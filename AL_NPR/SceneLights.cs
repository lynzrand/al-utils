extern alias unity;
using Il2CppInterop.Runtime.Attributes;
using UnityEngine.Rendering.Universal;
using unity::UnityEngine;
using unity::UnityEngine.SceneManagement;
using Input = UnityEngine.Input;
using Physics = UnityEngine.Physics;
using QueryTriggerInteraction = UnityEngine.QueryTriggerInteraction;

namespace AL_NPR;

public sealed class EnvironmentLightingController : MonoBehaviour
{
    internal const uint CharacterLayer = 0x4;
    private const uint MapLayer = 0x2;
    private const float MaximumGain = 0.35f;
    private const float FillBudget = 0.28f;
    private const string CharacterKeyName = "Directional Light Camera";

    private readonly Dictionary<int, CharacterFill> fills = new();
    private SkinOverrides? skin;
    private RasterShadowMaps? rasterRoute;
    private bool rasterShadows = true;
    private readonly Dictionary<int, DirectRoute> routes = new();
    private readonly Dictionary<int, Light> suppressedCharacterLights = new();
    private Light? suppressedKey;
    private bool share, automaticKey = true;
    private int sceneHandle;
    private float nextScan;
    internal string Status { get; private set; } = "Stock lighting.";
    internal bool UsesShaderMapLights => skin?.UsesShaderMapLights == true;

    public EnvironmentLightingController(IntPtr pointer) : base(pointer) { }

    [HideFromIl2Cpp]
    internal void UseDirectLighting(string bundlePath)
    {
        if (skin is not null) return;
        var loaded = new SkinOverrides(bundlePath);
        Restore();
        skin = loaded;
    }

    [HideFromIl2Cpp]
    internal void Shutdown()
    {
        Restore();
        skin?.Dispose();
        skin = null;
    }

    [HideFromIl2Cpp]
    internal void SetMode(bool shareMapLights, bool replaceKey)
    {
        share = shareMapLights;
        automaticKey = replaceKey;
        Apply();
    }

    [HideFromIl2Cpp]
    internal void SetRasterShadows(bool enabled)
    {
        rasterShadows = enabled;
        Apply();
    }

    public void LateUpdate()
    {
        if (Input.GetKeyDown(KeyCode.F7)) SetMode(!share, automaticKey);
        if (Input.GetKeyDown(KeyCode.F8)) SetMode(share, !automaticKey);
        if (share && Time.unscaledTime >= nextScan) Apply();
        foreach (var light in suppressedCharacterLights.Values)
            if (light && light.enabled) light.enabled = false;
    }

    public void OnDisable() => Restore();

    [HideFromIl2Cpp]
    internal void Restore()
    {
        rasterRoute?.Dispose();
        rasterRoute = null;
        RestoreKey();
        foreach (var fill in fills.Values) fill.Destroy();
        fills.Clear();
        foreach (var route in routes.Values) route.Restore();
        routes.Clear();
        RestoreCharacterLights();
        skin?.Restore();
    }

