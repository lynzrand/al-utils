import Materials.Skin.FluidMask;
import Surface.MaterialNoise;

public struct FluidLayer
{
    public float4 paint;
    public float3 normalTS;
}

public interface IFluidFilter
{
    static float4 samplePaint(Texture2D<float4> paint, SamplerState paintSampler, float2 uv);
}

public struct LinearFluidFilter : IFluidFilter
{
    public static float4 samplePaint(Texture2D<float4> paint, SamplerState paintSampler, float2 uv)
    {
        return paint.Sample(paintSampler, uv);
    }
}

public struct CubicFluidFilter : IFluidFilter
{
    public static float4 samplePaint(Texture2D<float4> paint, SamplerState paintSampler, float2 uv)
    {
        return sampleFluidMask(paint, paintSampler, uv);
    }
}

public struct FluidMap<Filter : IFluidFilter>
{
    public Texture2D<float4> paintMap;
    public SamplerState paintSampler;
    public float4 scaleOffset;
    public float2 texelSize;
    public float noiseScale;
    public float noiseAmount;
    public float normalScale;

    float4 readPaint(float2 uv)
    {
        return Filter.samplePaint(paintMap, paintSampler, uv);
    }

    public FluidLayer sampleLayer(float2 materialUV)
    {
        float2 uv = mad(materialUV, scaleOffset.xy, scaleOffset.zw);
        float2 noise = float2(fluidNoise(uv * noiseScale),
                              fluidNoise((uv + float2(12, 34)) * noiseScale));
        uv = mad((noise - 0.5) * noiseAmount, texelSize, uv);

        FluidLayer layer;
        layer.paint = readPaint(uv);
        float heightX = readPaint(uv + float2(texelSize.x, 0)).a;
        float heightY = readPaint(uv + float2(0, texelSize.y)).a;
        float2 gradient = (layer.paint.a - float2(heightX, heightY)) * normalScale;
        layer.normalTS = normalize(float3(gradient, 1));
        return layer;
    }
}
