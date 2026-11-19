extern alias unity;
using HarmonyLib;
using Il2CppInterop.Runtime.InteropTypes.Arrays;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.Universal.Internal;
using unity::UnityEngine;
using CommandBuffer = unity::UnityEngine.Rendering.CommandBuffer;
using VisibleLight = unity::UnityEngine.Rendering.VisibleLight;

namespace AL_NPR;

internal sealed class MapDirectional : IDisposable
{
    private const int MaxDirectionals = 32;
    private const int MapRenderingLayer = 2;
    private static MapDirectional? instance;
    private readonly Harmony hook = new("local.al.npr.map-directional");
    private readonly ComputeBuffer buffer;
    private readonly Il2CppStructArray<Vector4> upload;
    private readonly Il2CppSystem.Array uploadData;
    private readonly Vector4[] lastValues;
    private readonly bool useList, useVisibility, useRasterShadows;
    private readonly List<Directional> entries = new();
    private readonly List<Directional> capturedDirections = new();
    private readonly int bufferId = Shader.PropertyToID("ALMapLighting");
    private readonly int visibilityId = Shader.PropertyToID("_ALDirectionalVisibility");
    private readonly int mapObjects = LayerMask.GetMask("Map");
    private int lastCount = -1;
    private int lastWidth, lastHeight;
    private bool lastRasterShadow;
    private Camera? capturedCamera;
    private static FrozenVisibility? frozen;
    private bool uploaded, failed, overflowReported;
    internal bool Active { get; set; }
    internal string UploadedLight { get; private set; } = "none";

    internal MapDirectional(bool useList, bool useVisibility = false, bool useRasterShadows = false)
    {
        if (instance is not null)
            throw new InvalidOperationException("Map directional binding is already active.");
        this.useList = useList;
        this.useVisibility = useVisibility;
        this.useRasterShadows = useRasterShadows;
        int slots = useList ? 1 + 2 * MaxDirectionals : 3;
        lastValues = new Vector4[slots];
        upload = new Il2CppStructArray<Vector4>(slots);
        uploadData = new Il2CppSystem.Array(upload.Pointer);
        buffer = new ComputeBuffer(slots, 16, ComputeBufferType.Constant);
        instance = this;
        try
        {
            var method = AccessTools.Method(typeof(ForwardLights), nameof(ForwardLights.SetupLights));
            hook.Patch(method, prefix: new HarmonyMethod(typeof(MapDirectional), nameof(BindCamera)));
            if (useList)
            {
                var create = AccessTools.Method(typeof(UniversalRenderPipeline), nameof(UniversalRenderPipeline.CreateShadowData));
                hook.Patch(create, postfix: new HarmonyMethod(typeof(MapDirectional), nameof(ScaleMapShadowRequests)));
                var allocate = AccessTools.Method(typeof(ShadowUtils), nameof(ShadowUtils.ShadowRTReAllocateIfNeeded));
                hook.Patch(allocate, prefix: new HarmonyMethod(typeof(MapDirectional), nameof(SelectAtlasDepth)));
            }
        }
        catch
        {
            hook.UnpatchSelf();
            instance = null;
            buffer.Release();
            throw;
        }
    }

    private static void SelectAtlasDepth(ref int bits, string name)
    {
        if (instance is { Active: true } && Plugin.HigherShadowDepthPrecision?.Value == true &&
            name == "_AdditionalLightsShadowmapTexture")
            bits = Math.Max(bits, 32);
    }

    // URP builds fresh requests for every camera. Adjust them before packing so
    // the caster pass and receiver constants both see the resulting slice sizes.
    // Light components and the shared pipeline asset retain their authored values.
    private static void ScaleMapShadowRequests(ContextContainer __0, UniversalShadowData __result)
    {
        if (instance is not { Active: true } binding || Plugin.HigherMapShadowResolution?.Value != true ||
            !__result.supportsAdditionalLightShadows) return;
        var cap = Math.Min(8192, SystemInfo.maxTextureSize);
        var visible = __0.Get<UniversalLightData>().visibleLights;
        var sizes = __result.resolution;
        if (visible.Length != sizes.Count) return;

        bool increased = false;
        for (int i = 0; i < visible.Length; i++)
        {
            var entry = visible[i];
            if (entry.lightType is not (LightType.Spot or LightType.Point)) continue;
            int size = sizes[i];
            if (size <= 0 || size >= cap) continue;
            var light = entry.light;
            if (!light || light.shadows == LightShadows.None || (light.cullingMask & binding.mapObjects) == 0 ||
                (light.renderingLayerMask & MapRenderingLayer) == 0) continue;
            sizes[i] = Math.Min(size * 2, cap);
            increased = true;
        }
        if (increased)
        {
            __result.additionalLightsShadowmapWidth = Math.Max(__result.additionalLightsShadowmapWidth,
                Math.Min(__result.additionalLightsShadowmapWidth * 2, cap));
            __result.additionalLightsShadowmapHeight = Math.Max(__result.additionalLightsShadowmapHeight,
                Math.Min(__result.additionalLightsShadowmapHeight * 2, cap));
        }
    }

