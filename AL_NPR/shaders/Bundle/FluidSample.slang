import Materials.Skin.FluidMask;

/// Unity's painted RGBA fluid mask. Filtering preserves all four channels.
Texture2D<float4> fluidMask : register(t0);
/// Bilinear sampler used to combine pairs of cubic B-spline tap weights.
SamplerState fluidSampler : register(s0);

/// Sample the transformed mask UV in TEXCOORD0 and return RGBA. Single-mip, nondegenerate masks use cubic
/// reconstruction.
float4 FluidSample(float2 uv : TEXCOORD0) : SV_Target
{
    return sampleFluidMask(fluidMask, fluidSampler, uv);
}
