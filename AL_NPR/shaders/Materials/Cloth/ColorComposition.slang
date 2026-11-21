import Materials.Cloth.Bindings;
import Materials.Cloth.Highlights;
import Materials.Cloth.LightGather;
import Materials.Cloth.LightingFrame;
import Materials.Cloth.Palette;
import Materials.Cloth.Pigment;
import Surface.MaterialColor;
import Lighting.SceneLighting;
import Lighting.ToonPalette;

/// Blends the garment pigment toward the authored per-channel overlay and clamps the result.
float3 applyClothOverlay(float3 base, float3 tint, float strength)
{
    float3 overlay = select(tint > 0.5, base + tint * 2 - 1, base + (tint - 0.5) * 2);
    return saturate(lerp(base, overlay, strength));
}

/// Estimates transmitted key light from view-facing thickness, pigment, visibility, and the material's scattering controls.
float3 scatterCloth(ClothFrame frame, ClothKey key, ClothPalette palette, float3 pigment)
{
    float3 n = frame.normal + key.direction;
    float3 transmissionNormal = n * rsqrt(max(dot(n, n), 1.1754944e-38));
    float backLight = dot(-transmissionNormal, frame.view);
    float force = -0.75 * _SSSForce;
    float thickness = saturate((backLight - force) / (0.75 - force));
    float3 incident = max(key.color, 0);
    float3 incoming = mad(log2(min(incident, 3)), 0.30103, min(incident, 1));
    float3 tint = saturate(incoming * mad(pigment, 0.95, 0.05));
    tint = saturate(tintSaturation(tint, 2));
    float facing = saturate((dot(palette.rimDirection, frame.normal) + 1) * 0.25);
    float3 transmitted = (thickness * (incoming * tint)) * clamp(_SSSIntensity, 0, 999);
    float brightness = saturate(2 * dot(incoming, luminance709));
    return saturate(((key.visibility * facing) * transmitted) * brightness * _TestSSS);
}

/// Shades fluid-tinted pigment with the palette and probe. Returns pigment contrast for the highlight stage.
public float3 shadeClothPigment(ClothFrame frame, ClothKey key, ClothPalette palette, ClothRim rim,
                         float3 pigment, out float contrast)
{
    float3 probeTint = saturate(tintSaturation(mad(probe.evaluate(0.3 * frame.normal), 0.7, 0.3), 2));
    float shadowWeight = min(mad(dot(pigment, luminance709), -0.5, 1), 1) * saturate(mad(rim.amount - 0.25, -2, 1));
    float3 probeRim = mad(probeTint, rim.viewRim, 1 - rim.viewRim);
    float3 matShade = lerp(1, lerp(1, probeRim, shadowWeight), _TestMatcapShade);
    float value = peakChannel(pigment);
    contrast = pigmentContrast(pigment);
    float occlusion = contrast * (saturate(mad(value, 0.8, 0.2)) * _TestOC) * 0.3352197;
    float3 tint = lerp(palette.tint, 1, palette.highlight);
    float3 soft = applyClothOverlay(pigment * mad(matShade, 0.5, 0.5), tint, occlusion);
    float3 hard = applyClothOverlay(pigment * matShade, tint, occlusion);
    float3 base = lerp(soft, hard, palette.ramp);
    float3 hsv = rgbToHSV(base * lerp(1, palette.tint, palette.baseMix));
    hsv.y = clamp(hsv.y, 0, saturationOf(hard) + 0.1);
    base = hsvToRGB(hsv);
    base = saturate(mad(palette.ambient * palette.shadow, base, saturate(probe.evaluate(0.5 * frame.normal)) * palette.ambientWeight));

    return base;
}

