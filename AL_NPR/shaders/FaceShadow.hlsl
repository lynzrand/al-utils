// Small tent filter for a comparison-sampled punctual shadow atlas. The
// integer offsets are atlas texels, so its footprint follows the actual size.
Texture2D<float> Atlas : register(t0);
SamplerComparisonState CompareDepth : register(s0);

float FaceShadow(float3 uvz : TEXCOORD0) : SV_Target
{
    float visibility = 0;
    [unroll] for (int y = -1; y <= 1; ++y)
    {
        [unroll] for (int x = -1; x <= 1; ++x)
        {
            float weight = (2 - abs(x)) * (2 - abs(y));
            visibility += weight * Atlas.SampleCmpLevelZero(CompareDepth, uvz.xy,
                                                            uvz.z, int2(x, y));
        }
    }
    return visibility * (1.0 / 16.0);
}

#include "SceneToonLighting.hlsl"

// Give a partly occluded light the fraction of its band that is visible.
// This keeps an authored toon ramp from sharpening the filtered cast shadow.
float3 FaceBand(float4 light : TEXCOORD0) : SV_Target
{
    return PerLightBand(light.rgb) * light.a;
}
