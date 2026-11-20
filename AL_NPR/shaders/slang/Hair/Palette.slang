float sumChannels(float3 c) { return dot(c, float3(1)); }
float maxChannel(float3 c) { return max(c.r, max(c.g, c.b)); }
float hairLuminance(float3 c) { return dot(c, float3(0.2126729, 0.7151522, 0.072175)); }
float hairLuma601(float3 c) { return dot(c, float3(0.299, 0.587, 0.114)); }
float3 adjustSaturation(float3 color, float saturation)
{
    return lerp(hairLuminance(color), color, saturation);
}

float colorSaturation(float3 c)
{
    float value = maxChannel(c);
    return (value - min(c.r, min(c.g, c.b))) / (value + 1e-10);
}

// Preserve hue and value as the authored ramp scales or limits HSV saturation.
float3 setColorSaturation(float3 c, float saturation)
{
    float4 p = c.g >= c.b ? float4(c.gb, 0, -1.0/3.0) : float4(c.bg, -1, 2.0/3.0);
    float4 q = c.r >= p.x ? float4(c.r, p.yzx) : float4(p.xyw, c.r);
    float chroma = q.x - min(q.w, q.y);
    float hue = abs(q.z + (q.w - q.y) / (6 * chroma + 1e-10));
    float3 ramp = saturate(abs(frac(hue + float3(1, 2.0/3.0, 1.0/3.0)) * 6 - 3) - 1);
    return q.x * lerp(float3(1), ramp, saturation);
}

struct HairKey
{
    float luma, toonVisibility, band, faceFacing, rimFacing, rampFacing;
    float3 rimLight, probeHighlight, softProbe, compressed, logBoost, fallbackColor;
};

HairKey prepareHairKey(HairSurface s, HairInput input, float visibility)
{
    HairKey k;
    float3 color = mainLightColor.rgb;
    k.luma = saturate(hairLuminance(color));
    float presence = saturate(sumChannels(color));
    k.toonVisibility = lerp(0.7, smoothstep(0.3, 0.7, visibility), presence);
    k.softProbe = saturate(probe.evaluate(s.shadingNormal * 0.5));

    // Low light turns the palette towards the camera. Each band uses a different response.
    float3 faceKey = normalize(s.key) * (input.frontFace ? 1 : -1);
    float strength = saturate(1 - 0.1 * (max(log2(hairLuminance(color)), k.luma) - 1));
    float3 faceLight = lerp(s.view, faceKey, strength * min(k.luma * 2, 1));
    k.rimLight = lerp(s.view, faceKey, strength * min(k.luma * 3.3333333, 1));
    float3 rampLight = lerp(s.view, faceKey, strength * min(k.luma * 10, 1));
    k.rampFacing = dot(rampLight, s.shadingNormal);
    k.faceFacing = dot(s.shadingNormal, faceLight);
    k.rimFacing = dot(normalize(s.normal), faceLight);
    k.band = k.toonVisibility * saturate((k.faceFacing - 0.05) * 5);
    k.probeHighlight = saturate(probe.evaluate(s.shadingNormal) + saturate(k.band * color * 0.7 + 0.3));

    k.fallbackColor = lerp(float3(0.02822079, 0.06722254, 0.3231432), color, presence);
    k.logBoost = max(log2(k.fallbackColor) * 0.30103, 0);
    k.compressed = min(k.logBoost, 3) + saturate(k.fallbackColor);
    return k;
}

float3 shadowPigment(HairKey k, float shade)
{
    float3 probeColor = mad(k.softProbe, 0.7, 0.3);
    float3 ambient = setColorSaturation(probeColor, colorSaturation(probeColor) * 1.5);
    float brightness = sumChannels(k.compressed);
    float exposure = min(1 - (min(brightness, 4) - 1) / 6, 1);
    float shadowFloor = 0.7 - 0.2 * (clamp(hairLuma601(mainLightColor.rgb), 1, 3) - 1);
    float facing = max(shadowFloor, k.toonVisibility * saturate((k.rimFacing - 0.05) * 5));
    float mix = facing * ((mad(shade - 0.99, -0.10204082, 0.9) * (saturate(k.rampFacing) + 1)) * 0.375);
    float3 shadow = exposure * lerp(ambient, _Shadow_color.rgb, max(mix, 0));
    shadow = adjustSaturation(shadow, saturate((brightness - 1) / 3) * 0.9 + 1.1);
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
    float intensity = (dot(k.fallbackColor, float3(0.35)) - 0.333) * 1.4992504;
    float start = 0.5 - saturate(intensity) * 0.5;
    float wrap = max(-clamp((intensity - 1) * -0.25, -1, 0), 0.6);
    float ramp = lerp(start, 1, (wrap + k.rampFacing) / (wrap + 1));
    ramp += clamp(shade * toon.shadowPower * _mdGShadeControle * -3, -1, 0);
    float sample = toonRamp.Sample(toonRampSampler, float2(saturate(diffuse + ramp))).b;
    toon.shadowBand = lit * (1 - saturate(sample));

    float3 key = min(k.compressed, 1);
    key = max(key, key * 0.8 + 0.2);
    float keyEnergy = sumChannels(mainLightColor.rgb) / 3;
    float3 ambient = lerp(float3(0.5395417, 0.5462493, 0.7379106), probe.evaluate(s.normal),
                          saturate((keyEnergy - 1) * 0.5));
    float rampFacing = saturate((k.rampFacing + 0.8) * 0.625);
    float diffuseLevel = min(max(lit, 0.5) * rampFacing + max(1 - sumChannels(k.compressed), 0), 1);
    float3 floor = min(saturate(hairLuma601(mainLightColor.rgb)), (sumChannels(key) / 3) * lerp(ambient, 1, rampFacing));
    toon.lit = lerp(floor, key, diffuseLevel);
    toon.ambientMix = 0.1 - 0.1 * (sumChannels(saturate(mainLightColor.rgb)) / 3)
                                * min((diffuseLevel + 1) * 0.7692308, 1);
    return toon;
}
