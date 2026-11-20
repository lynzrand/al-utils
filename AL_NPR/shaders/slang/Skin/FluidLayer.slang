import FluidMask;
import MaterialNoise;

public struct FluidLayer
{
    public float4 paint;
    public float3 normalTS;
}

public enum FluidFilter { Linear, Cubic }

public struct FluidMap<let filter : FluidFilter>
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
        if (filter == FluidFilter.Cubic)
            return sampleFluidMask(paintMap, paintSampler, uv);
        return paintMap.Sample(paintSampler, uv);
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
