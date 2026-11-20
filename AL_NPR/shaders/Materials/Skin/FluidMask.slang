/// Each pair of cubic B-spline weights can share a hardware bilinear sample.
/// The same reconstruction feeds coverage and both offset height samples used
/// for the wet normal, so their edges stay registered as the model animates.
///
/// Resamples single-mip paint at normalized UV. Packed RGBA and neighboring height taps follow the same
/// filter.
public float4 sampleFluidMask(Texture2D<float4> mask, SamplerState linearSampler, float2 uv)
{
    uint width, height, levels;
    mask.GetDimensions(0, width, height, levels);
    if (levels != 1 || width <= 1 || height <= 1)
        return mask.Sample(linearSampler, uv);

    float2 size = float2(width, height);
    float2 p = uv * size - 0.5;
    float2 f = frac(p);
    float2 inv = 1.0 - f;
    float2 w0 = inv * inv * inv / 6.0;
    float2 w1 = (4.0 - 6.0 * f * f + 3.0 * f * f * f) / 6.0;
    float2 w3 = f * f * f / 6.0;
    float2 w2 = 1.0 - w0 - w1 - w3;
    float2 left = w0 + w1;
    float2 right = w2 + w3;
    float2 base = floor(p) + 0.5;
    float2 lo = (base - 1.0 + w1 / left) / size;
    float2 hi = (base + 1.0 + w3 / right) / size;
    float4 row0 = lerp(mask.SampleLevel(linearSampler, lo, 0),
                       mask.SampleLevel(linearSampler, float2(hi.x, lo.y), 0), right.x);
    float4 row1 = lerp(mask.SampleLevel(linearSampler, float2(lo.x, hi.y), 0),
                       mask.SampleLevel(linearSampler, hi, 0), right.x);
    return lerp(row0, row1, right.y);
}