    private void Apply()
    {
        nextScan = Time.unscaledTime + 0.35f;
        var scene = SceneManager.GetActiveScene();
        if (scene.handle != sceneHandle)
        {
            Restore();
            sceneHandle = scene.handle;
        }

        int map = LayerMask.GetMask("Map");
        int chara = LayerMask.GetMask("Chara", "Chara2");
        if (!share || map == 0 || chara == 0)
        {
            Restore();
            Status = "Stock lighting.";
            return;
        }

        if (skin is not null)
        {
            ApplyDirect(skin, map, chara);
            return;
        }

        var faces = FindNearbyFaces();
        if (faces.Count == 0)
        {
            Restore();
            Status = "No nearby skin renderers; stock lighting.";
            return;
        }

        float[] authored = new float[faces.Count], extra = new float[faces.Count];
        var candidates = new List<Candidate>();
        Light? key = null;
        foreach (var light in unity::UnityEngine.Object.FindObjectsOfType<Light>())
        {
            if (light.transform.parent == transform) continue;
            var data = light.GetComponent<UniversalAdditionalLightData>();
            if (!data) continue;
            bool reachesCharacter = (data.renderingLayers & CharacterLayer) != 0 && (light.cullingMask & chara) != 0;
            if (light.type == LightType.Directional && light.name == CharacterKeyName && reachesCharacter)
            {
                if (light.enabled || light == suppressedKey) key = light;
                continue;
            }
            if (!light.enabled || light.intensity <= 0f ||
                light.type is not (LightType.Directional or LightType.Point or LightType.Spot) ||
                light.bakingOutput.lightmapBakeType == LightmapBakeType.Baked)
                continue;

            if (!reachesCharacter &&
                ((light.cullingMask & map) == 0 || (data.renderingLayers & MapLayer) == 0 ||
                 light.type == LightType.Directional))
                continue;

            var input = new float[faces.Count];
            float strongest = 0f;
            for (int i = 0; i < faces.Count; i++)
            {
                var face = faces[i];
                if (reachesCharacter && (light.cullingMask & (1 << face.Layer)) == 0) continue;
                input[i] = EstimateDirectLight(light, face.Position);
                strongest = Math.Max(strongest, input[i]);
            }
            if (reachesCharacter)
                for (int i = 0; i < input.Length; i++) authored[i] += input[i];
            else if (strongest >= 0.012f)
                candidates.Add(new Candidate(light, data, input, strongest));
        }

        // Limit duplicated shadow maps and leave only sources that materially
        // reach the nearby faces. The budget constrains their combined input.
        candidates.Sort((a, b) => b.Strength.CompareTo(a.Strength));
        if (candidates.Count > 4) candidates.RemoveRange(4, candidates.Count - 4);
        foreach (var entry in candidates)
            for (int i = 0; i < faces.Count; i++) extra[i] += entry.Input[i];
        float gain = Math.Min(MaximumGain, FillBudget / Math.Max(FillBudget, extra.DefaultIfEmpty().Max()));

        var seen = new HashSet<int>();
        foreach (var candidate in candidates)
        {
            int id = candidate.Light.GetInstanceID();
            seen.Add(id);
            if (!fills.TryGetValue(id, out var fill))
            {
                fill = new CharacterFill(transform, candidate.Light.name);
                fills.Add(id, fill);
            }
            fill.Apply(candidate.Light, candidate.Data, chara, gain);
        }
        foreach (var id in fills.Keys.Where(id => !seen.Contains(id)).ToArray())
        {
            fills[id].Destroy();
            fills.Remove(id);
        }

        int covered = 0;
        for (int i = 0; i < faces.Count; i++)
            if (authored[i] + gain * extra[i] >= (suppressedKey ? 0.08f : 0.14f)) covered++;
        bool useEnvironment = automaticKey && covered == faces.Count;
        if (suppressedKey != key || !useEnvironment) RestoreKey();
        if (useEnvironment && key && key!.enabled)
        {
            key.enabled = false;
            suppressedKey = key;
        }
        Status = $"Character fills: {fills.Count}; gain: {gain:P0}; nearby lit faces: {covered}/{faces.Count}; " +
                 $"character key: {(suppressedKey ? "off" : "stock")} ({(automaticKey ? "auto" : "kept")}).";
    }

    [HideFromIl2Cpp]
    private void ApplyDirect(SkinOverrides overrides, int map, int chara)
    {
        var lights = unity::UnityEngine.Object.FindObjectsOfType<Light>();
        bool mapAvailable = false;
        for (int i = 0; i < SceneManager.sceneCount; i++)
            mapAvailable |= SceneManager.GetSceneAt(i).name.StartsWith("map", StringComparison.OrdinalIgnoreCase);
        if (!mapAvailable)
        {
            foreach (var light in lights)
            {
                if (!light.enabled || (light.cullingMask & map) == 0) continue;
                var data = light.GetComponent<UniversalAdditionalLightData>();
                if (data && (data.renderingLayers & MapLayer) != 0) mapAvailable = true;
            }
        }
        if (!mapAvailable)
        {
            Restore();
            Status = "No loaded map lighting; stock lighting.";
            return;
        }

        int materials = overrides.Apply();
        if (materials == 0)
        {
            Restore();
            Status = "No live skin or character materials could be overridden; stock lighting.";
            return;
        }

        if (overrides.UsesRasterShadows)
        {
            var sun = RasterShadowMaps.SelectSun(lights, map);
            if (rasterRoute is not null && (rasterRoute.Sun is null || rasterRoute.Sun != sun))
            {
                rasterRoute.Dispose();
                rasterRoute = null;
            }
            if (sun && rasterRoute is null)
            {
                try { rasterRoute = new RasterShadowMaps(sun!, shadowsEnabled: rasterShadows); }
                catch (Exception error)
                {
                    Restore();
                    Status = $"Raster sun routing failed ({error.GetType().Name}); stock lighting.";
                    BepInEx.Logging.Logger.CreateLogSource("AL Raster Shadows").LogWarning(error);
                    return;
                }
            }
            rasterRoute?.SetShadows(rasterShadows);
        }

        if (!automaticKey) RestoreCharacterLights();
        foreach (var light in lights)
        {
            var data = light.GetComponent<UniversalAdditionalLightData>();
            if (!data) continue;
            if (automaticKey && light.enabled && (light.cullingMask & chara) != 0 &&
                (light.name == CharacterKeyName ||
                 (!overrides.UsesShaderMapLights && data.renderingLayers == CharacterLayer)))
            {
                suppressedCharacterLights[light.GetInstanceID()] = light;
                light.enabled = false;
                continue;
            }
            if (overrides.UsesShaderMapLights || !light.enabled || light.intensity <= 0f || (light.cullingMask & map) == 0 ||
                (data.renderingLayers & MapLayer) == 0 ||
                light.type is not (LightType.Directional or LightType.Point or LightType.Spot) ||
                light.bakingOutput.lightmapBakeType == LightmapBakeType.Baked)
                continue;

            int id = light.GetInstanceID();
            if (!routes.TryGetValue(id, out var route))
            {
                if ((data.renderingLayers & CharacterLayer) != 0 && (light.cullingMask & chara) == chara)
                    continue;
                route = new DirectRoute(light, data, chara);
                routes.Add(id, route);
            }
            route.Apply();
        }
        string selection = overrides.UsesShaderMapLights ? "Shader map light selection" : $"Direct map light routes: {routes.Count}";
        if (overrides.UploadedMapDirectional is { } directional)
            selection += overrides.UsesMapDirectionalList
                ? $"; authored map directionals: {directional}"
                : $"; supplemental map directional: {directional}";
        if (overrides.UsesRasterShadows)
            selection += rasterRoute?.Sun is { } sun
                ? $"; raster sun: {sun.name} (shadows {(rasterShadows ? "on" : "off")})"
                : "; raster sun: no eligible map directional";
        Status = $"{selection}; overridden materials: {materials}; " +
                 $"suppressed character-only lights: {suppressedCharacterLights.Count}.";
    }