/// Combines primary and secondary rims, the additive grazing highlight, and transmitted key light.
public float3 addClothHighlights(float3 base, float pigmentContrast, float3 pigment, float highlight,
                          ClothFrame frame, ClothKey key, ClothPalette palette, ClothRim rim, bool frontFace)
{
    float facingLight = saturate(key.visibility * key.color.r);
    float rimSub = min(exp2(rim.logViewGrazing * 2.1) * 0.2, 0.2) * _TestRimSub;
    rimSub *= rim.verticalFade * float(frontFace) * rim.mask;
    rimSub = saturate((rimSub * facingLight) * 0.5) * rim.mask;
    float rimLight = max(rim.amount, max(rimSub, highlight) * mad(dot(key.ambient, luminance709), 0.7, 0.3));
    float grazing = palette.viewGrazing * palette.viewGrazing * palette.viewGrazing;
    float addRim = saturate(grazing * 0.6) * saturate(mad(dot(pigment, luminance601), 0.7, 0.3));
    addRim *= float(frontFace) * rim.mask * min(_TestRim, _TestRimSub);
    addRim *= facingLight * _AddRimIntensity;
    float rimMix = saturate(mad(rimLight, 3, pigmentContrast * addRim));
    float3 rimColor = tintSaturation(palette.rimLight + base, 1.5);
    float3 color = mad(addRim, pigmentContrast, lerp(base, rimColor, rimMix));
    color += scatterCloth(frame, key, palette, pigment);
    color *= 0.9;
    return lerp(clamp(color, 0, 0.98), color, max(rim.amount, highlight));
}

/// Adds the palette's key boost and the pass's additional-light response to the shaded pigment.
public float3 addClothLights(float3 color, float3 pigment, ClothFrame frame, ClothKey key,
                      ClothPalette palette, ClothLights lights)
{

    float3 additive = lerp(lights.diffuse, lights.wrapped, 0.5);
    float addWeight = mad(max(1 - palette.specMask, 0), 0.5, 0.5);
    float3 mainBoost = palette.hdrBoost * 0.1;
    mainBoost *= (key.shade * key.bands.x) * saturate((palette.lightFacing + 1) * 0.5);
    float3 additional = mad(addWeight * additive, mad(saturationOf(additive), 0.75, 0.25), mainBoost);
#ifdef CLOTH_NPR
    float3 lit = saturate(pigment);
    color = mad(lit, additional, color);
    color = mad(lit, fabricFill(probe.evaluate(frame.normal), lights.band), color);
    // Roll off bright, pale fabric before post-processing clips the folds of a white garment.
    float peak = peakChannel(color);
    float excess = max(peak - 0.45, 0);
    float pale = smoothstep(0.35, 0.85, min(lit.r, min(lit.g, lit.b)));
    color *= 1 - pale * (excess / max(peak, 1e-6)) * (1 - rcp(1 + 1.8 * excess));
#else
    color = mad(saturate(mad(pigment, 7, 0.3)), additional, color);
#endif

    return color;
}

/// Applies painted lines and light cancellation. The outline pass also blends its fogged silhouette color.
public float3 clothLineColor(float3 color, ClothPigment p, ClothKey key, ClothLights lights,
                      ClothFrame frame, bool frontFace)
{
    float3 line = lerp(color, _Line_color.rgb, mad(_Line_power, 0.8, 0.2));
    float lineWidth = (1 - p.detail.b) * _Line_width * _LineWidthS;
    color = lerp(color, lerp(line, color, p.base.a), saturate(lineWidth * 4) * _AlphaLine);
    color = lerp(color, p.lineDetail * line, p.lineDetail);
    color = lerp(color, p.dry, _LightCancel);
#ifdef CLOTH_PREPASS
    float3 outlineLight = max(tintSaturation(probe.evaluate(frame.normal), 2), mad(key.color, 0.7, 0.3));
    outlineLight = saturate(lights.unshaded + saturate(outlineLight));
    outlineLight *= frontFace ? 1 : 0.75;
    float facing = saturate((dot(frame.basis.normal, key.direction) - 0.3) * 1.4285715);
    float3 outline = lerp(mad(outlineLight, facing, line), unity_FogColor.rgb, saturate(unity_FogParams.x));
    float edge = 1 - dot(frame.basis.normal, frame.view);
    float edge2 = edge * edge;
    color = lerp(color, outline, saturate(edge * (edge2 * edge2)));
#endif
    return color;
}
