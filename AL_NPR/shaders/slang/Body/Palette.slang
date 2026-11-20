struct BodyPalette
{
    float3 lighting, baseShadow, shadowColor, ambient;
    float shadowBand, ambientMix, shade;
};

BodyPalette sampleBodyPalette(BodySurface s, BodyKey k, BodyShade geometry, SkinLights lights)
{
    BodyPalette p;
    float3 key = skinKeyColor();
    float3 softProbe = saturate(probe.evaluate(s.artisticNormal * 0.5));
    float3 ambientHSV = rgbToHSV(mad(softProbe, 0.7, 0.3));
    ambientHSV.y *= 1.5;
    float3 ambient = hsvToRGB(ambientHSV);
    float3 hsv = rgbToHSV(s.substrate);
    float rootValue = sqrt(hsv.z);
    float3 shadow = hsvToRGB(float3(hsv.x, min(sqrt(hsv.y), 1) * min(rootValue * 10, 1), rootValue * 0.5 + 0.5));
    shadow = lerp(shadow, _Shade_color.rgb, _UseShadowColor);
    p.baseShadow = saturate(lerp(shadow, float3(0.9049558, 0.8495964, 0.6682819), s.liquid));
    p.shadowColor = lerp(_Shadow_color.rgb, _Under_hair_color.rgb, s.hairAlpha);
    float shadowFloor = 0.7 - (clamp(dot(key, luminance601), 1, 3) - 1) * 0.2;
    float shadowEdge = min(grazingRim(normalize(s.artisticNormal - float3(0, 0.25, 0)), s.view, 1.8), 1);
    float3 edgeColor = lerp(p.baseShadow, p.shadowColor, shadowEdge * shadowFloor * _Shadow_color.a);
    float grazingView = max(1 - dot(s.artisticNormal, s.view), 0.0001);
    p.shade = max(geometry.occlusion, min(grazingView * grazingView * 0.5, 0.5));
    float depth = mad(p.shade - 0.99, -0.10204082, 0.9) * (saturate(dot(k.rampLight, s.unitNormal)) + 1) * 0.375;
    float energy = dot(k.compressed, float3(1));
    float exposure = min(1 - (min(energy, 4) - 1) / 6, 1);
    shadow = exposure * lerp(ambient, edgeColor, max(max(shadowFloor, k.surfaceBand) * depth, 0));
    shadow = tintSaturation(shadow, mad(saturate((energy - 1) / 3), 0.9, 1.1));
    shadow = lerp(shadow, _Shade_color.rgb, _UseShadowColor);

    float shadowPower = saturate(mad(_Shadow_power, 0.4, 0.5));
    float detail = lerp(_mdGShadeControle, 1, s.detail.b) * (shadowPower * p.shade);
    float dent = (shadowPower * s.dent) * _mdGShadeControle;
    float bias = (s.flatten - 1) * 3;
    float rampOffset = clamp(min(min(bias * detail, bias * dent), bias * (shadowPower * s.detail.b)), -1, 0);
    float intensity = (dot(k.fallback, float3(0.35)) - 0.333) * 1.4992504;
    float wrap = max(-clamp((intensity - 1) * -0.25, -1, 0), 0.6);
    float start = mad(saturate(intensity), -0.5, 0.5);
    float facing = dot(k.rampLight, s.artisticNormal);
    float diffuse = dot(lights.diffuse, luminance709);
    float ramp = rampOffset + lerp(start, 1, (wrap + facing) / (wrap + 1));
    float lamp = _Lamp.Sample(sampler_Lamp, float2(saturate(diffuse + ramp))).b;
    float lit = skinPaletteWeight(saturate(k.band + diffuse), lights);
    p.shadowBand = lit * (1 - saturate(lamp));

    float facingWeight = saturate((facing + 0.8) * 0.625);
    float3 keyTint = min(k.compressed, 1);
    keyTint = max(keyTint, mad(keyTint, 0.8, 0.2));
    float3 probeTint = lerp(float3(0.5395417, 0.5462493, 0.7379106), probe.evaluate(s.basis.normal),
                            saturate((dot(key, float3(1.0 / 3)) - 1) * 0.5));
    float3 floor = min(saturate(dot(key, luminance601)), dot(keyTint, float3(1.0 / 3)) * lerp(probeTint, 1, facingWeight));
    float lightWeight = min(mad(max(lit, 0.5), facingWeight, max(1 - energy, 0)), 1);
    p.lighting = lerp(shadow, 1, max(p.shadowBand, 1 - shadowPower)) * lerp(floor, keyTint, lightWeight);
    p.ambient = softProbe;
    p.ambientMix = 0.1 - 0.1 * dot(saturate(key), float3(1.0 / 3)) * min((lightWeight + 1) * 0.7692308, 1);
    return p;
}