    private void RestoreCharacterLights()
    {
        foreach (var light in suppressedCharacterLights.Values)
            if (light) light.enabled = true;
        suppressedCharacterLights.Clear();
    }

    private void RestoreKey()
    {
        if (suppressedKey) suppressedKey!.enabled = true;
        suppressedKey = null;
    }

    [HideFromIl2Cpp]
    private static List<Face> FindNearbyFaces()
    {
        var faces = new List<Face>();
        var camera = Camera.main;
        if (!camera) return faces;
        var cameraPosition = camera.transform.position;
        float closest = float.PositiveInfinity;
        foreach (var renderer in unity::UnityEngine.Object.FindObjectsOfType<SkinnedMeshRenderer>())
        {
            if (!renderer.enabled || (renderer.renderingLayerMask & CharacterLayer) == 0) continue;
            bool isFace = false;
            foreach (var material in renderer.sharedMaterials)
                isFace |= material && material.shader &&
                    material.shader.name is "AL/skin_head" or "AL/skin_head/Environment";
            if (!isFace) continue;
            // Use the head bone so pitch and oversized bounds cannot move
            // this estimate as the camera tilts across a face.
            var position = renderer.bounds.center;
            foreach (var bone in renderer.bones)
            {
                if (!bone || bone.name != "cf_J_FaceBase") continue;
                position = bone.position;
                break;
            }
            float distance = Vector3.Distance(cameraPosition, position);
            closest = Math.Min(closest, distance);
            faces.Add(new Face(position, renderer.gameObject.layer, distance));
        }
        faces.RemoveAll(face => face.Distance > closest + 6f);
        return faces;
    }

    [HideFromIl2Cpp]
    private static float EstimateDirectLight(Light light, Vector3 face)
    {
        var transform = light.transform;
        var toward = light.type == LightType.Directional ? -transform.forward * 60f : transform.position - face;
        float strength = light.intensity * light.color.linear.grayscale;
        if (light.type != LightType.Directional)
        {
            float range2 = light.range * light.range;
            float distance2 = toward.sqrMagnitude;
            if (distance2 >= range2) return 0f;
            float fade = 1f - distance2 * distance2 / (range2 * range2);
            strength *= fade * fade / Math.Max(distance2, 0.0001f);
            if (light.type == LightType.Spot)
            {
                float outer = Mathf.Cos(0.5f * Mathf.Deg2Rad * light.spotAngle);
                float inner = Mathf.Cos(0.5f * Mathf.Deg2Rad * light.innerSpotAngle);
                float angle = Vector3.Dot(-toward.normalized, transform.forward);
                float cone = Mathf.Clamp01((angle - outer) / Mathf.Max(0.001f, inner - outer));
                strength *= cone * cone;
            }
        }
        if (strength < 0.005f || light.shadows == LightShadows.None) return strength;
        var origin = face + toward.normalized * 0.025f;
        // A collider is an indication of shadow, not a full render-time
        // shadow test. Keep these candidates in the budget conservatively.
        return Physics.Linecast(origin, face + toward, LayerMask.GetMask("Map"), QueryTriggerInteraction.Ignore)
            ? strength * 0.5f : strength;
    }

    private readonly record struct Face(Vector3 Position, int Layer, float Distance);
    private sealed record Candidate(Light Light, UniversalAdditionalLightData Data, float[] Input, float Strength);

    private sealed class DirectRoute(Light light, UniversalAdditionalLightData data, int chara)
    {
        private readonly uint layerBits = CharacterLayer & ~data.renderingLayers;
        private readonly int objectBits = chara & ~light.cullingMask;

        public void Apply()
        {
            data.renderingLayers |= layerBits;
            light.cullingMask |= objectBits;
        }

        public void Restore()
        {
            if (data) data.renderingLayers &= ~layerBits;
            if (light) light.cullingMask &= ~objectBits;
        }
    }
}
