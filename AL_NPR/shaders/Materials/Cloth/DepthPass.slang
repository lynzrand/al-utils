import Materials.Cloth.Bindings;
import Materials.Cloth.FabricSampling;
import Surface.Coverage;

public struct DepthInput
{
    public float4 position : SV_POSITION;
    public float4 uv : TEXCOORD0;
};

public struct ClothDepthCoverage
{
    public float opacity;
    public float cutoff;
};

public ClothDepthCoverage depthCoverage(float2 positionCS, float4 uv, bool shadow)
{
    float detail = _Detail_mask_01.Sample(sampler_Detail_mask_01, uv.xy).b;
    float distanceFade = max(mad(distance(cameraPosition, objectOrigin), -0.09090909, 1), 0);
    float4 base = _Create_main_texture.SampleBias(sampler_Create_main_texture, uv.xy, _Mip);
    float3 region = clothRegion(uv.xy);
    float wetness = clothWetness(mad(uv.xy, _LiquidTiling.zw, _LiquidTiling.xy), region);

    float cutoff = clothCutoff(detail);
    float sheer = 0;
#ifdef CLOTH_CUTOUT_LAYOUT
    float2 detailUV = mad(uv.xy, _Detail_mask_01_ST.xy, _Detail_mask_01_ST.zw);
    sheer = sheerAmount(region, _Detail_mask_01.Sample(sampler_Detail_mask_01, detailUV).r);
    base.rgb = tintCloth(base.rgb, uv.xy, _ColorMask, sampler_ColorMask);
    if (shadow)
        cutoff = _ShadowClip;
#endif
    float opacity = garmentOpacity<Fabric>(base, uv.xy, detail, distanceFade, wetness, sheer);
    float threshold = ditherThreshold(positionCS, screenSize, targetScaleBias, projectionSign);
    return { maskedClothOpacity(opacity, uv, threshold, true), cutoff };
}

public float4 clothDepth(DepthInput input, bool shadow)
{
    ClothDepthCoverage coverage = depthCoverage(input.position.xy, input.uv, shadow);
    clipCoverage(coverage.opacity, coverage.cutoff, alphaToMask != 0);
    return 0;
}
