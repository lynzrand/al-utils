// Shared by the face and body color passes. Stock evaluates Unity's directional
// prefix and local cluster. NPR substitutes the scene's authored directionals.
import Skin.Frame;
#if SKIN_FACE
import Face.Bindings;
#else
import Body.Bindings;
#endif
import PunctualLighting;
import Reflectance;
import ForwardPlus;
#if !SKIN_PREPASS
import PunctualShadows;
#endif
#if SKIN_NPR
import SceneLighting;
import MapLighting;
#endif

public struct SkinLights
{
    public float3 diffuse;
    public float3 diffuseBandNormal;
    public float3 wrapped;
    public float3 band;
    public float3 incident;
}

void accumulateSkinLight(inout SkinLights sum, float3 normal, float3 bandNormal,
                         float3 direction, float3 radiance)
{
    DiffuseLobes bandSurface = DiffuseLobes(bandNormal, direction);
    sum.diffuseBandNormal = mad(radiance, bandSurface.cosine, sum.diffuseBandNormal);
    sum.diffuse = mad(radiance, DiffuseLobes(normal, direction).cosine, sum.diffuse);
    sum.wrapped = mad(bandSurface.wrapped, radiance, sum.wrapped);
}

void accumulatePunctualSkin(inout SkinLights sum, uint index, float3 positionWS,
                            float3 normal, float3 bandNormal, float shadowFade)
{
#if !SKIN_PREPASS
    uint layer = (SKIN_NPR != 0) ? 2u : asuint(renderingLayer.x);
    if ((layer & asuint(lightLayerMasks[index].x)) == 0) return;
#endif
    PunctualLight light = getPunctualLight(index, positionWS);
#if SKIN_NPR
    if (light.attenuation == 0) return;
#endif
#if SKIN_PREPASS
    float visibility = 1;
    sum.incident = mad(light.color, light.attenuation, sum.incident);
#else
    float visibility = punctualVisibility(_AdditionalLightsShadowmapTexture, shadowCompare1,
        index, positionWS, light.direction, shadowFade, (SKIN_FACE != 0) && (SKIN_NPR != 0));
#endif
    float3 radiance = (light.attenuation * visibility) * light.color;
#if SKIN_NPR
    float3 incident = light.attenuation * light.color;
    float gain = rcp(directLightCompression(incident));
    radiance *= gain;
    float facing = bandFacing(bandNormal, light.direction);
#if SKIN_FACE
    sum.band += visibleFaceBand((incident * gain) * facing, visibility);
#else
    sum.band += perLightBand(radiance * facing);
#endif
#else
    accumulateSkinLight(sum, normal, bandNormal, light.direction, radiance);
#endif
}

public SkinLights evaluateSkinLights(StageInput input, float3 normal, float3 bandNormal)
{
    ForwardPlusGrid grid = ForwardPlusGrid(_FPParams0, _FPParams1, _FPParams2.x);
    SkinLights sum = {};
    float3 positionWS = input.positionWS.xyz;
    float3 cameraOffset = positionWS - _WorldSpaceCameraPos;
    float fade = 0;
#if !SKIN_PREPASS
    fade = saturate(mad(dot(cameraOffset, cameraOffset),
                        additionalShadowFadeParams.x, additionalShadowFadeParams.y));
#endif
#if SKIN_NPR
    [loop] for (uint i = 0; i < min(mapDirectionalCount, 32u); ++i)
    {
        MapDirectional light = mapDirectionals[i];
        float3 direction = light.direction.xyz * rsqrt(max(dot(light.direction.xyz, light.direction.xyz), 1e-20));
        float3 radiance = light.color.rgb * rcp(directLightCompression(light.color.rgb));
        sum.band += perLightBand(radiance * bandFacing(bandNormal, direction));
    }
#else
    [loop] for (uint i = 0; i < grid.directionalCount; ++i)
        accumulatePunctualSkin(sum, i, positionWS, normal, bandNormal, fade);
#endif

    float2 uv = rcp(_ScaledScreenParams.xy) * input.positionCS.xy;
    uv.y = 1 - mad(uv.y, _ScaleBiasRt.x, _ScaleBiasRt.y);
    float3 cameraBack = float3(unity_MatrixV0.z, unity_MatrixV1.z, unity_MatrixV2.z);
    ClusterLights cluster = grid.localLights(uv, dot(-cameraBack, cameraOffset), unity_OrthoParams.w == 0);
    uint index;
    [loop] while (cluster.next(index))
        accumulatePunctualSkin(sum, index, positionWS, normal, bandNormal, fade);
#if SKIN_NPR
    // The NPR band supplies the direct response. The original ramp still
    // samples its unlit column for the material-specific palette tint.
    sum.band *= rcp(bandCompression(sum.band));
#endif
    return sum;
}

public float3 skinKeyColor()
{
#if SKIN_NPR
    float3 ambient = max(float3(probe.ar.w, probe.ag.w, probe.ab.w), 0.001);
    return dot(ambient, float3(0.212673, 0.715152, 0.072175));
#else
    return _MainLightColor.rgb;
#endif
}

public float3 skinKeyDirection()
{
#if SKIN_NPR
    float3 direction = mad(probe.ab.xyz, 0.072175, mad(probe.ag.xyz, 0.715152, probe.ar.xyz * 0.212673));
    direction.y += 0.0001;
    return direction;
#else
    return _MainLightPosition.xyz;
#endif
}

public float skinMainVisibility(float3 positionWS)
{
#if SKIN_NPR || SKIN_PREPASS
    return 1;
#else
    float3 uvz = mainShadowCoord(positionWS);
    float shadow = _MainLightShadowmapTexture.SampleCmpLevelZero(shadowCompare1, uvz.xy, uvz.z);
    return (uvz.z > 0 && uvz.z < 1) ? mad(shadow, mainShadowParams.x, 1 - mainShadowParams.x) : 1;
#endif
}

public float skinPaletteWeight(float stockWeight, SkinLights lights)
{
#if SKIN_NPR
    return bandWeight(lights.band);
#else
    return stockWeight;
#endif
}

public float3 skinBounce(SkinLights lights)
{
#if SKIN_NPR
    return lights.band;
#else
    return lerp(lights.diffuseBandNormal, lights.wrapped, 0.5);
#endif
}

public float3 applySkinFill(float3 color, float3 pigment, float3 ambient, SkinLights lights)
{
#if SKIN_NPR
    return mad(pigment, skinFill(ambient, skinPaletteWeight(0, lights)), color);
#else
    return color;
#endif
}
