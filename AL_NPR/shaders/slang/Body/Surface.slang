import Body.Bindings;
import Body.Material;
import Body.Pigment;
import Skin.Frame;
import Skin.Lighting;
import Skin.FluidLayer;
import Skin.FluidBindings;
import SurfaceNormals;
import Skin.SurfaceMath;
import MaterialColor;
import Reflectance;

#ifndef FILTER_BODY_OIL
#define FILTER_BODY_OIL 0
#endif
#if FILTER_BODY_OIL && SKIN_NPR && !SKIN_PREPASS
static const FluidFilter bodyFluidFilter = FluidFilter.Cubic;
#else
static const FluidFilter bodyFluidFilter = FluidFilter.Linear;
#endif

public struct BodySurface
{
    public TangentFrame basis;
    public float3 view, key, cameraOffset;
    public float3 normalWS, unitNormal, artisticNormal, dryNormal;
    public float3 substrate, pigment, paintedPigment, beadReflection;
    public float4 detail, regions;
    public float bustMask, flatten, liquid, hairAlpha, nippleMask, dent, lineMask;
};

float4 sampleExtra(float2 uv, float slice)
{
    return _TexEX.SampleBias(extraArraySampler, float3(uv, slice), _GlobalMipBias.x);
}

float4 sampleDetail(float2 uv, float slice)
{
    return _Detail_mask_01.SampleBias(detailArraySampler, float3(uv, slice), _GlobalMipBias.x);
}

public float3 toView(float3 direction)
{
    return mad(unity_MatrixV2.xyz, direction.z,
               mad(unity_MatrixV0.xyz, direction.x, unity_MatrixV1.xyz * direction.y));
}

public float3 unitDirection(float3 v)
{
    return v * rsqrt(max(dot(v, v), 1.1754944e-38));
}

float3 flattenedChestNormal(float3 normal)
{
    float3 local = worldToObject0.xyz * normal.x + worldToObject1.xyz * normal.y + worldToObject2.xyz * normal.z;
    local = unitDirection(local) * float3(0.3, 0.3, 1);
    return unitDirection(objectToWorld0.xyz * local.x + objectToWorld1.xyz * local.y + objectToWorld2.xyz * local.z);
}

float3 blendBumps(float3 a, float3 b)
{
    return normalize(combineNormalSlopes(a, b));
}

float3 sampleNipple(float2 uv, out float4 pigment)
{
    float2 size = mad(_Nip_size, 0.27, float2(0.54, 0.04000002));
    float2 resized = mad(uv, 2 - size.x * 2, size.y);
    uv = lerp(uv, resized, saturate(mad(length(uv - 0.5) + 0.05, 8.695652, -1)));
    pigment = _Nip.Sample(sampler_Nip, uv);
    float2 x = _Nip.Sample(sampler_Nip, uv + float2(0.0027, 0)).rg;
    float2 y = _Nip.Sample(sampler_Nip, uv + float2(0, 0.0027)).rg;
    // The second height difference uses the X tap as its reference in both game passes.
    float xHeight = max(x.r, x.g);
    float2 slope = float2(xHeight - max(pigment.r, pigment.g), max(y.r, y.g) - xHeight);
    return normalize(float3(-slope * (pigment.a * _Nip_color_01.a * 10), 1));
}

float liquidCoverage(float2 uv, float2 tiledUV)
{
    float2 pattern = smoothstep(0.1, 0.6, sampleExtra(tiledUV, 1).gr);
    float3 mask = sampleExtra(uv, 0).rgb;
    float4 zones = float4(saturate(mask.r - mask.g), saturate(mask.g - mask.r), mask.b, mask.g * mask.r);
    float4 levels = float4(_liquidftop, _liquidfbot, _liquidbtop, _liquidbbot);
    float4 fill = min(zones, max(pattern.r * saturate(levels - 1), pattern.g * levels));
    return saturate(dot(fill, float4(1)));
}

float4 sampleBodyMasks(inout BodySurface s, StageInput input, float2 uv)
{
    s.detail = sampleDetail(uv, 0);
    s.regions = sampleExtra(uv, 3);
    float4 detailColor = sampleExtra(uv, 2);
    s.bustMask = saturate(mad(s.detail.a - 0.66, -4.166667, 1));
    float bustSize = (_Bust_size - 0.25) * 4;
    s.flatten = s.regions.g * saturate(1 - bustSize);
    float lineWidth = min(1.5 - saturate((_Bust_size - 0.5) * 2.5)
                              * saturate((1 - detailColor.a) * 5.263158), 1) * (1 - s.detail.r) * _Line_width;
    s.lineMask = min(saturate(ceil(lineWidth)), sampleDetail(uv, 1).r) * _linetexon;
    s.dent = saturate((_Dent_power - 0.5) * 0.2)
           * (_Create_dent_texture.Sample(sampler_Create_dent_texture, input.uv0Uv1.zw).r * sqrt(_Dent_power));
    return detailColor;
}

struct WetBody
{
    float sweat;
    float3 reflectionNormal;
};

