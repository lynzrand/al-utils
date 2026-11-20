import Lighting.AmbientProbe;

public struct HairInput
{
    public float4 positionCS : SV_POSITION;
    public float4 positionWS : TEXCOORD0;
    public float3 normalWS : TEXCOORD1;
    public float4 tangentWS : TEXCOORD2;
    public float4 unused3 : TEXCOORD3;
    public float4 unused4 : TEXCOORD4;
    public float4 uv1Uv0 : TEXCOORD5;
    public float4 mainLightOS : TEXCOORD6;
    public float3 normalOS : NORMAL0;
    public float4 positionOS : TEXCOORD7;
    public bool frontFace : SV_IsFrontFace;
};

public cbuffer Globals : register(b0)
{
    public float2 screenSize : packoffset(c3);
    public float alphaToMaskAvailable : packoffset(c4.z);
    public float4 mainLightDirection : packoffset(c5);
    public float4 mainLightColor : packoffset(c6);
    public float4 fp0 : packoffset(c15);
    public float4 fp1 : packoffset(c16);
    public float4 fp2 : packoffset(c17);
    public float4 cameraPosition : packoffset(c25);
    public float projectionSign : packoffset(c26);
    public float orthographic : packoffset(c29.w);
    public float2 screenScaleBias : packoffset(c31);
    public float4 ambientColor : packoffset(c59);
    public float4 viewX : packoffset(c70);
    public float4 viewY : packoffset(c71);
    public float4 viewZ : packoffset(c72);
};

public cbuffer UnityPerDraw : register(b4)
{
    public float4 renderingLayer : packoffset(c10);
    public float4 cubeDecode : packoffset(c15);
    public SHCoefficients probe : packoffset(c25);
};

// The stock base pass has no shadow atlas and binds the material one slot earlier.
#ifdef HAIR_STOCK_BASE
public cbuffer UnityPerMaterial : register(b5)
#else
public cbuffer UnityPerMaterial : register(b6)
#endif
{
    public float4 _Sub_color_02 : packoffset(c0);
    public float4 _Add_skin_color : packoffset(c1);
    public float4 _Sub_color_01 : packoffset(c2);
    public float4 _Hair_color_mask_ST : packoffset(c3);
    public float4 _Main_color : packoffset(c4);
    public float4 _Sampler302397_g100057_ST : packoffset(c5);
    public float4 _md_02_ST : packoffset(c6);
    public float4 _Ex_hair_color2 : packoffset(c7);
    public float4 _md_01_ST : packoffset(c8);
    public float4 _Ex_hair_color : packoffset(c9);
    public float4 _Highlight_color02 : packoffset(c10);
    public float4 _Highlight_color01 : packoffset(c11);
    public float4 _Shadow_color : packoffset(c12);
    public float4 _Sampler345397_g100057_ST : packoffset(c13);
    public float _NureNormalPower : packoffset(c14.x);
    public float _TestSSS : packoffset(c14.y);
    public float _TestRimSub : packoffset(c14.z);
    public float _Intensity1 : packoffset(c14.w);
    public float _Intensity2 : packoffset(c15.x);
    public float _HairHigh2Multiply : packoffset(c15.y);
    public float _nureftop : packoffset(c15.z);
    public float _nurefbot : packoffset(c15.w);
    public float _TestMatcapShade : packoffset(c16.x);
    public float _nurebbot : packoffset(c16.y);
    public float _AseIntensity : packoffset(c16.z);
    public float _nurebtop : packoffset(c17.x);
    public float _hilightmove : packoffset(c17.y);
    public float _Ex_hair_color2_onoff : packoffset(c17.z);
    public float _Ex_hair_color_onoff : packoffset(c17.w);
    public float _RimMaskIntensity : packoffset(c18.x);
    public float _RimMaskPowermdG : packoffset(c18.y);
    public float _TestRim : packoffset(c18.z);
    public float _Shadow_power : packoffset(c18.w);
    public float _mdGIntensity : packoffset(c19.x);
    public float _mdGPower : packoffset(c19.y);
    public float _BaseColorMix : packoffset(c19.z);
    public float _mdGShadeControle : packoffset(c19.w);
    public float _ShadowColorControle : packoffset(c20.x);
    public float _LightLength : packoffset(c20.y);
    public float _hilightmove2 : packoffset(c20.z);
    public float _hilightmove3 : packoffset(c20.w);
    public float _Dither : packoffset(c21.x);
    public float _TipAlpha : packoffset(c21.y);
};

public Texture2D<float4> normalMap : register(t0);
public Texture2D<float4> paintedHighlight : register(t1);
public Texture2D<float4> detailMask1 : register(t2);
public Texture2D<float4> toonRamp : register(t3);
public Texture2D<float4> detailMask2 : register(t4);
public Texture2D<float4> colorMask : register(t5);
public Texture2D<float4> wetMask : register(t6);
public Texture2D<float4> wetNormalMap : register(t7);
public TextureCube<float4> environmentCube : register(t8);
public SamplerState environmentCubeSampler : register(s0);

#ifdef HAIR_STOCK_BASE
public SamplerState normalMapSampler : register(s1);
public SamplerState paintedHighlightSampler : register(s2);
public SamplerState detailMask1Sampler : register(s3);
public SamplerState toonRampSampler : register(s4);
public SamplerState detailMask2Sampler : register(s5);
public SamplerState colorMaskSampler : register(s6);
public SamplerState wetMaskSampler : register(s7);
public SamplerState wetNormalMapSampler : register(s8);
#else
public Texture2D<float4> mainShadowAtlas : register(t9);
public Texture2D<float4> additionalShadowAtlas : register(t10);
public SamplerComparisonState shadowCompare : register(s1);
public SamplerState normalMapSampler : register(s2);
public SamplerState paintedHighlightSampler : register(s3);
public SamplerState detailMask1Sampler : register(s4);
public SamplerState toonRampSampler : register(s5);
public SamplerState detailMask2Sampler : register(s6);
public SamplerState colorMaskSampler : register(s7);
public SamplerState wetMaskSampler : register(s8);
public SamplerState wetNormalMapSampler : register(s9);
#endif
