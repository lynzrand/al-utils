import AmbientProbe;

struct HairInput
{
    float4 positionCS : SV_POSITION;
    float4 positionWS : TEXCOORD0;
    float3 normalWS : TEXCOORD1;
    float4 tangentWS : TEXCOORD2;
    float4 unused3 : TEXCOORD3;
    float4 unused4 : TEXCOORD4;
    float4 uv1Uv0 : TEXCOORD5;
    float4 mainLightOS : TEXCOORD6;
    float3 normalOS : NORMAL0;
    float4 positionOS : TEXCOORD7;
    bool frontFace : SV_IsFrontFace;
};

cbuffer Globals : register(b0)
{
    float2 screenSize : packoffset(c3);
    float alphaToMaskAvailable : packoffset(c4.z);
    float4 mainLightDirection : packoffset(c5);
    float4 mainLightColor : packoffset(c6);
    float4 fp0 : packoffset(c15);
    float4 fp1 : packoffset(c16);
    float4 fp2 : packoffset(c17);
    float4 cameraPosition : packoffset(c25);
    float projectionSign : packoffset(c26);
    float orthographic : packoffset(c29.w);
    float2 screenScaleBias : packoffset(c31);
    float4 ambientColor : packoffset(c59);
    float4 viewX : packoffset(c70);
    float4 viewY : packoffset(c71);
    float4 viewZ : packoffset(c72);
};

cbuffer UnityPerDraw : register(b4)
{
    float4 renderingLayer : packoffset(c10);
    float4 cubeDecode : packoffset(c15);
    SHCoefficients probe : packoffset(c25);
};

// The stock base pass has no shadow atlas and binds the material one slot earlier.
#ifdef HAIR_STOCK_BASE
cbuffer UnityPerMaterial : register(b5)
#else
cbuffer UnityPerMaterial : register(b6)
#endif
{
    float4 _Sub_color_02 : packoffset(c0);
    float4 _Add_skin_color : packoffset(c1);
    float4 _Sub_color_01 : packoffset(c2);
    float4 _Hair_color_mask_ST : packoffset(c3);
    float4 _Main_color : packoffset(c4);
    float4 _Sampler302397_g100057_ST : packoffset(c5);
    float4 _md_02_ST : packoffset(c6);
    float4 _Ex_hair_color2 : packoffset(c7);
    float4 _md_01_ST : packoffset(c8);
    float4 _Ex_hair_color : packoffset(c9);
    float4 _Highlight_color02 : packoffset(c10);
    float4 _Highlight_color01 : packoffset(c11);
    float4 _Shadow_color : packoffset(c12);
    float4 _Sampler345397_g100057_ST : packoffset(c13);
    float _NureNormalPower : packoffset(c14.x);
    float _TestSSS : packoffset(c14.y);
    float _TestRimSub : packoffset(c14.z);
    float _Intensity1 : packoffset(c14.w);
    float _Intensity2 : packoffset(c15.x);
    float _HairHigh2Multiply : packoffset(c15.y);
    float _nureftop : packoffset(c15.z);
    float _nurefbot : packoffset(c15.w);
    float _TestMatcapShade : packoffset(c16.x);
    float _nurebbot : packoffset(c16.y);
    float _AseIntensity : packoffset(c16.z);
    float _nurebtop : packoffset(c17.x);
    float _hilightmove : packoffset(c17.y);
    float _Ex_hair_color2_onoff : packoffset(c17.z);
    float _Ex_hair_color_onoff : packoffset(c17.w);
    float _RimMaskIntensity : packoffset(c18.x);
    float _RimMaskPowermdG : packoffset(c18.y);
    float _TestRim : packoffset(c18.z);
    float _Shadow_power : packoffset(c18.w);
    float _mdGIntensity : packoffset(c19.x);
    float _mdGPower : packoffset(c19.y);
    float _BaseColorMix : packoffset(c19.z);
    float _mdGShadeControle : packoffset(c19.w);
    float _ShadowColorControle : packoffset(c20.x);
    float _LightLength : packoffset(c20.y);
    float _hilightmove2 : packoffset(c20.z);
    float _hilightmove3 : packoffset(c20.w);
    float _Dither : packoffset(c21.x);
    float _TipAlpha : packoffset(c21.y);
};

Texture2D<float4> normalMap : register(t0);
Texture2D<float4> paintedHighlight : register(t1);
Texture2D<float4> detailMask1 : register(t2);
Texture2D<float4> toonRamp : register(t3);
Texture2D<float4> detailMask2 : register(t4);
Texture2D<float4> colorMask : register(t5);
Texture2D<float4> wetMask : register(t6);
Texture2D<float4> wetNormalMap : register(t7);
TextureCube<float4> environmentCube : register(t8);
SamplerState environmentCubeSampler : register(s0);

#ifdef HAIR_STOCK_BASE
SamplerState normalMapSampler : register(s1);
SamplerState paintedHighlightSampler : register(s2);
SamplerState detailMask1Sampler : register(s3);
SamplerState toonRampSampler : register(s4);
SamplerState detailMask2Sampler : register(s5);
SamplerState colorMaskSampler : register(s6);
SamplerState wetMaskSampler : register(s7);
SamplerState wetNormalMapSampler : register(s8);
#else
Texture2D<float4> mainShadowAtlas : register(t9);
Texture2D<float4> additionalShadowAtlas : register(t10);
SamplerComparisonState shadowCompare : register(s1);
SamplerState normalMapSampler : register(s2);
SamplerState paintedHighlightSampler : register(s3);
SamplerState detailMask1Sampler : register(s4);
SamplerState toonRampSampler : register(s5);
SamplerState detailMask2Sampler : register(s6);
SamplerState colorMaskSampler : register(s7);
SamplerState wetMaskSampler : register(s8);
SamplerState wetNormalMapSampler : register(s9);
#endif
