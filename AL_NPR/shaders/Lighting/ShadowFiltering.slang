/// Return the normalized 3 × 3 tent-weighted depth comparison. XY is atlas UV and Z is receiver depth.
/// Offsets are measured in atlas texels and preserve hardware comparison filtering.
public float tentVisibility(Texture2D<float4> atlas, SamplerComparisonState compare,
                            float3 uvz)
{
    float visibility = 0;
    [unroll] for (int y = -1; y <= 1; ++y)
    {
        [unroll] for (int x = -1; x <= 1; ++x)
        {
            float weight = (2 - abs(x)) * (2 - abs(y));
            visibility += weight * atlas.SampleCmpLevelZero(compare, uvz.xy, uvz.z, int2(x, y));
        }
    }
    return visibility * 0.0625;
}
