// Unity binds these textures and samplers separately for Forward and ExtraPrePass.
public Texture2D<float4> _Lip_texture : register(t5);

#if SKIN_PREPASS
public SamplerState sampler_Detail_mask_01 : register(s0);
public SamplerState sampler_Detail_mask_02 : register(s1);
public SamplerState sampler_Create_jm_main_skin_head : register(s2);
public SamplerState sampler_spmap : register(s3);
public SamplerState sampler_expressionmap : register(s4);
public SamplerState sampler_Cheek_texture : register(s5);
public SamplerState sampler_Lip_texture : register(s6);
public SamplerState sampler_Nose_texture : register(s7);
public SamplerState sampler_FluidTex : register(s8);
public SamplerState sampler_LiquidBump : register(s9);
public SamplerState sampler_Texture2 : register(s10);
public Texture2D<float4> _Detail_mask_02 : register(t0);
public Texture2D<float4> _Create_jm_main_skin_head : register(t1);
public Texture2D<float4> _spmap : register(t2);
public Texture2D<float4> _expressionmap : register(t3);
public Texture2D<float4> _Cheek_texture : register(t4);
public Texture2D<float4> _Nose_texture : register(t6);
public Texture2D<float4> _FluidTex : register(t7);
public Texture2D<float4> _Texture2 : register(t8);
public Texture2D<float4> _Detail_mask_01 : register(t9);
public Texture2D<float4> _LiquidBump : register(t10);
#else
public SamplerState samplerunity_SpecCube0 : register(s0);
public SamplerComparisonState shadowCompare1 : register(s1);
public SamplerState sampler_FluidTex : register(s2);
public SamplerState sampler_LiquidBump : register(s3);
public SamplerState sampler_Texture2 : register(s4);
public SamplerState sampler_Detail_mask_01 : register(s5);
public SamplerState sampler_Detail_mask_02 : register(s6);
public SamplerState sampler_Lip_texture : register(s7);
public SamplerState sampler_Cheek_texture : register(s8);
public SamplerState sampler_Create_jm_main_skin_head : register(s9);
public SamplerState sampler_Lip_line_texture : register(s10);
public SamplerState sampler_spmap : register(s11);
public SamplerState sampler_Nose_texture : register(s12);
public SamplerState sampler_Lamp : register(s13);
public SamplerState sampler_expressionmap : register(s14);
public Texture2D<float4> _FluidTex : register(t0);
public Texture2D<float4> _Texture2 : register(t1);
public Texture2D<float4> _Detail_mask_01 : register(t2);
public Texture2D<float4> _Detail_mask_02 : register(t3);
public Texture2D<float4> _LiquidBump : register(t4);
public Texture2D<float4> _Cheek_texture : register(t6);
public Texture2D<float4> _Create_jm_main_skin_head : register(t7);
public Texture2D<float4> _Lip_line_texture : register(t8);
public Texture2D<float4> _spmap : register(t9);
public Texture2D<float4> _Nose_texture : register(t10);
public Texture2D<float4> _Lamp : register(t11);
public Texture2D<float4> _expressionmap : register(t12);
public TextureCube<float4> unity_SpecCube0 : register(t13);
public Texture2D<float4> _MainLightShadowmapTexture : register(t14);
public Texture2D<float4> _AdditionalLightsShadowmapTexture : register(t15);
#endif

public struct StageInput
{
    public float4 positionCS : SV_POSITION;
    public float4 positionWS : TEXCOORD0;
    public float3 normalWS : TEXCOORD1;
    public float4 tangentWS : TEXCOORD2;
#if SKIN_PREPASS
    public float4 uv0Uv1 : TEXCOORD3;
    public float4 uv3Uv2 : TEXCOORD4;
    public float4 unused6 : TEXCOORD5;
    public float4 unused7 : TEXCOORD6;
#else
    public float4 unused4 : TEXCOORD3;
    public float4 unused5 : TEXCOORD4;
    public float4 uv0Uv1 : TEXCOORD5;
    public float4 uv2Uv3 : TEXCOORD6;
    public float4 mainLightOS : TEXCOORD7;
    public float3 normalOS : NORMAL0;
    public float4 positionOS : TEXCOORD8;
#endif
    public bool frontFacing : SV_IsFrontFace;
}
