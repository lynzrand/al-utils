#define CLOTH_MATERIAL_SLOT b2
#include "MaterialProperties.slang"

SamplerState sampler_Create_main_texture : register(s0);
SamplerState sampler_Detail_mask_01 : register(s1);
SamplerState sampler_ColorMask : register(s2);
SamplerState sampler_liquidmask : register(s3);
SamplerState sampler_Liquid : register(s4);
SamplerState sampler_Cloth_alpha_bot : register(s5);
SamplerState sampler_Cloth_alpha : register(s6);
Texture2D<float4> _Create_main_texture : register(t0);
Texture2D<float4> _Detail_mask_01 : register(t1);
Texture2D<float4> _ColorMask : register(t2);
Texture2D<float4> _liquidmask : register(t3);
Texture2D<float4> _Liquid : register(t4);
Texture2D<float4> _Cloth_alpha_bot : register(t5);
Texture2D<float4> _Cloth_alpha : register(t6);

// Cutout depth passes bind the dye mask and a separate shadow threshold.
Fabric sampleDepthFabric(float3 color, float2 uv, float3 region)
{
    float2 detailUV = mad(uv, _Detail_mask_01_ST.xy, _Detail_mask_01_ST.zw);
    float sheer = sheerAmount(region, _Detail_mask_01.Sample(sampler_Detail_mask_01, detailUV).r);
    return { tintCloth(color, uv, _ColorMask, sampler_ColorMask), sheer };
}

float garmentShadowCutoff(float detail)
{
    return _ShadowClip;
}
