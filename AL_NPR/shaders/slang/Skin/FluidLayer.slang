import FluidMask;
import MaterialNoise;

#ifndef FILTER_BODY_OIL
#define FILTER_BODY_OIL 0
#endif

struct FluidLayer
{
    float4 paint;
    float3 normalTS;
}

float4 readFluidPaint(float2 uv)
{
#if FILTER_BODY_OIL && SKIN_NPR && !SKIN_FACE
    return sampleFluidMask(_FluidTex, sampler_FluidTex, uv);
#else
    return _FluidTex.Sample(sampler_FluidTex, uv);
#endif
}

FluidLayer sampleFluidLayer(float2 materialUV)
{
    float2 uv = mad(materialUV, _FluidTex_ST.xy, _FluidTex_ST.zw);
    float2 noise = float2(fluidNoise(uv * _Fluid_Noise_Scale),
                          fluidNoise((uv + float2(12, 34)) * _Fluid_Noise_Scale));
    float2 offset = (noise - 0.5) * _Fluid_Noise_Amount;
    uv = mad(offset, _FluidTex_TexelSize.xy, uv);

    FluidLayer layer;
    layer.paint = readFluidPaint(uv);
    float heightX = readFluidPaint(uv + float2(_FluidTex_TexelSize.x, 0)).a;
    float heightY = readFluidPaint(uv + float2(0, _FluidTex_TexelSize.y)).a;
    float2 gradient = (layer.paint.a - float2(heightX, heightY)) * _FluidNormalScale;
    layer.normalTS = normalize(float3(gradient, 1));
    return layer;
}
