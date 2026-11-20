// Unity's wetness and sheer controls both address front top, front bottom,
// back top and back bottom. Each effect decodes those zones from the mask RGB.
public float regionWetness(float3 region, float2 liquid, float4 strengths)
{
    float2 wet = smoothstep(0.1, 0.6, liquid);
    float4 amount = max(wet.r * strengths, wet.g * saturate(strengths - 1));
    float4 zones = float4(saturate(region.rg - region.gr), region.b, region.r * region.g);
    return saturate(dot(min(amount, zones), 1));
}

public float regionSheerness(float3 region, float detail, float2 scaleOffset, float4 strengths)
{
    float3 exclusive = saturate(region - max(region.zzy, region.yxx));
    float4 zones = float4(exclusive, saturate(min(region.r, region.g) - region.b));
    float strength = saturate(mad(detail, scaleOffset.x, scaleOffset.y));
    return saturate(dot(min(zones, strength * strengths), 1));
}

public struct ClothDyes
{
    public float3 base, red, green, blue;

    public float3 color(float3 mask)
    {
        float3 dye = lerp(base, red, mask.r);
        dye = lerp(dye, green, mask.g);
        return lerp(dye, blue, mask.b);
    }
};
