struct ClothPalette
{
    float3 tint, shadow, ambient, rimLight;
    float baseMix, shade, ramp, lightFacing, viewGrazing, highlight;
    float3 rimDirection, hdrBoost;
    float specMask;
};

ClothPalette clothPalette(ClothFrame frame, ClothKey key, ClothPigment p, ClothLights lights)
{
    ClothPalette palette;
    float facingView = dot(frame.normal, frame.view);
    palette.viewGrazing = 1 - facingView;
    float keyLuma = dot(key.color, luminance601);
    float keyWeight = key.hdrFade * min(saturate(key.luma) * 10, 1);
    float3 diffuseDirection = mad(keyWeight, key.facingDelta, frame.view);
    palette.lightFacing = dot(diffuseDirection, frame.normal);
    float rimWeight = key.hdrFade * min(saturate(key.luma) * 3.3333333, 1);
    palette.rimDirection = mad(rimWeight, key.facingDelta, frame.view);

    float3 baseKey = lerp(float3(0.02822079, 0.06722254, 0.3231432), key.color, key.strength);
    float3 hdr = max(log2(baseKey) * 0.30103, 0);
    palette.hdrBoost = min(hdr, 1);
    float3 keyColor = saturate(baseKey) + min(hdr, 3);
    float brightness = dot(keyColor, 1);
    float ambientScale = min(mad(min(brightness, 4) - 1, -1.0 / 6.0, 1), 1);
    float3 probeHalf = saturate(probe.evaluate(0.5 * frame.normal));
    float3 ambientHSV = rgbToHSV(mad(probeHalf, 0.7, 0.3));
    ambientHSV.y *= 1.5;
    float3 ambientTint = hsvToRGB(ambientHSV);

    float peak = peakChannel(p.wetTint);
    float dyeWeight = max(min(sqrt(saturationOf(p.wetTint)), 1) * saturate(peak * 10), 1 - peak);
    palette.tint = lerp(float3(0.4508419, 0.60609, 1),
                        saturate(tintSaturation(saturate(p.wetTint), 2)), dyeWeight);
    palette.tint = saturate(lerp(palette.tint, float3(0.9049558, 0.8495964, 0.6682819), p.wetBlend));

    palette.specMask = max(saturate(p.detail.g / clamp(mad(_mdGPower, -0.5, 1), 0.5, 1)) * _mdGIntensity, 0);
    float edge = max(palette.viewGrazing, 0.0001);
    float shadowDetail = max(palette.specMask, min(edge * edge * 0.5, 0.5));
    palette.baseMix = shadowDetail * _BaseColorMix;
#ifdef CLOTH_NPR
    float vertexFacing = lights.band;
#else
    float vertexFacing = saturate((dot(normalize(frame.basis.normal), key.facingDirection) - 0.05) * 5);
#endif
    float keyFloor = mad(clamp(keyLuma, 1, 3) - 1, -0.2, 0.7);
    float mixWeight = mad(shadowDetail - 0.99, -0.10204082, 0.9) * (saturate(palette.lightFacing) + 1) * 0.375;
    mixWeight *= max(key.shade * vertexFacing, keyFloor);
    float3 mixed = lerp(ambientTint, palette.tint, max(mixWeight, 0)) * ambientScale;
    palette.shadow = tintSaturation(mixed, mad(saturate((brightness - 1) / 3), 0.9, 1.1));
    palette.shadow = lerp(palette.shadow, _Shade_color.rgb, _UseShadowColor);

    float shadowPower = saturate(mad(_Shadow_power, 0.4, 0.5));
    float additional = dot(lights.diffuse, luminance709);
    float keyShade = saturate(mad(key.shade, key.bands.x, additional));
    float rampScale = (dot(baseKey, 0.35) - 0.333) * 1.4992504;
    float bottom = mad(saturate(rampScale), -0.5, 0.5);
    float start = min(clamp((rampScale - 1) * -0.25, -1, 0), -0.6);
    float shift = clamp(((shadowDetail * shadowPower) * _mdGShadeControle) * -3, -1, 0);
    float rampUV = saturate(additional + (shift + ((palette.lightFacing - start) * (1 - bottom) / (1 - start) + bottom)));
    palette.ramp = keyShade * (1 - saturate(_Lamp.Sample(sampler_Lamp, rampUV.xx).b));
    palette.shadow = lerp(palette.shadow, 1, max(palette.ramp, 1 - shadowPower));
    palette.ramp = max(palette.ramp, 0.5);

    float3 lit = min(keyColor, 1);
    lit = max(lit, mad(lit, 0.8, 0.2));
    float3 sky = lerp(float3(0.5395417, 0.5462493, 0.7379106), probe.evaluate(frame.basis.normal),
                      saturate((dot(key.color, 1.0 / 3.0) - 1) * 0.5));
    float facing = saturate((palette.lightFacing + 0.8) * 0.625);
    sky = lerp(sky, 1, facing) * dot(lit, 1.0 / 3.0);
    sky = min(saturate(keyLuma), sky);
    palette.shade = min(mad(max(keyShade, 0.5), facing, max(1 - brightness, 0)), 1);
    palette.ambient = lerp(sky, lit, palette.shade);

    float3 rimTint = lerp(dot(p.wet, luminance601), p.wet, 1.5);
    rimTint = mad(rimTint, 0.7, 0.3);
    palette.rimLight = clamp((mad(saturationOf(rimTint), 2.2, 0.8) * rimTint) * key.ambient, 0, 99);
    float fresnel = 1 - dot(frame.normalBeforeNormalize, frame.view);
    float f2 = fresnel * fresnel;
    palette.highlight = saturate(mad(fresnel * (f2 * f2), 0.05,
                       (viewAxes(frame.normalBeforeNormalize).y + 1) * 0.15) + 0.3);
    return palette;
}