    private static void BindCamera(UnsafeCommandBuffer __0, UniversalCameraData __2, UniversalLightData __3)
    {
        if (instance is not { failed: false } binding) return;
        try
        {
            binding.Bind(CommandBufferHelpers.GetNativeCommandBuffer(__0), __2, __3);
        }
        catch (Exception error)
        {
            binding.failed = true;
            binding.UploadedLight = $"binding failed ({error.GetType().Name})";
            BepInEx.Logging.Logger.CreateLogSource("AL Map Directional").LogWarning(error);
        }
    }

    private void Bind(CommandBuffer command, UniversalCameraData camera, UniversalLightData lights)
    {
        bool changed = useList ? PackList(command, camera, lights) : PackPrimary(camera, lights);
        if (!uploaded || changed)
        {
            command.SetBufferData(buffer, uploadData);
            uploaded = true;
        }
        command.SetGlobalConstantBuffer(buffer, bufferId, 0, 16 * lastValues.Length);
    }

    private bool PackList(CommandBuffer command, UniversalCameraData cameraData, UniversalLightData lights)
    {
        Camera camera = cameraData.camera;
        bool rasterShadow = false;
        entries.Clear();
        if (Active)
        {
            var visible = lights.visibleLights;
            for (int index = 0; index < visible.Length; index++)
            {
                if (TryRead(visible[index], out var entry, out var light))
                {
                    if (useRasterShadows && index == lights.mainLightIndex && cameraData.maxShadowDistance > 0f &&
                        light!.shadows != LightShadows.None && UniversalRenderPipeline.asset.supportsMainLightShadows)
                    {
                        var color = entry.Color;
                        color.w = 1f;
                        entry = entry with { Color = color };
                        rasterShadow = true;
                    }
                    entries.Add(entry);
                }
            }
        }

        // A slot promotion can reorder Unity's light list. Keep summation
        // order stable for the set of lights supplied to this camera.
        entries.Sort(static (a, b) => a.Id.CompareTo(b.Id));
        int count = Math.Min(entries.Count, MaxDirectionals);
        // A truncated main entry cannot receive this atlas. Leave the shader's
        // filter disabled rather than spend a PCF lookup no light consumes.
        rasterShadow &= entries.Take(count).Any(entry => entry.Color.w != 0f);
        if (useVisibility && camera == Camera.main)
        {
            capturedCamera = camera;
            capturedDirections.Clear();
            for (int index = 0; index < count; index++)
                capturedDirections.Add(entries[index]);
        }
        if (entries.Count > MaxDirectionals && !overflowReported)
        {
            overflowReported = true;
            BepInEx.Logging.Logger.CreateLogSource("AL Map Directional")
                .LogWarning($"A camera has more than {MaxDirectionals} eligible map directionals.");
        }
        var visibility = useVisibility && frozen is { } frame && frame.Matches(camera, entries, count) ? frame.Texture : null;
        int width = visibility ? visibility!.width : 0;
        int height = visibility ? visibility!.height : 0;
        if (visibility) command.SetGlobalTexture(visibilityId, visibility!);
        bool changed = lastCount != count || lastWidth != width || lastHeight != height || lastRasterShadow != rasterShadow;
        if (changed)
        {
            // The shader reads the count as a uint, so preserve its bits.
            upload[0] = new Vector4(BitConverter.Int32BitsToSingle(count),
                BitConverter.Int32BitsToSingle(width != 0 || rasterShadow ? 1 : 0),
                BitConverter.Int32BitsToSingle(width), BitConverter.Int32BitsToSingle(height));
            lastWidth = width;
            lastHeight = height;
            lastRasterShadow = rasterShadow;
        }
        for (int index = 0; index < count; index++)
        {
            changed |= Write(1 + 2 * index, entries[index].Direction);
            changed |= Write(2 + 2 * index, entries[index].Color);
        }
        for (int index = count; index < lastCount; index++)
        {
            changed |= Write(1 + 2 * index, Vector4.zero);
            changed |= Write(2 + 2 * index, Vector4.zero);
        }
        lastCount = count;
        if (changed) UploadedLight = count == 0 ? "none" : string.Join(", ",
            entries.Take(count).Select(entry => entry.Light.name));
        return changed;
    }

