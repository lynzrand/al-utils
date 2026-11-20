#define SKIN_FACE 0
#define SKIN_PREPASS 0
import Coverage;
import MaterialNoise;
import AmbientProbe;

#define SKIN_MATERIAL_SLOT b6
#include "Material.slang"
#include "../Skin/Frame.slang"

SamplerState samplerunity_SpecCube0 : register(s0);
SamplerComparisonState shadowCompare1 : register(s1);
SamplerState sampler_Create_dent_texture : register(s2);
SamplerState sampler_FluidTex : register(s3);
SamplerState sampler_Normal_map : register(s4);
SamplerState extraArraySampler : register(s5);
SamplerState sampler_Nip : register(s6);
SamplerState sampler_LiquidBump : register(s7);
SamplerState sampler_Create_main_texture : register(s8);
SamplerState sampler_Under_hair_texture : register(s9);
SamplerState detailArraySampler : register(s10);
SamplerState sampler_Detail_mask_02 : register(s11);
SamplerState sampler_Lamp : register(s12);
SamplerState sampler_shine_texture : register(s13);
SamplerState sampler_Cloth_alpha_bot : register(s14);
SamplerState sampler_Cloth_alpha : register(s15);
Texture2D<float4> _FluidTex : register(t0);
Texture2D<float4> _Normal_map : register(t1);
Texture2D<float4> _Nip : register(t2);
Texture2D<float4> _LiquidBump : register(t3);
Texture2D<float4> _Create_main_texture : register(t4);
Texture2D<float4> _Under_hair_texture : register(t5);
Texture2D<float4> _Detail_mask_02 : register(t6);
Texture2D<float4> _Create_dent_texture : register(t7);
Texture2D<float4> _Lamp : register(t8);
Texture2D<float4> _shine_texture : register(t9);
Texture2D<float4> _Cloth_alpha_bot : register(t10);
Texture2D<float4> _Cloth_alpha : register(t11);
TextureCube<float4> unity_SpecCube0 : register(t12);
Texture2D<float4> _MainLightShadowmapTexture : register(t13);
Texture2D<float4> _AdditionalLightsShadowmapTexture : register(t14);
Texture2DArray<float4> _TexEX : register(t15);
Texture2DArray<float4> _Detail_mask_01 : register(t16);

struct StageInput
{
    float4 positionCS : SV_POSITION;
    float4 positionWS : TEXCOORD0;
    float3 normalWS : TEXCOORD1;
    float4 tangentWS : TEXCOORD2;
    float4 uv0Uv1 : TEXCOORD3;
    float4 unused5 : TEXCOORD4;
    float4 unused6 : TEXCOORD5;
    float4 uv2Uv3 : TEXCOORD6;
    float4 positionOS : TEXCOORD7;
    float4 mainLightOS : TEXCOORD8;
    float3 normalOS : NORMAL0;
    bool frontFacing : SV_IsFrontFace;
}

#include "../Skin/FluidLayer.slang"
#include "Pigment.slang"

#include "../Skin/Lighting.slang"

#include "Color.slang"
