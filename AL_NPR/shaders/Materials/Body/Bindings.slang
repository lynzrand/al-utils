// Unity binds these textures and samplers separately for Forward and ExtraPrePass.
public SamplerState samplerunity_SpecCube0 : register(s0);
public SamplerState sampler_Nip : register(s6);
public SamplerState sampler_LiquidBump : register(s7);
public SamplerState sampler_Create_main_texture : register(s8);
public SamplerState sampler_Under_hair_texture : register(s9);
public Texture2D<float4> _FluidTex : register(t0);
public Texture2D<float4> _Normal_map : register(t1);
public Texture2D<float4> _Nip : register(t2);
public Texture2D<float4> _LiquidBump : register(t3);
public Texture2D<float4> _Create_main_texture : register(t4);
public Texture2D<float4> _Under_hair_texture : register(t5);
public Texture2D<float4> _Detail_mask_02 : register(t6);
public Texture2D<float4> _Create_dent_texture : register(t7);
public Texture2D<float4> _Lamp : register(t8);
public Texture2D<float4> _shine_texture : register(t9);
public Texture2D<float4> _Cloth_alpha_bot : register(t10);
public Texture2D<float4> _Cloth_alpha : register(t11);
public TextureCube<float4> unity_SpecCube0 : register(t12);

#if SKIN_PREPASS
public SamplerState detailArraySampler : register(s1);
public SamplerState extraArraySampler : register(s2);
public SamplerState sampler_Create_dent_texture : register(s3);
public SamplerState sampler_FluidTex : register(s4);
public SamplerState sampler_Normal_map : register(s5);
public SamplerState sampler_Detail_mask_02 : register(s10);
public SamplerState sampler_Lamp : register(s11);
public SamplerState sampler_shine_texture : register(s12);
public SamplerState sampler_Cloth_alpha_bot : register(s13);
public SamplerState sampler_Cloth_alpha : register(s14);
public Texture2DArray<float4> _Detail_mask_01 : register(t13);
public Texture2DArray<float4> _TexEX : register(t14);
#else
public SamplerComparisonState shadowCompare1 : register(s1);
public SamplerState sampler_Create_dent_texture : register(s2);
public SamplerState sampler_FluidTex : register(s3);
public SamplerState sampler_Normal_map : register(s4);
public SamplerState extraArraySampler : register(s5);
public SamplerState detailArraySampler : register(s10);
public SamplerState sampler_Detail_mask_02 : register(s11);
public SamplerState sampler_Lamp : register(s12);
public SamplerState sampler_shine_texture : register(s13);
public SamplerState sampler_Cloth_alpha_bot : register(s14);
public SamplerState sampler_Cloth_alpha : register(s15);
public Texture2D<float4> _MainLightShadowmapTexture : register(t13);
public Texture2D<float4> _AdditionalLightsShadowmapTexture : register(t14);
public Texture2DArray<float4> _TexEX : register(t15);
public Texture2DArray<float4> _Detail_mask_01 : register(t16);
#endif

public struct StageInput
{
    public float4 positionCS : SV_POSITION;
    public float4 positionWS : TEXCOORD0;
    public float3 normalWS : TEXCOORD1;
    public float4 tangentWS : TEXCOORD2;
#if SKIN_PREPASS
    public float4 unused4 : TEXCOORD3;
#else
    public float4 uv0Uv1 : TEXCOORD3;
#endif
    public float4 unused5 : TEXCOORD4;
#if SKIN_PREPASS
    public float4 uv0Uv1 : TEXCOORD5;
#else
    public float4 unused6 : TEXCOORD5;
#endif
    public float4 uv2Uv3 : TEXCOORD6;
    public float4 positionOS : TEXCOORD7;
    public float4 mainLightOS : TEXCOORD8;
    public float3 normalOS : NORMAL0;
    public bool frontFacing : SV_IsFrontFace;
}
