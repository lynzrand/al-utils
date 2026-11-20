/// Unity's wetness and sheer controls both address front top, front bottom,
/// back top and back bottom. Each effect decodes those zones from the mask RGB.
public float regionWetness(float3 region, float2 liquid, float4 strengths)
{
    float2 wet = smoothstep(0.1, 0.6, liquid);
    float4 amount = max(wet.r * strengths, wet.g * saturate(strengths - 1));
    float4 zones = float4(saturate(region.rg - region.gr), region.b, region.r * region.g);
    return saturate(dot(min(amount, zones), 1));
}

/// Combines three exclusive RGB zones and their red/green overlap with scaled detail and four authored strengths.
public float regionSheerness(float3 region, float detail, float2 scaleOffset, float4 strengths)
{
    float3 exclusive = saturate(region - max(region.zzy, region.yxx));
    float4 zones = float4(exclusive, saturate(min(region.r, region.g) - region.b));
    float strength = saturate(mad(detail, scaleOffset.x, scaleOffset.y));
    return saturate(dot(min(zones, strength * strengths), 1));
}

/// Base dye and its three ordered color-mask overrides.
public struct ClothDyes
{
    /// Layer 4 dye, applied before the mask's RGB layers.
    public float3 base;
    /// Layer 1 dye, blended by the mask's red channel.
    public float3 red;
    /// Layer 2 dye, blended after red by the green channel.
    public float3 green;
    /// Layer 3 dye, blended last by the blue channel.
    public float3 blue;

    /// Applies the red, then green, then blue dye weights over the unmasked dye.
    public float3 color(float3 mask)
    {
        float3 dye = lerp(base, red, mask.r);
        dye = lerp(dye, green, mask.g);
        return lerp(dye, blue, mask.b);
    }
};
