import Materials.Hair.Bindings;
import Materials.Hair.Surface;
import Lighting.ToonPalette;
import Surface.MaterialColor;

/// Sum RGB components with equal weight, preserving values above one.
public float sumChannels(float3 c) { return dot(c, float3(1)); }
/// Rec. 709 weighted brightness used by the hair palette and additional lighting.
public float hairLuminance(float3 c) { return dot(c, luminance709); }
/// Rec. 601 weighted brightness used by the authored secondary silhouette.
public float hairLuma601(float3 c) { return dot(c, luminance601); }

/// Replace HSV saturation while preserving hue and value.
public float3 setColorSaturation(float3 color, float saturation)
{
    float3 hsv = rgbToHSV(color);
    return hsvToRGB(float3(hsv.x, saturation, hsv.z));
}

/// Main-light, shadow, and ambient-probe inputs shared across hair palette lookups.
public struct HairKey
{
    /// Rec. 709 main-light brightness clamped to the unit interval.
    public float luma;
    /// Main shadow visibility after applying the material's fallback and smooth transition.
    public float toonVisibility;
    /// Key light band strength after shadow visibility.
    public float band;
    /// Dot product of the shading normal and the diffuse palette direction.
    public float faceFacing;
    /// Dot product of the geometric normal and the diffuse palette direction.
    public float rimFacing;
    /// Dot product of the shading normal and the ramp lookup direction.
    public float rampFacing;
    /// World-space view-to-key blend used for the rim lobe.
    public float3 rimLight;
    /// Clamped probe and key RGB illumination for highlights.
    public float3 probeHighlight;
    /// Ambient probe RGB evaluated on the half-scaled shading normal and clamped for shadow tint.
    public float3 softProbe;
    /// Shared key-light energy, fallback color, and HDR compression for the hair palette.
    public PaletteLight palette;
};

/// Resolve the geometric, shading, and rim directions and combine the main key with the renderer's probe.
public HairKey prepareHairKey(HairSurface s, HairInput input, float visibility)
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

/// Blend ambient probe color with the authored shadow tint under the key's exposure.
float3 shadowPigment(HairKey k, float shade)
{
    float3 ambient = shadowProbeTint(k.softProbe);
    float facing = max(shadowFloor(mainLightColor.rgb), k.toonVisibility * saturate((k.rimFacing - 0.05) * 5));
    float mix = facing * shadowTintWeight(shade, k.rampFacing);
    float3 shadow = k.palette.exposeShadow(lerp(ambient, _Shadow_color.rgb, max(mix, 0)));
    return lerp(shadow, _Shadow_color.rgb, _ShadowColorControle);
}

/// Lit and shadow tints plus the weights that mix them with the strand pigment.
public struct HairToon
{
    /// RGB fill tint used to scale the lit pigment.
    public float3 lit;
    /// RGB tint of the shadow band after incorporating the probe and material shadow color.
    public float3 shadow;
    /// Lit weight from the ramp's inverse blue channel and available direct light.
    public float shadowBand;
    /// Clamped material control for ramp displacement and minimum shadow-band fill.
    public float shadowPower;
    /// Weight of the additive ambient probe in the final pigment.
    public float ambientMix;
    /// Combined painted and grazing shade mask used for the base color mix.
    public float shade;
};

/// Sample the blue lighting ramp and return the lit, shadow, and ambient weights for the strand.
public HairToon sampleHairRamp(HairSurface s, HairKey k, float shade, float3 extraDiffuse)
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
