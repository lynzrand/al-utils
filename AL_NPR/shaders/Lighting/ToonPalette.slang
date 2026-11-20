import Surface.MaterialColor;

/// Each lobe turns toward the camera at a different rate as the key fades.
public struct PaletteDirections
{
    /// World-space direction for diffuse band selection as the key blends toward the view.
    public float3 diffuse;
    /// World-space direction for the material's tone-ramp lookup.
    public float3 ramp;
    /// World-space direction for the broad and narrow silhouette highlights.
    public float3 rim;

    /// Blend the view and signed key vectors according to the key color's Rec. 709 brightness.
    public __init(float3 color, float3 view, float3 signedKey)
    {
        float luma = dot(color, luminance709);
        float brightness = saturate(luma);
        float fade = saturate(mad(max(log2(luma), brightness) - 1, -0.1, 1));
        float3 delta = signedKey - view;
        diffuse = mad(fade * min(brightness * 2, 1), delta, view);
        ramp = mad(fade * min(brightness * 10, 1), delta, view);
        rim = mad(fade * min(brightness * 3.3333333, 1), delta, view);
    }
}

/// Key color summarized for the ramp, shadow tint, and fill.
public struct PaletteLight
{
    /// RGB key tint blended toward the game's blue fallback as direct light fades.
    public float3 fallback;
    /// Nonnegative per-channel HDR boost computed from the fallback-adjusted key.
    public float3 logBoost;
    /// Clamped key RGB plus its capped logarithmic HDR boost.
    public float3 compressed;
    /// Clamped sum of the input key's RGB channels.
    public float presence;
    /// Sum of the compressed key's RGB components, used for band exposure.
    public float energy;

    /// Derive fallback tint and exposure from the scene's HDR key RGB.
    public __init(float3 color)
    {
        presence = saturate(dot(color, float3(1)));
        fallback = lerp(float3(0.02822079, 0.06722254, 0.3231432), color, presence);
        logBoost = max(log2(fallback) * 0.30103, 0);
        compressed = min(logBoost, 3) + saturate(fallback);
        energy = dot(compressed, float3(1));
    }

    /// Convert the surface/light facing to the material ramp coordinate before the shade-mask bias.
    public float rampCoordinate(float facing)
    {
        float lightBias = (dot(fallback, float3(0.35)) - 0.333) * 1.4992504;
        float floor = mad(saturate(lightBias), -0.5, 0.5);
        float wrap = max(-clamp((lightBias - 1) * -0.25, -1, 0), 0.6);
        return ((1 - floor) * (facing + wrap)) / (wrap + 1) + floor;
    }

    /// Apply energy-dependent brightness and saturation to a shadow tint.
    public float3 exposeShadow(float3 tint)
    {
        float exposure = min(mad(min(energy, 4) - 1, -1.0 / 6, 1), 1);
        return tintSaturation(exposure * tint, mad(saturate((energy - 1) / 3), 0.9, 1.1));
    }
}

/// Turn the clamped soft probe RGB into the ambient shadow tint by boosting HSV saturation.
public float3 shadowProbeTint(float3 softProbe)
{
    float3 hsv = rgbToHSV(mad(softProbe, 0.7, 0.3));
    hsv.y *= 1.5;
    return hsvToRGB(hsv);
}

/// Minimum key-dependent weight applied when blending authored and ambient shadow color.
public float shadowFloor(float3 key)
{
    return mad(clamp(dot(key, luminance601), 1, 3) - 1, -0.2, 0.7);
}

/// Strength of the painted shadow tint from shade mask and ramp-light facing.
public float shadowTintWeight(float shade, float facing)
{
    return mad(shade - 0.99, -0.10204082, 0.9) * (saturate(facing) + 1) * 0.375;
}

/// Gate rim and occlusion from the pigment's HSV saturation and peak value.
public float pigmentContrast(float3 pigment)
{
    return max(saturate(mad(saturationOf(pigment) - 0.4, 3.3333333, 1)),
               saturate(mad(peakChannel(pigment) - 0.1, -1.4285715, 1)));
}

/// The authored blue sky sets the floor for the bright band. Strong keys
/// gradually replace it with the scene's probe on the geometric normal.
public struct PaletteFill
{
    /// RGB fill chosen between the sky floor and bright key color.
    public float3 tint;
    /// Weight of bright key color in the sky-to-key interpolation.
    public float amount;
    /// Strength of the additional soft-probe RGB added to the final palette.
    public float ambientWeight;

    /// Use ramp facing and direct-band strength to blend the sky floor and the compressed key.
    public __init(PaletteLight light, float3 key, float3 probe, float rampFacing, float direct)
    {
        float facing = saturate((rampFacing + 0.8) * 0.625);
        float3 bright = min(light.compressed, 1);
        bright = max(bright, mad(bright, 0.8, 0.2));
        float3 sky = lerp(float3(0.5395417, 0.5462493, 0.7379106), probe,
                          saturate((dot(key, float3(1.0 / 3)) - 1) * 0.5));
        float3 floor = min(saturate(dot(key, luminance601)), dot(bright, float3(1.0 / 3)) * lerp(sky, 1, facing));
        amount = min(mad(max(direct, 0.5), facing, max(1 - light.energy, 0)), 1);
        tint = lerp(floor, bright, amount);
        ambientWeight = mad(dot(saturate(key), float3(1.0 / 3)) * min((amount + 1) * 0.7692308, 1), -0.1, 0.1);
    }
}