WetBody sampleBodyNormals(inout BodySurface s, StageInput input, float3 fluidNormal, out float4 nipple)
{
    WetBody wet;
    float2 uv = input.uv0Uv1.xy;
    float3 nippleNormal = sampleNipple(input.uv2Uv3.xy, nipple);
    s.nippleMask = nipple.a * _Nip_color_01.a * nipple.b;
    float3 baseNormal = unpackScaledNormal(_Normal_map.Sample(sampler_Normal_map, uv), _SkinIntensity);
    baseNormal = lerp(baseNormal, float3(0, 0, 1), s.regions.g * saturate((_Bust_size - 0.25) * 4));
    float3 skinNormal = blendBumps(baseNormal, nippleNormal);
    s.dryNormal = normalize(s.basis.toWorld(skinNormal));

    float2 tiledUV = mad(_LiquidTiling.zw, uv, _LiquidTiling.xy);
    float liquid = liquidCoverage(uv, tiledUV);
    s.liquid = smoothstep(0.01, 0.7, liquid);
    float3 liquidNormal = unpackScaledNormal(_LiquidBump.Sample(sampler_LiquidBump, tiledUV), 2 * liquid);
    float3 wetNormal = blendBumps(liquidNormal, skinNormal);
    float height = sweatHeight(uv, _TimeParameters.x, _SweatNoise);
    float sweat = height * _AseIntensity;
    float3 bead = s.basis.toTangent(sweatNormalWS(input.positionWS.xyz, s.basis.normal, height, _AseIntensity * 0.2));
    float3 beadShape = s.basis.toTangent(sweatNormalWS(input.positionWS.xyz, s.basis.normal, height, 0.2));
    s.beadReflection = max(height - saturate(bead.y), 0) * decodeProbe(unity_SpecCube0.SampleLevel(
        samplerunity_SpecCube0, reflect(-s.view, s.basis.toWorld(bead)), 0.97800004), specCubeHDR);
    float3 layered = blendBumps(blendBumps(lerp(wetNormal, beadShape, sweat * 4), bead), fluidNormal);
    s.normalWS = s.basis.toWorld(layered);
    s.unitNormal = normalize(s.normalWS);
    s.artisticNormal = lerp(s.unitNormal, flattenedChestNormal(s.unitNormal), s.flatten);

    wet.reflectionNormal = s.basis.toWorld(lerp(wetNormal, beadShape, sweat));
    wet.sweat = sweat;
    return wet;
}

void sampleBodyPigment(inout BodySurface s, StageInput input, float4 detailColor, float4 nipple,
                       FluidLayer fluid, WetBody wet, float visibility)
{
    float2 uv = input.uv0Uv1.xy;
    float moisture = max(min(wet.sweat, _AseIntensity), s.liquid);
    float3 reflection = wetSkinReflection(unity_SpecCube0, samplerunity_SpecCube0, specCubeHDR,
        reflect(-s.view, wet.reflectionNormal), input.positionOS.xy, max(_AseIntensity, _NureIntensity), moisture);
    float4 base = _Create_main_texture.Sample(sampler_Create_main_texture, mad(uv, _Create_main_texture_ST.xy, _Create_main_texture_ST.zw));
    float4 hair = _Under_hair_texture.Sample(sampler_Under_hair_texture, input.uv2Uv3.zw);
    s.hairAlpha = hair.a * _Under_hair_color.a;
    float3 pigment = bodyPigment(base, nipple, hair, detailColor.rgb);
    pigment = saturate(lerp(pigment, float3(0.957614, 0.9262637, 0.8728591), s.liquid));
    float gloss = max(_AseIntensity * 0.3, _NureIntensity);
    pigment = lerp(pigment, pigment * saturate(1 - wet.sweat), gloss);
    float3 color = skinKeyColor();
    float3 specular = blinnPhong(normalize(wet.reflectionNormal), normalize(s.view + normalize(skinKeyDirection())), 512)
                    * (visibility * (color / (peakChannel(color) + 1e-7)));
    float3 substrate = saturate(mad(specular, max(s.liquid, gloss), saturate(reflection + pigment)));
    s.substrate = substrate;
    s.pigment = tintSaturation(substrate, 0.8);
    float3 fluidNormal = s.basis.toWorld(fluid.normalTS);
    float facingAway = max(1 - dot(fluidNormal, normalize(s.key)), 0.0001);
    s.paintedPigment = skinFluidPigment().apply(substrate, fluid.paint, facingAway, dot(fluidNormal, normalize(toView(s.cameraOffset))));
}

public BodySurface sampleBody(StageInput input, float visibility)
{
    BodySurface s = { TangentFrame(input.normalWS, input.tangentWS) };
    s.key = unitDirection(skinKeyDirection());
    s.cameraOffset = _WorldSpaceCameraPos - input.positionWS.xyz;
    s.view = unity_OrthoParams.w == 0 ? normalize(s.cameraOffset)
           : float3(unity_MatrixV0.z, unity_MatrixV1.z, unity_MatrixV2.z);
    float4 detailColor = sampleBodyMasks(s, input, input.uv0Uv1.xy);
    FluidLayer fluid = skinFluidMap<bodyFluidFilter>().sampleLayer(input.uv0Uv1.xy);
    float4 nipple;
    WetBody wet = sampleBodyNormals(s, input, fluid.normalTS, nipple);
    sampleBodyPigment(s, input, detailColor, nipple, fluid, wet, visibility);
    return s;
}
