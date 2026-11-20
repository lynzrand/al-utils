#define CLOTH_MATERIAL_SLOT b2
#include "MaterialProperties.slang"

SamplerState sampler_Create_main_texture : register(s0);
SamplerState sampler_Detail_mask_01 : register(s1);
SamplerState sampler_Liquid : register(s2);
SamplerState sampler_liquidmask : register(s3);
SamplerState sampler_Cloth_alpha_bot : register(s4);
SamplerState sampler_Cloth_alpha : register(s5);
Texture2D<float4> _Create_main_texture : register(t0);
Texture2D<float4> _Detail_mask_01 : register(t1);
Texture2D<float4> _Liquid : register(t2);
Texture2D<float4> _liquidmask : register(t3);
Texture2D<float4> _Cloth_alpha_bot : register(t4);
Texture2D<float4> _Cloth_alpha : register(t5);

Fabric sampleDepthFabric(float3 color, float2 uv, float3 region)
{
    return { color, 0 };
}

float garmentShadowCutoff(float detail)
{
    return clothCutoff(detail);
}
