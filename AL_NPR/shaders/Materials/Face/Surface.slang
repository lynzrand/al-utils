import Materials.Face.Bindings;
import Materials.Face.Material;
import Materials.Skin.Frame;

/// Detail textures and liquid-surface data shared by face color and outline shading.
public struct FaceDetail
{
    /// Primary detail RGBA. R restricts outlines and liquid, G influences shade and rim, B controls ramp
    /// shifts and rim masking.
    public float4 mask;
    /// Secondary detail RGBA. G reduces direct palette weight and B masks the rim and alters normal and line
    /// shading.
    public float4 secondary;
    /// Local liquid coverage from the tiled pattern, material level and painted exclusion mask.
    public float liquid;
    /// Decoded tangent-space bump vector scaled by liquid coverage, before combining the fluid layer.
    public float3 liquidNormalTS;
}

/// Samples the two detail masks in UV0 and returns the local liquid coverage and tangent-space wet normal.
public FaceDetail sampleFaceDetail(float2 uv)
{
    FaceDetail detail;
    detail.mask = _Detail_mask_01.Sample(sampler_Detail_mask_01, mad(uv, _Detail_mask_01_ST.xy, _Detail_mask_01_ST.zw));
    detail.secondary = _Detail_mask_02.Sample(sampler_Detail_mask_02, mad(uv, _Detail_mask_02_ST.xy, _Detail_mask_02_ST.zw));
    float2 liquidUV = mad(_LiquidTiling.zw, uv, _LiquidTiling.xy);
    float2 layers = _Texture2.Sample(sampler_Texture2, liquidUV).rg;
    float2 edge = saturate((layers - 0.1) * 2);
    layers = edge * edge * mad(edge, -2, 3);
    float mask = saturate((detail.secondary.b - detail.mask.r) + saturate(mad(1 - detail.mask.g, 1.23, -0.31)));
    detail.liquid = min(mask, max(layers.r * _liquidface, layers.g * saturate(_liquidface - 1)));

    float4 packed = _LiquidBump.Sample(sampler_LiquidBump, liquidUV);
    float2 xy = mad(float2(packed.r * packed.a, packed.g), 2, -1);
    float z = sqrt(1 - min(dot(xy, xy), 1));
#if SKIN_PREPASS
    z = max(z, 1e-16);
#endif
    float strength = detail.liquid + detail.liquid;
    detail.liquidNormalTS = float3(xy * strength, mad(min(strength, 1), z - 1, 1));
    return detail;
}

/// Combines line color with pigment darkened by a view-dependent shadow, using the secondary blue detail
/// channel.
public float3 faceLineTint(float3 viewDirection, float3 geometricNormal, float detailMask, float3 pigment)
{
    float3 view = normalize(viewDirection + float3(0, 0.36, -0.03));
    float facing = dot(view, normalize(geometricNormal));
    float shadow = (1 - detailMask) * (saturate(mad(facing + 1, -0.75, 1.5)) * _Shadow_color.a);
    float3 shaded = lerp(float3(1), _Shadow_color.rgb, shadow);
    return mad(mad(_Line_power, 0.8, 0.2), mad(-shaded, pigment, _Line_color), shaded * pigment);
}

/// Returns a world-space surface-to-eye direction from camera position or the constant orthographic camera
/// axis.
public float3 faceViewDirection(float3 positionWS)
{
    float3 cameraBack = float3(unity_MatrixV0.z, unity_MatrixV1.z, unity_MatrixV2.z);
    return unity_OrthoParams.w == 0 ? normalize(_WorldSpaceCameraPos - positionWS) : cameraBack;
}
