import Materials.Cloth.Bindings;
import Materials.Cloth.FabricSampling;
import Materials.Cloth.LightingFrame;
import Materials.Cloth.Surface;
import Surface.MaterialColor;
import Lighting.Reflectance;
import Surface.SurfaceNormals;

public struct ClothPigment
{
    public float3 dry, wetTint, wet, specular;
    public float4 detail;
    public float4 base;
    public float lineDetail, wetBlend, sheer;
};

float4 matcapRegions(float3 mask, float overrideAmount)
{
    float3 exclusive = float3(saturate(mask.r - max(mask.g, mask.b)), saturate(mask.g - mask.b), mask.b);
    float3 regions = lerp(mask, exclusive, overrideAmount);
    return float4(regions, 1 - saturate(dot(regions, 1)));
}

// Apply each layer to the preceding layer's result. Even a masked-out layer
// can desaturate that result through its authored alpha and power.
float3 addMatcap(float3 color, float4 layer, float region, float power)
{
    float3 offset = layer.rgb - 0.5;
    float3 combined = select(layer.rgb > 0.5, mad(layer.rgb, 2, color) - 1, mad(offset, 2, color));
    float amount = layer.a * power;
    float3 result = saturate(lerp(color, combined, saturate((region * layer.a) * power)));
    return lerp(result, dot(result, luminance601), 0.25 * amount);
}

float4 sampleMatcap(float2 uv, float slice)
{
    return _TexTAMatcap.SampleBias(matcapSampler, float3(uv, slice), mipAndAlpha.x);
}

// Object-space Y and Z partition the cloth into front/back and top/bottom.
float4 clothFinishZones(float3 positionOS)
{
    float2 blend = saturate(mad(positionOS.zy + float2(0.8, 1), float2(1.8181818, 1.1428572), -1));
    return float4(min(blend.x, blend.y), max(blend.x - blend.y, 0),
                  max(blend.y - blend.x, 0), 1 - max(blend.x, blend.y));
}

float3 wetSheen(ClothInput input, ClothFrame frame, ClothSurface surface, ClothKey key, float3 tint, out float sheerStrength)
{
    float2 uv = input.uv.xy;
    float detail = _Detail_mask_01.Sample(sampler_Detail_mask_01, mad(uv, _Detail_mask_01_ST.xy, _Detail_mask_01_ST.zw)).r;
    float4 zones = clothFinishZones(input.positionOS.xyz);
    float4 strength = float4(_nureftop, _nurefbot, _nurebtop, _nurebbot);
    float wetDetail = saturate(dot(min(zones, detail * strength), 1));
    float wetArea = max(saturate(dot(min(zones, strength), 1)), 0.3 * _AseIntensity);
    float2 normalUV = mad(uv, _Normal_map_ST.xy, _Normal_map_ST.zw);
    float3 wet = unpackScaledNormal(_Normal_map.Sample(sampler_Normal_map, normalUV), _NureNormalPower);
    float3 baseNormal = lerp(surface.baseNormalTS, wet, wetDetail);

    float stepUV = (_SukeNormalLength * _SukeNormalLength * _SukeNormalLength) * 0.1;
    float2 height = float2(
        _Detail_mask_01.Sample(sampler_Detail_mask_01, uv + float2(stepUV, 0)).r,
        _Detail_mask_01.Sample(sampler_Detail_mask_01, uv + float2(0, stepUV)).r);
    float3 flat = float3(0, 0, 1);
    float3 sheer = normalize(float3((height - detail) * _SukeNormalPower, 1));
    sheerStrength = sheerAmount(surface.region, detail);
    sheer = lerp(flat, normalize(lerp(flat, sheer, sheerStrength)), _sukeONOFF);
    float3 normalWS = frame.basis.toWorld(normalize(combineNormalSlopes(baseNormal, sheer)));

    float3 reflection = saturate(0.3 * sampleReflection(reflect(-frame.view, normalWS), 4.05));
    float3 reflectedTint = saturate(lerp(tint, tint * reflection, 0.5));
    float3 base = lerp(tint * mad(-wetDetail, _AseIntensity, 1), reflectedTint, wetArea);
    float3 normal = normalize(normalWS);
    float3 diffuse = mad(max(dot(normal, key.direction), 0), key.litColor, 2 * glstate_lightmodel_ambient.rgb) * tint;
    float specular = wetSpecular(normal, key.viewHalf, wetArea);
    float3 sheen = mad(diffuse, 0.2, wetArea * (specular * key.litColor));
    return saturate(mad(sheen, wetArea, base));
}