    private bool PackPrimary(UniversalCameraData camera, UniversalLightData lights)
    {
        Vector4 direction = Vector4.zero, color = Vector4.zero, flags = Vector4.zero;
        UploadedLight = "none";
        int index = lights.mainLightIndex;
        var visible = lights.visibleLights;
        if (Active && (uint)index < (uint)visible.Length &&
            TryRead(visible[index], out var entry, out var light))
        {
            // Forward+ already retains the other visible directionals in its
            // additional-light list in bundles that predate the authored list.
            direction = -visible[index].localToWorldMatrix.GetColumn(2);
            direction.w = 1f;
            color = entry.Color;
            if (camera.maxShadowDistance > 0f && light!.shadows != LightShadows.None &&
                UniversalRenderPipeline.asset.supportsMainLightShadows)
                flags.x = 1f;
            UploadedLight = entry.Light.name;
        }
        return Write(0, direction) | Write(1, color) | Write(2, flags);
    }

    private bool TryRead(VisibleLight visible, out Directional entry, out Light? light)
    {
        entry = default;
        light = null;
        if (visible.lightType != LightType.Directional) return false;
        light = visible.light;
        if (!light || (light!.cullingMask & mapObjects) == 0 ||
            light.bakingOutput.lightmapBakeType == LightmapBakeType.Baked) return false;
        var data = light.GetComponent<UniversalAdditionalLightData>();
        var rgb = visible.finalColor;
        if (!data || (data.renderingLayers & MapRenderingLayer) == 0 ||
            !float.IsFinite(rgb.r) || !float.IsFinite(rgb.g) || !float.IsFinite(rgb.b) ||
            (rgb.r <= 0f && rgb.g <= 0f && rgb.b <= 0f)) return false;

        var column = visible.localToWorldMatrix.GetColumn(2);
        var toward = new Vector3(-column.x, -column.y, -column.z).normalized;
        if (toward.sqrMagnitude == 0f) return false;
        entry = new Directional(light.GetInstanceID(), light,
            new Vector4(toward.x, toward.y, toward.z, 0f), new Vector4(rgb.r, rgb.g, rgb.b, 0f));
        return true;
    }

    private bool Write(int slot, Vector4 value)
    {
        if (lastValues[slot].Equals(value)) return false;
        lastValues[slot] = value;
        upload[slot] = value;
        return true;
    }

    public void Dispose()
    {
        hook.UnpatchSelf();
        instance = null;
        frozen = null;
        buffer.Release();
    }

    private readonly record struct Directional(int Id, Light Light, Vector4 Direction, Vector4 Color);

    internal static (int[] Ids, Vector4[] Directions) VisibilityInputs(Camera camera)
    {
        if (instance is not { useVisibility: true, Active: true } binding || binding.capturedCamera != camera)
            throw new InvalidOperationException("The experimental visibility skin shaders have not seen this camera.");
        return (binding.capturedDirections.Select(entry => entry.Id).ToArray(),
            binding.capturedDirections.Select(entry => entry.Direction).ToArray());
    }

    internal static void PublishVisibility(Camera camera, int[] ids, Vector4[] directions, RenderTexture texture)
        => frozen = new FrozenVisibility(camera, camera.worldToCameraMatrix, camera.projectionMatrix, ids, directions, texture);

    internal static void ClearVisibility() => frozen = null;

    private sealed record FrozenVisibility(Camera Camera, Matrix4x4 View, Matrix4x4 Projection, int[] Ids,
        Vector4[] Directions, RenderTexture Texture)
    {
        internal bool Matches(Camera camera, List<Directional> entries, int count)
        {
            if (!Texture || Time.timeScale != 0f || camera != Camera || count != Ids.Length ||
                camera.pixelWidth != Texture.width || camera.pixelHeight != Texture.height ||
                !camera.worldToCameraMatrix.Equals(View) || !camera.projectionMatrix.Equals(Projection)) return false;
            for (int index = 0; index < count; index++)
                if (entries[index].Id != Ids[index] || !entries[index].Direction.Equals(Directions[index])) return false;
            return true;
        }
    }
}
