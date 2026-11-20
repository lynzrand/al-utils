#define SKIN_FACE 1
#define SKIN_PREPASS 0
import Coverage;
import MaterialNoise;
import AmbientProbe;

#define SKIN_MATERIAL_SLOT b6
#include "Material.slang"
#include "../Skin/Frame.slang"

SamplerState samplerunity_SpecCube0 : register(s0);
SamplerComparisonState shadowCompare1 : register(s1);
SamplerState sampler_FluidTex : register(s2);
SamplerState sampler_LiquidBump : register(s3);
SamplerState sampler_Texture2 : register(s4);
SamplerState sampler_Detail_mask_01 : register(s5);
SamplerState sampler_Detail_mask_02 : register(s6);
SamplerState sampler_Lip_texture : register(s7);
SamplerState sampler_Cheek_texture : register(s8);
SamplerState sampler_Create_jm_main_skin_head : register(s9);
SamplerState sampler_Lip_line_texture : register(s10);
SamplerState sampler_spmap : register(s11);
SamplerState sampler_Nose_texture : register(s12);
SamplerState sampler_Lamp : register(s13);
SamplerState sampler_expressionmap : register(s14);
Texture2D<float4> _FluidTex : register(t0);
Texture2D<float4> _Texture2 : register(t1);
Texture2D<float4> _Detail_mask_01 : register(t2);
Texture2D<float4> _Detail_mask_02 : register(t3);
Texture2D<float4> _LiquidBump : register(t4);
Texture2D<float4> _Lip_texture : register(t5);
Texture2D<float4> _Cheek_texture : register(t6);
Texture2D<float4> _Create_jm_main_skin_head : register(t7);
Texture2D<float4> _Lip_line_texture : register(t8);
Texture2D<float4> _spmap : register(t9);
Texture2D<float4> _Nose_texture : register(t10);
Texture2D<float4> _Lamp : register(t11);
Texture2D<float4> _expressionmap : register(t12);
TextureCube<float4> unity_SpecCube0 : register(t13);
Texture2D<float4> _MainLightShadowmapTexture : register(t14);
Texture2D<float4> _AdditionalLightsShadowmapTexture : register(t15);

struct StageInput
{
    float4 positionCS : SV_POSITION;
    float4 positionWS : TEXCOORD0;
    float3 normalWS : TEXCOORD1;
    float4 tangentWS : TEXCOORD2;
    float4 unused4 : TEXCOORD3;
    float4 unused5 : TEXCOORD4;
    float4 uv0Uv1 : TEXCOORD5;
    float4 uv2Uv3 : TEXCOORD6;
    float4 mainLightOS : TEXCOORD7;
    float3 normalOS : NORMAL0;
    float4 positionOS : TEXCOORD8;
    bool frontFacing : SV_IsFrontFace;
}

#include "../Skin/FluidLayer.slang"
#include "Makeup.slang"

#include "../Skin/Lighting.slang"

#include "Surface.slang"
#include "ForwardSurface.slang"
#include "ForwardLighting.slang"

float4 main(StageInput input) : SV_Target0
{
    float threshold = ditherThreshold(input.positionCS.xy, _ScaledScreenParams.xy, _ScaleBiasRt.xy, _ProjectionParams.x);
    float opacity = passesDither(_Dither, threshold) ? 1 : 0;
    clipCoverage(opacity, 0.5, _AlphaToMaskAvailable != 0);

    FaceSurface surface = sampleFaceSurface(input);
    FaceKey key = faceKey(input, surface);
    SkinLights lights = evaluateSkinLights(input, surface.normal, surface.normal);
    FaceRim rim = faceRim(input, surface, key);
    float gloss = faceGloss(input, surface);
    FacePalette palette = facePalette(surface, key, rim, lights, gloss);
    float3 lit = mad(rim.secondary, palette.chromaMask, palette.color) + faceSubsurface(surface, key);
    float3 bounded = clamp(lit * 0.98, 0, 0.98);
    float3 color = mad(saturate(mad(surface.pigment, 7, 0.3)), palette.bounce,
                       mad(max(gloss, rim.outer), mad(lit, 0.98, -bounded), bounded));
    color = applySkinFill(color, surface.pigment, palette.ambient, lights);
    color = lerp(color, _Nose_line_color.rgb, surface.makeup.nose.b * _Nose_line_color.a);
    float3 line = faceLineTint(surface.view, surface.basis.normal, surface.detail.secondary.b, surface.makeup.pigment);
    return float4(lerp(color, line, surface.lineCoverage), _AlphaToMaskAvailable != 0 ? opacity : 1);
}
