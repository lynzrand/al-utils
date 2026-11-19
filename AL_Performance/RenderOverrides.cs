extern alias unity;
using UnityEngine.Rendering.Universal;
using unity::UnityEngine;
using unity::UnityEngine.Rendering;

namespace AL_Performance;

internal sealed class RenderOverrides
{
    private UniversalRenderPipelineAsset? asset;
    private AssetSettings original, applied;
    private readonly List<ScriptableRendererFeature> features = new();
    private readonly List<(UniversalAdditionalCameraData Camera, bool Shadows, bool Post)> cameras = new();
    private readonly Dictionary<int, (UniversalAdditionalLightData Data, SoftShadowQuality Original)> lights = new();
    private SoftShadowQuality? appliedFilter;
    private float nextLightScan;

    internal void Apply(BenchmarkRequest? request, float configuredScale, int configuredMsaa,
        bool configuredDisableFsr, ShadowFilter configuredShadowFilter)
    {
        float scale = request?.Scale ?? configuredScale;
        int msaa = request?.Msaa ?? configuredMsaa;
        bool disableFsr = request?.DisableFsr ?? configuredDisableFsr;
        bool useFsr = request?.Fsr == true && scale is > 0 and < 1;
        int filter = request?.ShadowFilter ?? (int)configuredShadowFilter;
        var overrides = new AssetSettings(
            scale > 0 ? Math.Clamp(scale, 0.5f, 1f) : null,
            disableFsr ? UpscalingFilterSelection.Auto : useFsr ? UpscalingFilterSelection.FSR : null,
            request?.MainShadowResolution is 512 or 1024 or 2048 or 4096 ? request.MainShadowResolution : null,
            request?.ShadowCascades is >= 1 and <= 4 ? request.ShadowCascades : null,
            request?.ShadowDistance > 0 ? request.ShadowDistance : null,
            msaa is 1 or 2 or 4 or 8 ? msaa : null,
            request?.DisableAdditionalShadows == true ? false : null,
            request?.DisableMainShadows == true ? false : null,
            filter is >= 1 and <= 3 ? (SoftShadowQuality)filter : null);
        bool featureOverride = request?.DisableFeatures is { Length: > 0 };
        bool cameraOverride = request is { DisableShadows: true } or { DisablePost: true };

        if (overrides.IsEmpty && !featureOverride && !cameraOverride)
        {
            Restore();
            return;
        }

        var activeAsset = GraphicsSettings.currentRenderPipeline?.TryCast<UniversalRenderPipelineAsset>();
        if (asset != activeAsset)
        {
            Restore();
            asset = activeAsset;
        }
        if (!asset) return;

        ApplyAssetSettings(overrides);
        ApplyLightFilter(overrides.Filter);

        if (featureOverride)
        {
            foreach (var renderer in asset!.m_RendererDataList)
            {
                if (!renderer) continue;
                foreach (var feature in renderer.rendererFeatures)
                {
                    if (!feature || !feature.isActive) continue;
                    if (!request!.DisableFeatures!.Contains(feature.name, StringComparer.OrdinalIgnoreCase)) continue;
                    if (!features.Any(existing => existing == feature)) features.Add(feature);
                    feature.SetActive(false);
                }
            }
        }

        if (cameraOverride)
        {
            cameras.RemoveAll(entry => !entry.Camera);
            foreach (var camera in Camera.allCameras)
            {
                if (!camera) continue;
                var data = camera.GetComponent<UniversalAdditionalCameraData>();
                if (!data) continue;
                if (!cameras.Any(entry => entry.Camera == data))
                    cameras.Add((data!, data!.renderShadows, data.renderPostProcessing));
                if (request!.DisableShadows) data!.renderShadows = false;
                if (request.DisablePost) data!.renderPostProcessing = false;
            }
        }
    }

    internal void Restore()
    {
        if (asset) ApplyAssetSettings(default);
        ApplyLightFilter(null);
        foreach (var feature in features)
            if (feature) feature.SetActive(true);
        foreach (var (camera, shadows, post) in cameras)
        {
            if (!camera) continue;
            camera.renderShadows = shadows;
            camera.renderPostProcessing = post;
        }
        features.Clear();
        cameras.Clear();
        original = applied = default;
        asset = null;
    }

    private void ApplyAssetSettings(AssetSettings requested)
    {
        if (requested.IsEmpty && applied.IsEmpty) return;
        var current = AssetSettings.Read(asset!);
        var next = new AssetSettings(
            Reconcile(requested.Scale, current.Scale, applied.Scale, ref original.Scale),
            Reconcile(requested.Upscaling, current.Upscaling, applied.Upscaling, ref original.Upscaling),
            Reconcile(requested.MainShadowResolution, current.MainShadowResolution, applied.MainShadowResolution, ref original.MainShadowResolution),
            Reconcile(requested.Cascades, current.Cascades, applied.Cascades, ref original.Cascades),
            Reconcile(requested.ShadowDistance, current.ShadowDistance, applied.ShadowDistance, ref original.ShadowDistance),
            Reconcile(requested.Msaa, current.Msaa, applied.Msaa, ref original.Msaa),
            Reconcile(requested.AdditionalShadows, current.AdditionalShadows, applied.AdditionalShadows, ref original.AdditionalShadows),
            Reconcile(requested.MainShadows, current.MainShadows, applied.MainShadows, ref original.MainShadows),
            Reconcile(requested.Filter, current.Filter, applied.Filter, ref original.Filter));
        next.Apply(asset!);
        applied = requested;
    }

