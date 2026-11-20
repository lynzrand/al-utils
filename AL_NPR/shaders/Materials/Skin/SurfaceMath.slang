import Surface.MaterialColor;
import Surface.MaterialNoise;

// Object-space gradient noise modulates the stock skin's surface detail.
// Lock the lattice to the mesh so the pattern follows the character.
float2 grainGradient(float2 cell)
{
    float2 seed = mad(cell, float2(0.3183099, 0.3678794), float2(0.3678794, 0.3183099));
    float hash = frac((seed.y * seed.x) * (seed.y + seed.x));
    return mad(frac(hash * float2(5.0929585, 5.8860703)), 2, -1);
}

public float skinGrain(float2 positionOS)
{
    float2 grid = positionOS * 4;
    float2 cell = floor(grid);
    float2 uv = frac(grid);
    float2 blend = uv * uv * mad(-uv, 2, 3);
    float lowerLeft = dot(grainGradient(cell), uv);
    float lowerRight = dot(grainGradient(cell + float2(1, 0)), uv - float2(1, 0));
    float upperLeft = dot(grainGradient(cell + float2(0, 1)), uv - float2(0, 1));
    float upperRight = dot(grainGradient(cell + 1), uv - 1);
    float lower = mad(blend.x, lowerRight - lowerLeft, lowerLeft);
    float upper = mad(blend.x, upperRight - upperLeft, upperLeft);
    return mad(mad(blend.y, upper - lower, lower), 0.5, 0.5);
}

public float sweatHeight(float2 uv, float time, float2 heightRange)
{
    float2 grid = (uv + float2(0, time * 0.003)) * 96;
    float2 distances = sweatCellDistances(floor(grid), frac(grid), time * 0.1);
    return saturate(mad(distances.x + distances.y, 0.5, -heightRange.x) / (heightRange.y - heightRange.x));
}

// Wet skin sharpens the probe across the surface. Local droplets also
// sharpen it and give it a minimum strength independently of the skin grain.
public float3 wetSkinReflection(TextureCube<float4> probe, SamplerState probeSampler, float4 hdr,
                                float3 reflectionDirection, float2 positionOS, float wetness, float coverage)
{
    float roughness = 1 - max(coverage * 0.9, wetness * 0.9);
    float4 sample = probe.SampleLevel(probeSampler, reflectionDirection, reflectionProbeMip(roughness));
    float strength = max(skinGrain(positionOS) * (wetness * 0.1), coverage * 0.25);
    float3 reflection = strength * decodeProbe(sample, hdr);
    return lerp(reflection, dot(reflection, luminance601), 0.75);
}

// Reconstruct the normal of an animated height field on either side of the mesh.
public float3 sweatNormalWS(float3 positionWS, float3 normalWS, float height, float strength)
{
    float3 dx = ddx_coarse(positionWS);
    float3 dy = ddy_coarse(positionWS);
    float3 u = cross(dy, normalWS);
    float3 v = cross(normalWS, dx);
    float determinant = dot(dx, u);
    float3 gradient = mad(ddx_coarse(height), u, ddy_coarse(height) * v);
    return normalize(abs(determinant) * normalWS - (sign(determinant) * strength) * gradient);
}
