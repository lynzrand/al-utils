import AmbientProbe;

public struct ClothInput
{
    public float4 positionCS : SV_Position;
    public float4 positionWS : TEXCOORD0;
    public float3 normalWS : TEXCOORD1;
    public float4 tangentWS : TEXCOORD2;
    // These slots keep the input registers aligned with the game vertex signature.
    public float4 unused3 : TEXCOORD3;
    public float4 unused4 : TEXCOORD4;
    public float4 uv : TEXCOORD5;
    public float4 maskUV : TEXCOORD6;
    public float4 positionOS : TEXCOORD7;
    public float4 lightOS : TEXCOORD8;
    public float3 normalOS : NORMAL0;
    public bool frontFace : SV_IsFrontFace;
};

public cbuffer Globals : register(b0)
{
    public float4 _ScaledScreenParams : packoffset(c3);
    public float4 mipAndAlpha : packoffset(c4);
    public float4 _MainLightPosition : packoffset(c5);
    public float4 _MainLightColor : packoffset(c6);
    public float4 _FPParams0 : packoffset(c15);
    public float4 _FPParams1 : packoffset(c16);
    public float4 _FPParams2 : packoffset(c17);
    public float4 _WorldSpaceCameraPos : packoffset(c25);
    public float4 _ProjectionParams : packoffset(c26);
    public float4 unity_OrthoParams : packoffset(c29);
    public float4 _ScaleBiasRt : packoffset(c31);
    public float4 glstate_lightmodel_ambient : packoffset(c59);
    public float4 unity_FogParams : packoffset(c64);
    public float4 unity_FogColor : packoffset(c65);
    public float4 viewX : packoffset(c70);
    public float4 viewY : packoffset(c71);
    public float4 viewZ : packoffset(c72);
};

public cbuffer UnityPerDraw : register(b4)
{
    public float4 objectOrigin : packoffset(c3);
    public float4 renderingLayer : packoffset(c10);
    public float4 specCubeDecode : packoffset(c15);
    public SHCoefficients probe : packoffset(c25);
};

public SamplerState samplerunity_SpecCube0 : register(s0);
#ifdef CLOTH_PREPASS
public SamplerState sampler_Detail_mask_01 : register(s1);
#else
public SamplerComparisonState shadowCompare1 : register(s1);
#endif
public SamplerState sampler_FluidTex : register(s2);
public SamplerState sampler_Normal_map : register(s3);
public SamplerState sampler_LiquidBump : register(s4);
public SamplerState sampler_Liquid : register(s5);
public SamplerState sampler_liquidmask : register(s6);
public SamplerState sampler_Create_main_texture : register(s7);
public SamplerState sampler_ColorMask : register(s8);
public SamplerState matcapSampler : register(s9);
public SamplerState sampler_Matcap_mask : register(s10);
#ifdef CLOTH_PREPASS
public SamplerState sampler_Detail_mask_02 : register(s11);
public SamplerState sampler_Lamp : register(s12);
public SamplerState sampler_Cloth_alpha_bot : register(s13);
public SamplerState sampler_Cloth_alpha : register(s14);
#else
public SamplerState sampler_Detail_mask_01 : register(s11);
public SamplerState sampler_Detail_mask_02 : register(s12);
public SamplerState sampler_Lamp : register(s13);
public SamplerState sampler_Cloth_alpha_bot : register(s14);
public SamplerState sampler_Cloth_alpha : register(s15);
#endif
public Texture2D<float4> _FluidTex : register(t0);
public Texture2D<float4> _Normal_map : register(t1);
public Texture2D<float4> _Liquid : register(t2);
public Texture2D<float4> _liquidmask : register(t3);
public Texture2D<float4> _LiquidBump : register(t4);
public Texture2D<float4> _Create_main_texture : register(t5);
public Texture2D<float4> _ColorMask : register(t6);
public Texture2D<float4> _Matcap_mask : register(t7);
public Texture2D<float4> _Detail_mask_01 : register(t8);
public Texture2D<float4> _Detail_mask_02 : register(t9);
public Texture2D<float4> _Lamp : register(t10);
public Texture2D<float4> _Cloth_alpha_bot : register(t11);
public Texture2D<float4> _Cloth_alpha : register(t12);
public TextureCube<float4> unity_SpecCube0 : register(t13);
#ifdef CLOTH_PREPASS
public Texture2DArray<float4> _TexTAMatcap : register(t14);
#else
public Texture2D<float4> _MainLightShadowmapTexture : register(t14);
public Texture2D<float4> _AdditionalLightsShadowmapTexture : register(t15);
public Texture2DArray<float4> _TexTAMatcap : register(t16);
#endif
