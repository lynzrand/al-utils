// The fixed offsets are atlas texels. Preserve the comparison sampler's
// hardware filtering and apply the tent weights before the toon palette.
public float faceVisibility(Texture2D<float4> atlas, SamplerComparisonState compare,
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
