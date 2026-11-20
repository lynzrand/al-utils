import ToonPalette;
import MaterialColor;

float sumChannels(float3 c) { return dot(c, float3(1)); }
float hairLuminance(float3 c) { return dot(c, luminance709); }
float hairLuma601(float3 c) { return dot(c, luminance601); }

float3 setColorSaturation(float3 color, float saturation)
{
    float3 hsv = rgbToHSV(color);
    return hsvToRGB(float3(hsv.x, saturation, hsv.z));
}

struct HairKey
{
    float luma, toonVisibility, band, faceFacing, rimFacing, rampFacing;
    float3 rimLight, probeHighlight, softProbe;
    PaletteLight palette;
};

HairKey prepareHairKey(HairSurface s, HairInput input, float visibility)
{
    HairKey k;
    float3 color = mainLightColor.rgb;
    k.luma = saturate(hairLuminance(color));
    k.palette = PaletteLight(color);
    k.toonVisibility = lerp(0.7, smoothstep(0.3, 0.7, visibility), k.palette.presence);
    k.softProbe = saturate(probe.evaluate(s.shadingNormal * 0.5));

    float3 signedKey = normalize(s.key) * (input.frontFace ? 1 : -1);
    PaletteDirections directions = PaletteDirections(color, s.view, signedKey);
    k.rimLight = directions.rim;
    k.rampFacing = dot(directions.ramp, s.shadingNormal);
    k.faceFacing = dot(s.shadingNormal, directions.diffuse);
    k.rimFacing = dot(normalize(s.basis.normal), directions.diffuse);
    k.band = k.toonVisibility * saturate((k.faceFacing - 0.05) * 5);
    k.probeHighlight = saturate(probe.evaluate(s.shadingNormal) + saturate(k.band * color * 0.7 + 0.3));

    return k;
}

float3 shadowPigment(HairKey k, float shade)
{
    float3 ambient = shadowProbeTint(k.softProbe);
    float facing = max(shadowFloor(mainLightColor.rgb), k.toonVisibility * saturate((k.rimFacing - 0.05) * 5));
    float mix = facing * shadowTintWeight(shade, k.rampFacing);
    float3 shadow = k.palette.exposeShadow(lerp(ambient, _Shadow_color.rgb, max(mix, 0)));
    return lerp(shadow, _Shadow_color.rgb, _ShadowColorControle);
}

struct HairToon
{
    float3 lit, shadow;
    float shadowBand, shadowPower, ambientMix, shade;
};

HairToon sampleHairRamp(HairSurface s, HairKey k, float shade, float3 extraDiffuse)
{
    HairToon toon;
    toon.shade = shade;
    toon.shadow = shadowPigment(k, shade);
    toon.shadowPower = saturate(_Shadow_power * 0.4 + 0.5);
    float diffuse = hairLuminance(extraDiffuse);
    float lit = saturate(k.band + diffuse);
    float ramp = k.palette.rampCoordinate(k.rampFacing);
    ramp += clamp(shade * toon.shadowPower * _mdGShadeControle * -3, -1, 0);
    float sample = toonRamp.Sample(toonRampSampler, float2(saturate(diffuse + ramp))).b;
    toon.shadowBand = lit * (1 - saturate(sample));

    PaletteFill fill = PaletteFill(k.palette, mainLightColor.rgb, probe.evaluate(s.basis.normal), k.rampFacing, lit);
    toon.lit = fill.tint;
    toon.ambientMix = fill.ambientWeight;
    return toon;
}
