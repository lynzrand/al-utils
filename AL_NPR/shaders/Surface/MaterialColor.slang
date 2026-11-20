public static const float3 luminance709 = float3(0.2126729, 0.7151522, 0.072175);
public static const float3 luminance601 = float3(0.299, 0.587, 0.114);

public float peakChannel(float3 color) { return max(color.r, max(color.g, color.b)); }

public float saturationOf(float3 color)
{
    float value = peakChannel(color);
    return (value - min(color.r, min(color.g, color.b))) / (value + 1e-10);
}

public float3 tintSaturation(float3 color, float amount)
{
    return lerp(dot(color, luminance709), color, amount);
}

public float3 rgbToHSV(float3 color)
{
    float4 p = color.g >= color.b ? float4(color.gb, 0, -1.0 / 3.0)
                                  : float4(color.bg, -1, 2.0 / 3.0);
    float4 q = color.r >= p.x ? float4(color.r, p.yzx) : float4(p.xyw, color.r);
    float chroma = q.x - min(q.y, q.w);
    return float3(abs(q.z + (q.w - q.y) / mad(chroma, 6, 1e-10)),
                  chroma / (q.x + 1e-10), q.x);
}

public float3 hsvToRGB(float3 hsv)
{
    float3 hue = frac(hsv.x + float3(1, 2.0 / 3.0, 1.0 / 3.0));
    return hsv.z * lerp(1, saturate(abs(mad(hue, 6, -3)) - 1), hsv.y);
}

// Unity stores its reflection probe in HDR or RGBM form according to these
// decode parameters. Resolve the encoded alpha before applying the RGB scale.
public float3 decodeProbe(float4 encoded, float4 decode)
{
    float alpha = max(mad(decode.w, encoded.a - 1, 1), 0);
    return encoded.rgb * (exp2(log2(alpha) * decode.y) * decode.x);
}

// The game's specular probes map perceptual roughness to six mip intervals.
public float reflectionProbeMip(float roughness)
{
    return roughness * mad(-roughness, 0.7, 1.7) * 6;
}
