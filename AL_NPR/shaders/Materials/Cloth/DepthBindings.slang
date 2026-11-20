public cbuffer Globals : register(b0)
{
    public float2 screenSize : packoffset(c3);
    public float alphaToMask : packoffset(c4.z);
    public float3 cameraPosition : packoffset(c21);
    public float projectionSign : packoffset(c22);
    public float2 targetScaleBias : packoffset(c27);
};

public cbuffer UnityPerDraw : register(b1)
{
    public float3 objectOrigin : packoffset(c3);
};

public SamplerState sampler_Create_main_texture : register(s0);
public SamplerState sampler_Detail_mask_01 : register(s1);
public SamplerState sampler_liquidmask : register(s3);
public Texture2D<float4> _Create_main_texture : register(t0);
public Texture2D<float4> _Detail_mask_01 : register(t1);
public Texture2D<float4> _liquidmask : register(t3);

// Cutout depth and shadow passes also bind the authored dye mask.
#ifdef CLOTH_CUTOUT_LAYOUT
public SamplerState sampler_ColorMask : register(s2);
public SamplerState sampler_Liquid : register(s4);
public SamplerState sampler_Cloth_alpha_bot : register(s5);
public SamplerState sampler_Cloth_alpha : register(s6);
public Texture2D<float4> _ColorMask : register(t2);
public Texture2D<float4> _Liquid : register(t4);
public Texture2D<float4> _Cloth_alpha_bot : register(t5);
public Texture2D<float4> _Cloth_alpha : register(t6);
#else
public SamplerState sampler_Liquid : register(s2);
public SamplerState sampler_Cloth_alpha_bot : register(s4);
public SamplerState sampler_Cloth_alpha : register(s5);
public Texture2D<float4> _Liquid : register(t2);
public Texture2D<float4> _Cloth_alpha_bot : register(t4);
public Texture2D<float4> _Cloth_alpha : register(t5);
#endif
