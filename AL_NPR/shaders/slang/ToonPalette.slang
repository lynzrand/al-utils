import MaterialColor;

// Each lobe turns toward the camera at a different rate as the key fades.
public struct PaletteDirections
{
    public float3 diffuse, ramp, rim;

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

public struct PaletteLight
{
    public float3 fallback, logBoost, compressed;
    public float presence, energy;

    public __init(float3 color)
    {
        presence = saturate(dot(color, float3(1)));
        fallback = lerp(float3(0.02822079, 0.06722254, 0.3231432), color, presence);
        logBoost = max(log2(fallback) * 0.30103, 0);
        compressed = min(logBoost, 3) + saturate(fallback);
        energy = dot(compressed, float3(1));
    }

    public float rampCoordinate(float facing)
    {
        float lightBias = (dot(fallback, float3(0.35)) - 0.333) * 1.4992504;
        float floor = mad(saturate(lightBias), -0.5, 0.5);
        float wrap = max(-clamp((lightBias - 1) * -0.25, -1, 0), 0.6);
        return ((1 - floor) * (facing + wrap)) / (wrap + 1) + floor;
    }

    public float3 exposeShadow(float3 tint)
    {
        float exposure = min(mad(min(energy, 4) - 1, -1.0 / 6, 1), 1);
        return tintSaturation(exposure * tint, mad(saturate((energy - 1) / 3), 0.9, 1.1));
    }
}

public float3 shadowProbeTint(float3 softProbe)
{
    float3 hsv = rgbToHSV(mad(softProbe, 0.7, 0.3));
    hsv.y *= 1.5;
    return hsvToRGB(hsv);
}

public float shadowFloor(float3 key)
{
    return mad(clamp(dot(key, luminance601), 1, 3) - 1, -0.2, 0.7);
}

public float shadowTintWeight(float shade, float facing)
{
    return mad(shade - 0.99, -0.10204082, 0.9) * (saturate(facing) + 1) * 0.375;
}

public float pigmentContrast(float3 pigment)
{
    return max(saturate(mad(saturationOf(pigment) - 0.4, 3.3333333, 1)),
               saturate(mad(peakChannel(pigment) - 0.1, -1.4285715, 1)));
}

// The authored blue sky sets the floor for the bright band. Strong keys
// gradually replace it with the scene's probe on the geometric normal.
public struct PaletteFill
{
    public float3 tint;
    public float amount, ambientWeight;

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
