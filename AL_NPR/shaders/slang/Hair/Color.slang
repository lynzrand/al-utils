import Coverage;

#include "Bindings.slang"
#include "Surface.slang"
#include "Lights.slang"
#include "Palette.slang"
#include "Highlights.slang"

float3 shadeHairPigment(float3 pigment, float rim, HairSurface s, HairKey k, HairToon toon)
{
    float3 probeShade = mad(probe.evaluate(s.shadingNormal * 0.3), 0.7, 0.3);
    float falloff = min(pow(max(1 - dot(s.shadingNormal, s.view + float3(0, 0.2, 0)), 0.0001), 1.2), 1);
    float strength = min(1 - hairLuminance(pigment) * 0.5, 1) * saturate(1 - (rim - 0.25) * 2);
    float3 matcap = lerp(float3(1), saturate(adjustSaturation(probeShade, 2)), falloff) * strength + (1 - strength);
    matcap = lerp(float3(1), matcap, _TestMatcapShade);
    float3 shaded = saturate(pigment * (matcap * 0.5 + 0.5));
    float3 fullyShaded = saturate(pigment * matcap);
    shaded = lerp(shaded, fullyShaded, max(toon.shadowBand, 0.5));
    shaded *= lerp(float3(1), _Shadow_color.rgb, toon.shade * _BaseColorMix);
    shaded = setColorSaturation(shaded, min(colorSaturation(fullyShaded) + 0.1, max(colorSaturation(shaded), 0)));

    float3 shadow = lerp(toon.shadow, float3(1), max(toon.shadowBand, 1 - toon.shadowPower));
    return saturate(toon.lit * shadow * shaded + k.softProbe * toon.ambientMix);
}

float3 hairTransmission(HairSurface s, HairKey k, HairMasks masks, float3 pigment, float visibility)
{
    float3 key = max(mainLightColor.rgb, 0);
    key = log2(min(key, 3)) * 0.30103 + min(key, 1);
    float3 color = saturate(key * mad(pigment, 0.95, 0.05));
    float bias = dot(masks.colors.gb, float2(0.5, 0.25));
    float backLight = saturate((bias - dot(safeUnit(s.shadingNormal + s.key), s.view)) / (bias + 0.75));
    float facing = saturate((dot(k.rimLight, s.shadingNormal) + 1) * 0.25);
    return saturate(saturate(2 * hairLuminance(key)) * ((visibility * facing) *
                    (backLight * (key * saturate(adjustSaturation(color, 2))))) * _TestSSS);
}

float3 finishHairPalette(float3 pigment, HairStripe stripe, HairSurface s, HairInput input,
                         HairMasks masks, HairKey k, HairToon toon, float visibility, float rim)
{
    float edge = s.viewEdge;
    float fresnel = max(edge, 0.0001);
    float litRed = saturate(visibility * mainLightColor.r);
    float rimMask = input.frontFace ? masks.rim : 0;
    float innerRim = saturate(litRed * rimMask * s.elevation * min(pow(fresnel, 2.1) * 0.2, 0.2) * _TestRimSub * 0.75);
    float3 highlight = stripe.tint * 0.7 + 0.3;
    float specular = max(max(stripe.intensity, masks.rim * innerRim), 0) * (hairLuminance(k.probeHighlight) * 0.7 + 0.3);
    specular = max(specular, saturate(max(stripe.primary, _Highlight_color02.a) * 0.5 + 0.5) * rim);

    float silhouette = saturate(edge * edge * edge * 0.3) * saturate(hairLuma601(pigment) * 0.7 + 0.3);
    float rimGain = litRed * rimMask * silhouette * min(_TestRimSub, _TestRim);
    rimGain *= max(saturate((colorSaturation(pigment) - 0.4) * 3.3333333 + 1),
                   saturate(1 - (maxChannel(pigment) - 0.1) * 1.4285715));
    float3 base = shadeHairPigment(pigment, rim, s, k, toon);
    float3 bright = base + clamp(k.probeHighlight * ((colorSaturation(highlight) * 2.2 + 0.8) * highlight), 0, 99);
    float3 result = rimGain + lerp(base, adjustSaturation(bright, 1.5), saturate(3 * specular + rimGain));
    result += hairTransmission(s, k, masks, pigment, visibility);
    result *= 0.98;
    return lerp(clamp(result, 0, 0.98), result, max(stripe.intensity, rim));
}

float4 shadeHair(HairInput input, bool opaqueBase)
{
    HairSurface surface = makeHairSurface(input);
    HairLights lights = gatherHairLights(surface, input);
    HairMasks masks = sampleHairMasks(input.uv1Uv0.zw);
    float visibility = hairKeyVisibility(input.positionWS.xyz);
    HairKey key = prepareHairKey(surface, input, visibility);
    HairStripe stripe = paintStrands(strandPigment(masks), masks, surface, input, visibility, key.luma);
    float3 pigment = wetHair(stripe.pigment, surface, input, visibility);

    float fresnel = max(surface.viewEdge, 0.0001);
    float shade = max(masks.shade, min(fresnel * fresnel * 0.5, 0.5));
    HairToon toon = sampleHairRamp(surface, key, shade, lights.diffuse);
    float rim = saturate(hairRim(surface, input, key.rimLight, key.faceFacing, fresnel));
    float facing = saturate((key.faceFacing + 0.2) * 2.5) * 0.5 + 0.5;
    rim = input.frontFace ? saturate(masks.rim * surface.elevation * facing * rim * _TestRim * 0.75) : 0;
    float3 color = finishHairPalette(pigment, stripe, surface, input, masks, key, toon, visibility, rim);
#ifndef HAIR_STOCK_BASE
    float3 fill = lerp(lights.diffuse, lights.wrapped, 0.5);
    fill *= (colorSaturation(fill) * 0.75 + 0.25) * (max(1 - masks.shade, 0) * 0.5 + 0.5);
    float3 keyFill = (min(key.logBoost, 1) * 0.1) * (key.band * saturate((key.rampFacing + 1) * 0.5));
    color += saturate(mad(pigment, 7, 0.3)) * (fill * (stripe.intensity * 0.2 + 1) + keyFill);
#endif
#ifdef HAIR_NPR
    color += finishHairReflection(lights.reflected, masks.detail.r, _Highlight_color01);
#endif
    float threshold = ditherThreshold(input.positionCS.xy, screenSize, screenScaleBias, projectionSign);
    float alpha = passesDither(_Dither, threshold) ? (opaqueBase ? 1 : max(saturate(_TipAlpha), 0.01)) : 0;
    clipCoverage(alpha, 0.01, alphaToMaskAvailable != 0);
    return float4(color, alpha);
}
