import Materials.Hair.Bindings;
import Surface.SurfaceNormals;

public struct HairSurface
{
    public TangentFrame basis;
    public float3 toCamera, view, key, shadingNormal;
    public float viewEdge, elevation;
};

public float3 safeUnit(float3 v)
{
    return v * rsqrt(max(dot(v, v), 1.1754944e-38));
}

public HairSurface makeHairSurface(HairInput input)
{
    HairSurface s;
    s.basis = TangentFrame(input.normalWS, input.tangentWS);
    s.toCamera = cameraPosition.xyz - input.positionWS.xyz;
    s.view = orthographic == 0 ? normalize(s.toCamera) : float3(viewX.z, viewY.z, viewZ.z);
    s.key = safeUnit(mainLightDirection.xyz);
    float4 texel = normalMap.Sample(normalMapSampler, input.uv1Uv0.xy);
    s.shadingNormal = normalize(s.basis.toWorld(unpackScaledNormal(texel, 1 - dot(s.key, s.basis.normal))));
    s.viewEdge = 1 - dot(s.shadingNormal, s.view);
    s.elevation = saturate((s.shadingNormal.y + 1.5) / 3);
    return s;
}

public float2 materialUV(float2 uv, float4 scaleOffset)
{
    return mad(uv, scaleOffset.xy, scaleOffset.zw);
}

public struct HairMasks
{
    public float4 colors;
    public float3 detail;
    public float shade;
    public float rim;
};

public HairMasks sampleHairMasks(float2 uv)
{
    HairMasks mask;
    float green = detailMask1.Sample(detailMask1Sampler, materialUV(uv, _md_01_ST)).g;
    mask.detail = detailMask2.Sample(detailMask2Sampler, materialUV(uv, _md_02_ST)).rgb;
    mask.colors = colorMask.Sample(colorMaskSampler, materialUV(uv, _Hair_color_mask_ST));
    mask.shade = max(saturate(green / clamp(1 - _mdGPower * 0.5, 0.5, 1)) * _mdGIntensity, 0);
    mask.rim = 1 - max(max(mask.detail.g, pow(abs(green), 1 - _RimMaskPowermdG * 0.99)) * _RimMaskIntensity, 0);
    return mask;
}

public float3 strandPigment(HairMasks mask)
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
