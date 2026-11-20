#include "Surface.slang"
#include "Highlights.slang"
#include "Palette.slang"

float coveredBody(StageInput input, float dent)
{
    float4 uv = mad(float4(input.uv0Uv1.xy, input.uv2Uv3.xy), _Cloth_alpha_ST.xyxy, _Cloth_alpha_ST.zwzw);
    float2 maskUV = lerp(uv.xy, uv.zw, _AlphaMaskuv);
    float coverage = clothingMask(_Cloth_alpha.Sample(sampler_Cloth_alpha, maskUV).rgb,
                                 _Cloth_alpha_bot.Sample(sampler_Cloth_alpha_bot, maskUV).rgb, _alpha_a, _alpha_b);
    float threshold = ditherThreshold(input.positionCS.xy, _ScaledScreenParams.xy, _ScaleBiasRt.xy, _ProjectionParams.x);
    coverage *= float(passesDither(_Dither, threshold));
#if SKIN_PREPASS
    coverage *= 1 - dent;
#endif
    return coverage;
}

float4 main(StageInput input) : SV_Target0
{
    float visibility = skinMainVisibility(input.positionWS.xyz);
    BodySurface s = sampleBody(input, visibility);
    SkinLights lights = evaluateSkinLights(input, s.artisticNormal, s.unitNormal);
    BodyKey key = prepareBodyKey(s, input.frontFacing, visibility, lights);
    BodyShade shade = sampleBodyShade(s, input.uv0Uv1.xy);
    float3 lit = illuminateBody(s, key, shade, lights, input);
    float3 line = clamp(lerp(lit, _Line_color, mad(_Line_power, 0.8, 0.2)), 0, 0.95);
#if SKIN_PREPASS
    float3 fill = saturate(lights.incident + saturate(max(tintSaturation(probe.evaluate(s.artisticNormal), 2),
                                                         mad(skinKeyColor(), 0.7, 0.3))));
    float facing = saturate((dot(s.basis.normal, s.key) - 0.3) * 1.4285715);
    float3 outlined = min(line + ((input.frontFacing ? 1 : 0.75) * fill) * facing, 1);
    float3 color = lerp(outlined * saturate(mad(skinKeyColor(), 0.5, 0.5)), unity_FogColor.rgb, saturate(unity_FogParams.x));
#else
    float3 beads = saturate(lerp(s.beadReflection, skinKeyColor() * s.beadReflection, 0.5));
    float3 color = lerp(mad(beads, _AseIntensity, lit), line, s.lineMask);
#endif
    float coverage = coveredBody(input, s.dent);
    clipCoverage(coverage, 0.5, _AlphaToMaskAvailable != 0);
    return float4(color, _AlphaToMaskAvailable != 0 ? coverage : 1);
}
