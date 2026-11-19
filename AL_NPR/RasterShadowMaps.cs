extern alias unity;
using UnityEngine.Rendering.Universal;
using unity::UnityEngine;

namespace AL_NPR;

// Route an explicitly selected authored directional through URP's main atlas.
// Holding this route while toggling shadows keeps the light slots and shading
// identical during an on/off timing comparison. Dispose restores authored state.
public sealed class RasterShadowMaps : IDisposable
{
    private readonly Light light;
    private readonly Light? previousSun;
    private readonly UniversalAdditionalLightData data;
    private readonly LightShadows previousShadows;
    private readonly int previousCullingMask;
    private readonly bool previousCustomShadowLayers;
    private readonly uint previousShadowLayers;
    private bool disposed;
    internal Light? Sun => light ? light : null;

    public RasterShadowMaps(Light sun, bool includeCharacterCasters = true, bool shadowsEnabled = true)
    {
        if (!sun || sun.type != LightType.Directional)
            throw new ArgumentException("Select an existing authored directional.", nameof(sun));
        light = sun;
        data = sun.GetComponent<UniversalAdditionalLightData>();
        if (!data) throw new ArgumentException("The directional has no URP light data.", nameof(sun));
        previousSun = RenderSettings.sun;
        previousShadows = light.shadows;
        previousCullingMask = light.cullingMask;
        previousCustomShadowLayers = data.customShadowLayers;
        previousShadowLayers = data.shadowRenderingLayers;

        try
        {
            if (includeCharacterCasters)
            {
                light.cullingMask |= LayerMask.GetMask("Chara", "Chara2");
                uint layers = previousCustomShadowLayers ? previousShadowLayers : data.renderingLayers;
                data.customShadowLayers = true;
                data.shadowRenderingLayers = layers | EnvironmentLightingController.CharacterLayer;
            }
            RenderSettings.sun = light;
            SetShadows(shadowsEnabled);
        }
        catch
        {
            Dispose();
            throw;
        }
    }

    public void SetShadows(bool enabled)
    {
        if (disposed) throw new ObjectDisposedException(nameof(RasterShadowMaps));
        light.shadows = enabled ? (previousShadows == LightShadows.None ? LightShadows.Soft : previousShadows) : LightShadows.None;
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        if (light)
        {
            light.shadows = previousShadows;
            light.cullingMask = previousCullingMask;
        }
        if (data)
        {
            data.customShadowLayers = previousCustomShadowLayers;
            data.shadowRenderingLayers = previousShadowLayers;
        }
        if (RenderSettings.sun == light) RenderSettings.sun = previousSun ? previousSun : null;
    }

    // The shadow slot follows an authored map light, never the camera key or
    // a water-only directional. Instance ID breaks equal-intensity ties so
    // a different FindObjectsOfType order cannot change the selected sun.
    internal static Light? SelectSun(IEnumerable<Light> lights, int mapMask)
    {
        Light? selected = null;
        foreach (var candidate in lights)
        {
            if (!candidate || !candidate.isActiveAndEnabled || candidate.type != LightType.Directional ||
                !float.IsFinite(candidate.intensity) || candidate.intensity <= 0f ||
                (candidate.cullingMask & mapMask) == 0 ||
                candidate.bakingOutput.lightmapBakeType == LightmapBakeType.Baked ||
                candidate.name.Contains("Camera", StringComparison.OrdinalIgnoreCase) ||
                candidate.name.Contains("Water", StringComparison.OrdinalIgnoreCase)) continue;
            var settings = candidate.GetComponent<UniversalAdditionalLightData>();
            if (!settings || (settings.renderingLayers & 2) == 0) continue;
            var color = candidate.color;
            if (!float.IsFinite(color.r) || !float.IsFinite(color.g) || !float.IsFinite(color.b) ||
                (color.r <= 0f && color.g <= 0f && color.b <= 0f)) continue;
            if (!selected || candidate.intensity > selected!.intensity ||
                (candidate.intensity == selected!.intensity && candidate.GetInstanceID() < selected.GetInstanceID()))
                selected = candidate;
        }
        return selected;
    }
}
