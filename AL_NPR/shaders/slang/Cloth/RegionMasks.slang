float3 clothRegion(float2 uv)
{
    return _liquidmask.Sample(sampler_liquidmask, mad(uv, _liquidmask_ST.xy, _liquidmask_ST.zw)).rgb;
}

float clothWetness(float2 liquidUV, float3 region)
{
    float2 wet = smoothstep(0.1, 0.6, _Liquid.Sample(sampler_Liquid, liquidUV).rg);
    float4 strengths = float4(_liquidftop, _liquidfbot, _liquidbtop, _liquidbbot);
    float4 amount = max(wet.r * strengths, wet.g * saturate(strengths - 1));
    float4 zones = float4(saturate(region.rg - region.gr), region.b, region.r * region.g);
    return saturate(dot(min(amount, zones), 1));
}

#if defined(CLOTH_CUTOUT) || defined(CLOTH_COLOR_PASS)
float3 tintCloth(float3 pigment, float2 uv)
{
    float3 mask = _ColorMask.Sample(sampler_ColorMask, mad(uv, _ColorMask_ST.xy, _ColorMask_ST.zw)).rgb;
    float3 dye = lerp(_Main_color_04.rgb, _Main_color_01.rgb, mask.r);
    dye = lerp(dye, _Main_color_02.rgb, mask.g);
    dye = lerp(dye, _Main_color_03.rgb, mask.b);
    return _Main_color_switchtest != 0 ? dye * pigment : pigment;
}

float sheerAmount(float3 region, float detail)
{
    float3 exclusive = saturate(region - max(region.zzy, region.yxx));
    float4 zones = float4(exclusive, saturate(min(region.r, region.g) - region.b));
    float strength = saturate(mad(detail, _SukeScale, _SukeOffset));
    return saturate(dot(min(zones, strength * float4(_sukeftop, _sukefbot, _sukebtop, _sukebbot)), 1));
}
#endif
