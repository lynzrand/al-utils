import FluidMask;

Texture2D<float4> fluidMask : register(t0);
SamplerState fluidSampler : register(s0);

float4 FluidSample(float2 uv : TEXCOORD0) : SV_Target
{
    return sampleFluidMask(fluidMask, fluidSampler, uv);
}
