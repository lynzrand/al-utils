import Materials.Hair.Bindings;
import Surface.SurfaceNormals;

/// Per-fragment strand frame and view-dependent geometry used by the ramp, wet layer, and rim.
public struct HairSurface
{
    /// World-space strand tangent, bitangent, and geometric normal.
    public TangentFrame basis;
    /// Unnormalized vector from the fragment to the camera in world space.
    public float3 toCamera;
    /// World-space surface-to-eye direction. Orthographic cameras use a constant axis.
    public float3 view;
    /// World-space unit direction toward the main light.
    public float3 key;
    /// World-space strand normal after light-dependent normal-map scaling.
    public float3 shadingNormal;
    /// One minus the dot product of the shading normal and the view direction.
    public float viewEdge;
    /// Clamped upward-facing factor from the shading normal for the rim.
    public float elevation;
};

/// Normalize a direction with a lower bound on squared length so zero vectors stay zero.
public float3 safeUnit(float3 v)
{
    return v * rsqrt(max(dot(v, v), 1.1754944e-38));
}

/// Construct the strand frame, camera vectors, and light-dependent normal from interpolated mesh data.
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

/// Transform mesh UV by Unity's scale in XY and offset in ZW.
public float2 materialUV(float2 uv, float4 scaleOffset)
{
    return mad(uv, scaleOffset.xy, scaleOffset.zw);
}

/// Pigment and detail samples, with the shade and rim weights derived from them.
public struct HairMasks
{
    /// RGBA dye weights from the transformed color-mask lookup.
    public float4 colors;
    /// R masks the highlights, G suppresses rim, and B blends the skin tint.
    public float3 detail;
    /// Nonnegative strength of the authored shadow derived from the first detail mask.
    public float shade;
    /// Remaining rim weight after both detail masks suppress it.
    public float rim;
};

/// Sample UV0 with each material texture's own transform and derive shade and rim weights.
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

/// Layer secondary dyes, skin tint, and optional extra colors onto the base strand RGB.
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