float pigmentContrast(float3 pigment)
{
    return max(saturate(mad(saturationOf(pigment) - 0.4, 3.3333333, 1)),
               saturate(mad(peakChannel(pigment) - 0.1, -1.4285715, 1)));
}

float3 matcapPigment(BodySurface s, BodyPalette p, BodyRim rim, float contrast)
{
    float edge = grazingRim(normalize(s.artisticNormal), s.view + float3(0, 0.2, 0), 1.5);
    float density = mad(s.regions.b, -0.5, 1);
    float weight = saturate(edge * (density * _Shadow_color.a) * 0.5);
    float3 tint = lerp(p.shadowColor, dot(p.shadowColor, luminance601), mad(weight, -0.8, 0.4));
    float3 edgeTint = lerp(1, saturate(tint), saturate(mad(_Shadow_color.a, 0.25, 0.75)) * saturate(density * edge * 0.5));
    float brightness = min(1 - dot(s.pigment, luminance709) * 0.5, 1);
    float width = (1 - s.flatten) * saturate(mad(rim.main - 0.25, -2, 1));
    float3 matcap = lerp(1, lerp(1, edgeTint, brightness * width), _TestMatcapShade);
    float viewEdge = 1 - dot(s.normalWS, s.view);
    float square = viewEdge * viewEdge;
    float lightness = saturate(mad(viewEdge * (square * square), 0.05, (toView(s.normalWS).y + 1) * 0.15) + 0.3);
    float3 occlusionTint = lerp(p.shadowColor, 1, lightness);
    float occlusion = contrast * saturate(mad(peakChannel(s.pigment), 0.8, 0.2)) * _TestOC * 0.3352197;
    float3 shift = (occlusionTint * 2 - 1) * occlusion;
    float3 painted = saturate(mad(matcap, s.paintedPigment, shift));
    float3 skin = saturate(mad(matcap, s.pigment, shift));
    float3 pigment = lerp(skin, painted, max(p.shadowBand, 0.5));
    float3 hsv = rgbToHSV(pigment * lerp(1, p.baseShadow, p.shade * _BaseColorMix));
    hsv.y = min(saturationOf(painted) + 0.1, max(hsv.y, 0));
    return saturate(mad(p.lighting, hsvToRGB(hsv), p.ambient * p.ambientMix));
}

float3 illuminateBody(BodySurface s, BodyKey k, BodyShade shade, SkinLights lights, StageInput input)
{
    BodyRim rim = bodyRim(s, k, shade, input);
    BodyPalette palette = sampleBodyPalette(s, k, shade, lights);
    float contrast = pigmentContrast(s.pigment);
    float3 lit = matcapPigment(s, palette, rim, contrast);
    float shine = paintedShine(s, k);
    float3 probeLight = probe.evaluate(s.artisticNormal);
    float3 lighting = saturate(probeLight + saturate(mad(k.band * skinKeyColor(), 0.9, 0.1)));
    float shineWeight = max(mad(dot(lighting, luminance709), 0.7, 0.3) * max(shine, 0),
                            rim.main * saturate(mad(_Highlight_color.a, 0.5, 0.5)));
    float3 highlight = mad(_Highlight_color.rgb, 0.7, 0.3);
    highlight = clamp(lighting * (mad(saturationOf(highlight), 2.2, 0.8) * highlight), 0, 99);
    float rimWeight = contrast * rim.secondary;
    lit = lerp(lit, tintSaturation(highlight + lit, 1.5), saturate(mad(shineWeight, 3, rimWeight)));
    lit = rim.transmission + (rimWeight + lit);
    float3 diffuse = skinBounce(lights);
    float wrapped = saturate((dot(k.rampLight, s.artisticNormal) + 1) * 0.5);
    float3 bounce = min(k.logBoost, 1) * 0.1 * (k.band * wrapped)
                  + mad(max(1 - shade.occlusion, 0), 0.25, 0.75) * diffuse * mad(saturationOf(diffuse), 0.75, 0.25);
    float3 capped = clamp(lit * 0.98, 0, 0.98);
    lit = mad(saturate(mad(s.pigment, 7, 0.3)), bounce, lerp(capped, lit * 0.98, max(shine, rim.main)));
    return applySkinFill(lit, s.pigment, probeLight, lights);
}
