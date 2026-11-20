#define SKIN_FACE 1
#define SKIN_NPR 0
#define SKIN_PREPASS 1
import Coverage;
import MaterialNoise;
import AmbientProbe;

#define SKIN_MATERIAL_SLOT b2
#include "Material.slang"
#include "../Skin/Frame.slang"

SamplerState sampler_Detail_mask_01 : register(s0);
SamplerState sampler_Detail_mask_02 : register(s1);
SamplerState sampler_Create_jm_main_skin_head : register(s2);
SamplerState sampler_spmap : register(s3);
SamplerState sampler_expressionmap : register(s4);
SamplerState sampler_Cheek_texture : register(s5);
SamplerState sampler_Lip_texture : register(s6);
SamplerState sampler_Nose_texture : register(s7);
SamplerState sampler_FluidTex : register(s8);
SamplerState sampler_LiquidBump : register(s9);
SamplerState sampler_Texture2 : register(s10);
Texture2D<float4> _Detail_mask_02 : register(t0);
Texture2D<float4> _Create_jm_main_skin_head : register(t1);
Texture2D<float4> _spmap : register(t2);
Texture2D<float4> _expressionmap : register(t3);
Texture2D<float4> _Cheek_texture : register(t4);
Texture2D<float4> _Lip_texture : register(t5);
Texture2D<float4> _Nose_texture : register(t6);
Texture2D<float4> _FluidTex : register(t7);
Texture2D<float4> _Texture2 : register(t8);
Texture2D<float4> _Detail_mask_01 : register(t9);
Texture2D<float4> _LiquidBump : register(t10);

struct StageInput
{
    float4 positionCS : SV_POSITION;
    float4 positionWS : TEXCOORD0;
    float3 normalWS : TEXCOORD1;
    float4 tangentWS : TEXCOORD2;
    float4 uv0Uv1 : TEXCOORD3;
    float4 uv3Uv2 : TEXCOORD4;
    float4 unused6 : TEXCOORD5;
    float4 unused7 : TEXCOORD6;
    bool frontFacing : SV_IsFrontFace;
}

#include "../Skin/FluidLayer.slang"
#include "Makeup.slang"

#include "Surface.slang"
import SurfaceNormals;
import Skin.SurfaceFrame;
import MaterialColor;

float4 main(StageInput input) : SV_Target0
{
    float2 uv = input.uv0Uv1.xy;
    FaceDetail detail = sampleFaceDetail(uv);
    float threshold = ditherThreshold(input.positionCS.xy, _ScaledScreenParams.xy, _ScaleBiasRt.xy, _ProjectionParams.x);
    float coverage = passesDither(_Dither, threshold) && (1 - detail.mask.r) * _Line_width >= 0.05 ? 1 : 0;
    clipCoverage(coverage, 0.5, _AlphaToMaskAvailable != 0);

    TangentFrame basis = TangentFrame(input.normalWS, input.tangentWS);
    float3 fluidNormal = sampleFluidLayer(uv).normalTS;
    float3 liquidNormal = detail.liquidNormalTS;
    float3 combined = liquidNormal.z * fluidNormal;
    combined.xy = mad(liquidNormal.xy, fluidNormal.z, combined.xy);
    float3 normal = normalize(basis.toWorld(normalize(combined)));
    float3 probeColor = tintSaturation(probe.evaluate(normal), 2);
    float3 lightColor = saturate(max(probeColor, mad(_MainLightColor.rgb, 0.7, 0.3)));
    lightColor *= input.frontFacing ? 1 : 0.75;
    float3 light = _MainLightPosition.xyz * rsqrt(max(dot(_MainLightPosition.xyz, _MainLightPosition.xyz), 1.1754944e-38));
    float facing = saturate((dot(basis.normal, light) - 0.3) * 1.4285715);
    float3 highlight = saturate(facing * (lightColor * lightData.z));
    float3 line = faceLineTint(faceViewDirection(input.positionWS.xyz), basis.normal, detail.secondary.b,
                               sampleFaceMakeup(input).pigment);
    float3 color = mad(highlight, 1 - saturate(detail.mask.r * 3.3333333), line);
    return float4(lerp(color, unity_FogColor.rgb, saturate(unity_FogParams.x)),
                  _AlphaToMaskAvailable != 0 ? coverage : 1);
}
