cbuffer Globals : register(b0)
{
    float4 _ScaledScreenParams : packoffset(c3);
    float4 mipAndAlpha : packoffset(c4);
    float4 _MainLightPosition : packoffset(c5);
    float4 _MainLightColor : packoffset(c6);
    float4 _FPParams0 : packoffset(c15);
    float4 _FPParams1 : packoffset(c16);
    float4 _FPParams2 : packoffset(c17);
    float4 _WorldSpaceCameraPos : packoffset(c25);
    float4 _ProjectionParams : packoffset(c26);
    float4 unity_OrthoParams : packoffset(c29);
    float4 _ScaleBiasRt : packoffset(c31);
    float4 glstate_lightmodel_ambient : packoffset(c59);
    float4 unity_FogParams : packoffset(c64);
    float4 unity_FogColor : packoffset(c65);
    float4 viewX : packoffset(c70);
    float4 viewY : packoffset(c71);
    float4 viewZ : packoffset(c72);
};

cbuffer UnityPerDraw : register(b4)
{
    float4 objectOrigin : packoffset(c3);
    float4 renderingLayer : packoffset(c10);
    float4 specCubeDecode : packoffset(c15);
    SHCoefficients probe : packoffset(c25);
};

SamplerState samplerunity_SpecCube0 : register(s0);
#ifdef CLOTH_PREPASS
SamplerState sampler_Detail_mask_01 : register(s1);
#else
SamplerComparisonState shadowCompare1 : register(s1);
#endif
SamplerState sampler_FluidTex : register(s2);
SamplerState sampler_Normal_map : register(s3);
SamplerState sampler_LiquidBump : register(s4);
SamplerState sampler_Liquid : register(s5);
SamplerState sampler_liquidmask : register(s6);
SamplerState sampler_Create_main_texture : register(s7);
SamplerState sampler_ColorMask : register(s8);
SamplerState matcapSampler : register(s9);
SamplerState sampler_Matcap_mask : register(s10);
#ifdef CLOTH_PREPASS
SamplerState sampler_Detail_mask_02 : register(s11);
SamplerState sampler_Lamp : register(s12);
SamplerState sampler_Cloth_alpha_bot : register(s13);
SamplerState sampler_Cloth_alpha : register(s14);
#else
SamplerState sampler_Detail_mask_01 : register(s11);
SamplerState sampler_Detail_mask_02 : register(s12);
SamplerState sampler_Lamp : register(s13);
SamplerState sampler_Cloth_alpha_bot : register(s14);
SamplerState sampler_Cloth_alpha : register(s15);
#endif
Texture2D<float4> _FluidTex : register(t0);
Texture2D<float4> _Normal_map : register(t1);
Texture2D<float4> _Liquid : register(t2);
Texture2D<float4> _liquidmask : register(t3);
Texture2D<float4> _LiquidBump : register(t4);
Texture2D<float4> _Create_main_texture : register(t5);
Texture2D<float4> _ColorMask : register(t6);
Texture2D<float4> _Matcap_mask : register(t7);
Texture2D<float4> _Detail_mask_01 : register(t8);
Texture2D<float4> _Detail_mask_02 : register(t9);
Texture2D<float4> _Lamp : register(t10);
Texture2D<float4> _Cloth_alpha_bot : register(t11);
Texture2D<float4> _Cloth_alpha : register(t12);
TextureCube<float4> unity_SpecCube0 : register(t13);
#ifdef CLOTH_PREPASS
Texture2DArray<float4> _TexTAMatcap : register(t14);
#else
Texture2D<float4> _MainLightShadowmapTexture : register(t14);
Texture2D<float4> _AdditionalLightsShadowmapTexture : register(t15);
Texture2DArray<float4> _TexTAMatcap : register(t16);
#endif