public ClothPigment clothPigment(ClothInput input, ClothFrame frame, ClothSurface surface, ClothKey key)
{
    ClothPigment p;
    float2 uv = input.uv.xy;
    p.base = _Create_main_texture.SampleBias(sampler_Create_main_texture, uv, _Mip);
    p.base.rgb = tintCloth(p.base.rgb, uv, _ColorMask, sampler_ColorMask);
    float3 base = p.base.rgb;
    float3 normalWS = frame.basis.toWorld(surface.baseNormalTS);
    float3 normal = normalize(normalWS);
    float2 matUV = mad(viewAxes(normal).xy, 0.5, 0.5);
    float3 mask = _Matcap_mask.Sample(sampler_Matcap_mask, uv).rgb;
    float4 regions = matcapRegions(mask, _MaskOverride);
    float3 color = addMatcap(base, sampleMatcap(matUV, _MatcapIndex1), regions.x, _Matcap_power_01);
    color = addMatcap(color, sampleMatcap(matUV, _MatcapIndex2), regions.y, _Matcap_power_02);
    color = addMatcap(color, sampleMatcap(matUV, _MatcapIndex3), regions.z, _Matcap_power_03);
    color = addMatcap(color, sampleMatcap(matUV, _MatcapIndex4), regions.w, _Matcap_power_04);
    float3 matcap = lerp(base, color, _Matcaponoff);

    p.detail = _Detail_mask_01.Sample(sampler_Detail_mask_01, uv);
    float occlusion = 1 - p.detail.g;
    float3 incident = saturate(clamp(key.visibility, 0.66, 1) * (occlusion * key.color));
    float4 finishRegions = matcapRegions(mask, _MaskOverrideGloss);
    float4 glossLayers = float4(_Gloss_power_01, _Gloss_power_02, _Gloss_power_03, _Gloss_power_04);
    float gloss = saturate(dot(sampleMatcap(matUV, 14).a * glossLayers, finishRegions));
    float smoothness = gloss * occlusion;
    float3 diffuse = mad(max(mad(dot(normal, key.direction), 1.5, -0.5), 0),
                         key.litColor, 2 * glstate_lightmodel_ambient.rgb);
    diffuse *= smoothness * saturate(incident + tintSaturation(matcap, 1.5));
    float specular = blinnPhong(normal, key.viewHalf, exp2(mad(smoothness, 10, 1)));
    float3 highlight = saturate(mad(diffuse, 0.3, (smoothness * min(dot(incident, luminance709), 1)) * (specular * key.litColor)));

    p.specular = highlight;
    float roughness = 1 - mad(gloss, 2.7, 0.3);
    float lod = reflectionProbeMip(roughness);
    float3 reflection = 0.5 * sampleReflection(reflect(-frame.view, normalWS), lod);
    reflection = incident * saturate(lerp(reflection, dot(reflection, luminance601), 0.66));
    float4 metallicLayers = float4(_Metallic_power_01, _Metallic_power_02, _Metallic_power_03, _Metallic_power_04);
    float metallic = saturate(dot(sampleMatcap(matUV, 15).a * metallicLayers, finishRegions));
    metallic *= mad(dot(matcap, luminance601), 0.5, 0.5);
    color = saturate(lerp(matcap, reflection * matcap, mad(smoothness, 0.5, metallic)));
    color = tintSaturation(color, clamp(mad(metallic, 0.5, 1), 1, 3));
    color = saturate(mad(metallic * 0.1, reflection, color));
    color = saturate(mad(mad(-gloss * saturate(dot(matcap, 0.4)), 0.2, 1), color, smoothness * highlight));
    float2 curvature = _Detail_mask_02.Sample(sampler_Detail_mask_02, uv).rg;
    p.lineDetail = curvature.g;
    p.dry = lerp(color, _Color_Cuvature.rgb, curvature.r * _Color_Cuvature.a);
    p.wetBlend = smoothstep(0.01, 0.7, surface.wetness);
    float3 wetTint = saturate(lerp(p.dry, float3(0.957614, 0.9262637, 0.8728591), p.wetBlend));
    p.wetTint = lerp(p.dry, wetTint, p.wetBlend);
    p.wet = wetSheen(input, frame, surface, key, p.wetTint, p.sheer);
    return p;
}