    private void ApplyLightFilter(SoftShadowQuality? filter)
    {
        if (filter is null)
        {
            foreach (var (data, originalQuality) in lights.Values)
            {
                if (data && data.softShadowQuality == appliedFilter) data.softShadowQuality = originalQuality;
            }
            lights.Clear();
            appliedFilter = null;
            nextLightScan = 0;
            return;
        }

        if (appliedFilter == filter && Time.realtimeSinceStartup < nextLightScan) return;
        nextLightScan = Time.realtimeSinceStartup + 1;
        foreach (var id in new List<int>(lights.Keys))
            if (!lights[id].Data) lights.Remove(id);

        var activeLights = unity::UnityEngine.Object.FindObjectsByType<Light>(FindObjectsSortMode.None);
        for (int index = 0; index < activeLights.Length; index++)
        {
            var light = activeLights[index];
            if (!light || light.shadows != LightShadows.Soft) continue;
            var data = light.GetComponent<UniversalAdditionalLightData>();
            if (!data) continue;
            int id = data!.GetInstanceID();
            var current = data.softShadowQuality;
            if (!lights.ContainsKey(id) || current != appliedFilter) lights[id] = (data, current);
            if (current != filter) data.softShadowQuality = filter.Value;
        }
        appliedFilter = filter;
    }

    // Restore only fields this plugin owned. If the game changed one while overridden,
    // keep that new game value as the one to restore when the override is removed.
    private static T? Reconcile<T>(T? requested, T? current, T? applied, ref T? original) where T : struct
    {
        if (requested is null)
        {
            var restore = Nullable.Equals(current, applied) ? original : null;
            original = null;
            return restore;
        }

        if (!Nullable.Equals(current, applied)) original = current;
        return requested;
    }

    internal static object Describe(UniversalRenderPipelineAsset asset)
    {
        var renderers = new List<object>();
        foreach (var renderer in asset.m_RendererDataList)
        {
            if (!renderer) continue;
            var features = new List<object>();
            foreach (var feature in renderer.rendererFeatures)
            {
                if (feature) features.Add(new { feature.name, Active = feature.isActive });
            }
            renderers.Add(new { renderer.name, Features = features });
        }

        return new
        {
            asset.name, asset.renderScale, Upscaling = asset.upscalingFilter.ToString(), asset.msaaSampleCount,
            asset.supportsHDR, asset.supportsCameraDepthTexture, asset.supportsCameraOpaqueTexture,
            asset.mainLightShadowmapResolution, asset.additionalLightsShadowmapResolution,
            asset.supportsMainLightShadows, asset.supportsAdditionalLightShadows, asset.supportsSoftShadows,
            SoftShadowQuality = asset.softShadowQuality.ToString(),
            asset.shadowCascadeCount, asset.shadowDistance, asset.useSRPBatcher, Renderers = renderers
        };
    }

    private struct AssetSettings(float? scale, UpscalingFilterSelection? upscaling,
        int? mainShadowResolution, int? cascades, float? shadowDistance, int? msaa,
        bool? additionalShadows, bool? mainShadows, SoftShadowQuality? filter)
    {
        internal float? Scale = scale;
        internal UpscalingFilterSelection? Upscaling = upscaling;
        internal int? MainShadowResolution = mainShadowResolution;
        internal int? Cascades = cascades;
        internal float? ShadowDistance = shadowDistance;
        internal int? Msaa = msaa;
        internal bool? AdditionalShadows = additionalShadows;
        internal bool? MainShadows = mainShadows;
        internal SoftShadowQuality? Filter = filter;

        internal readonly bool IsEmpty => Scale is null && Upscaling is null && MainShadowResolution is null
            && Cascades is null && ShadowDistance is null && Msaa is null && AdditionalShadows is null && MainShadows is null
            && Filter is null;

        internal static AssetSettings Read(UniversalRenderPipelineAsset asset) => new(
            asset.renderScale, asset.upscalingFilter, asset.mainLightShadowmapResolution,
            asset.shadowCascadeCount, asset.shadowDistance, asset.msaaSampleCount,
            asset.supportsAdditionalLightShadows, asset.supportsMainLightShadows, asset.softShadowQuality);

        internal readonly void Apply(UniversalRenderPipelineAsset asset)
        {
            if (Scale is { } scale && asset.renderScale != scale) asset.renderScale = scale;
            if (Upscaling is { } upscaling && asset.upscalingFilter != upscaling) asset.upscalingFilter = upscaling;
            if (MainShadowResolution is { } resolution && asset.mainLightShadowmapResolution != resolution)
                asset.mainLightShadowmapResolution = resolution;
            if (Cascades is { } cascades && asset.shadowCascadeCount != cascades) asset.shadowCascadeCount = cascades;
            if (ShadowDistance is { } distance && asset.shadowDistance != distance) asset.shadowDistance = distance;
            if (Msaa is { } msaa && asset.msaaSampleCount != msaa) asset.msaaSampleCount = msaa;
            if (AdditionalShadows is { } additional && asset.supportsAdditionalLightShadows != additional)
                asset.supportsAdditionalLightShadows = additional;
            if (MainShadows is { } main && asset.supportsMainLightShadows != main)
                asset.supportsMainLightShadows = main;
            if (Filter is { } quality && asset.softShadowQuality != quality) asset.softShadowQuality = quality;
        }
    }
}
