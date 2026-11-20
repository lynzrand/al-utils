struct HairSurface
{
    float3 tangent, bitangent, normal;
    float3 toCamera, view, key, shadingNormal;
    float viewEdge, elevation;

    float3 toWorld(float3 local)
    {
        return float3(dot(float3(tangent.x, bitangent.x, normal.x), local),
                      dot(float3(tangent.y, bitangent.y, normal.y), local),
                      dot(float3(tangent.z, bitangent.z, normal.z), local));
    }
};

float3 safeUnit(float3 v)
{
    return v * rsqrt(max(dot(v, v), 1.1754944e-38));
}

float3 unpackHairNormal(float4 texel, float strength)
{
    float2 xy = float2(texel.r * texel.a, texel.g) * 2 - 1;
    float z = max(sqrt(1 - min(dot(xy, xy), 1)), 1e-16);
    return float3(xy * strength, lerp(1, z, saturate(strength)));
}

HairSurface makeHairSurface(HairInput input)
{
    HairSurface s;
    float scale = 1 / max(length(input.normalWS), 1.1754944e-38);
    s.tangent = input.tangentWS.xyz * scale;
    s.bitangent = (cross(input.normalWS, input.tangentWS.xyz) * input.tangentWS.w) * scale;
    s.normal = input.normalWS * scale;
    s.toCamera = cameraPosition.xyz - input.positionWS.xyz;
    s.view = orthographic == 0 ? normalize(s.toCamera) : float3(viewX.z, viewY.z, viewZ.z);
    s.key = safeUnit(mainLightDirection.xyz);
    float4 texel = normalMap.Sample(normalMapSampler, input.uv1Uv0.xy);
    s.shadingNormal = normalize(s.toWorld(unpackHairNormal(texel, 1 - dot(s.key, s.normal))));
    s.viewEdge = 1 - dot(s.shadingNormal, s.view);
    s.elevation = saturate((s.shadingNormal.y + 1.5) / 3);
    return s;
}

float2 materialUV(float2 uv, float4 scaleOffset)
{
    return mad(uv, scaleOffset.xy, scaleOffset.zw);
}

struct HairMasks
{
    float4 colors;
    float3 detail;
    float shade;
    float rim;
};

HairMasks sampleHairMasks(float2 uv)
{
    HairMasks mask;
    float green = detailMask1.Sample(detailMask1Sampler, materialUV(uv, _md_01_ST)).g;
    mask.detail = detailMask2.Sample(detailMask2Sampler, materialUV(uv, _md_02_ST)).rgb;
    mask.colors = colorMask.Sample(colorMaskSampler, materialUV(uv, _Hair_color_mask_ST));
    mask.shade = max(saturate(green / clamp(1 - _mdGPower * 0.5, 0.5, 1)) * _mdGIntensity, 0);
    mask.rim = 1 - max(max(mask.detail.g, pow(abs(green), 1 - _RimMaskPowermdG * 0.99)) * _RimMaskIntensity, 0);
    return mask;
}

float3 strandPigment(HairMasks mask)
{
    float3 color = lerp(_Main_color.rgb, _Sub_color_02.rgb, mask.colors.g * _Sub_color_02.a);
    color = lerp(color, _Sub_color_01.rgb, mask.colors.b * _Sub_color_01.a);
    color = lerp(color, _Add_skin_color.rgb, mask.detail.b * _Add_skin_color.a);
    if (_Ex_hair_color2_onoff != 0)
    {
        float blend = saturate(2 * (1 - smoothstep(0.05, 0.95, mask.colors.a)));
        color = lerp(color, _Ex_hair_color2.rgb, blend * _Ex_hair_color2.a);
    }
    if (_Ex_hair_color_onoff != 0)
        color = lerp(color, _Ex_hair_color.rgb, mask.colors.r * _Ex_hair_color.a);
    return color;
}
