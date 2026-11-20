import Coverage;

cbuffer Globals : register(b0)
{
    float2 screenSize : packoffset(c3);
    float alphaToMask : packoffset(c4.z);
    float3 cameraPosition : packoffset(c21);
    float projectionSign : packoffset(c22);
    float2 targetScaleBias : packoffset(c27);
};

cbuffer UnityPerDraw : register(b1)
{
    float3 objectOrigin : packoffset(c3);
};

#include "RegionMasks.slang"
#include "Opacity.slang"

struct DepthInput
{
    float4 position : SV_POSITION;
#ifdef CLOTH_NORMALS
    float3 worldNormal : TEXCOORD0;
    float4 uv : TEXCOORD1;
#else
    float4 uv : TEXCOORD0;
#endif
};

[shader("fragment")]
float4 main(DepthInput input) : SV_Target0
{
    float detail = _Detail_mask_01.Sample(sampler_Detail_mask_01, input.uv.xy).b;
    float distanceFade = max(mad(distance(cameraPosition, objectOrigin), -0.09090909, 1), 0);
    float4 base = _Create_main_texture.SampleBias(sampler_Create_main_texture, input.uv.xy, _Mip);
    float3 region = clothRegion(input.uv.xy);
    float wetness = clothWetness(mad(input.uv.xy, _LiquidTiling.zw, _LiquidTiling.xy), region);
    float sheer = 0;
#ifdef CLOTH_CUTOUT
    float2 detailUV = mad(input.uv.xy, _Detail_mask_01_ST.xy, _Detail_mask_01_ST.zw);
    sheer = sheerAmount(region, _Detail_mask_01.Sample(sampler_Detail_mask_01, detailUV).r);
    base.rgb = tintCloth(base.rgb, input.uv.xy);
#endif
    float opacity = garmentOpacity(base, input.uv.xy, detail, distanceFade, wetness, sheer);
    float threshold = ditherThreshold(input.position.xy, screenSize, targetScaleBias, projectionSign);
    opacity = maskedClothOpacity(opacity, input.uv, threshold, true);

#if defined(CLOTH_SHADOW) && defined(CLOTH_CUTOUT)
    float cutoff = _ShadowClip;
#else
    float cutoff = clothCutoff(detail);
#endif
#ifdef CLOTH_NORMALS
    clip(opacity - cutoff);
    return float4(normalize(input.worldNormal), 0);
#else
    clipCoverage(opacity, cutoff, alphaToMask != 0);
    return 0;
#endif
}
