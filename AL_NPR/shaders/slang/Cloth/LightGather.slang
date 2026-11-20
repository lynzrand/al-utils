import Cloth.Bindings;
import ForwardPlus;
import PunctualLighting;
import Reflectance;
#ifndef CLOTH_PREPASS
import PunctualShadows;
#endif
#ifdef CLOTH_NPR
import MapLighting;
import SceneLighting;
#endif

public struct ClothLights
{
    public float3 diffuse;
    public float3 wrapped;
    public float3 unshaded;
#ifdef CLOTH_NPR
    public float3 bandColor;
    public float3 bandDirection;
    public float band;
#endif
};

#ifdef CLOTH_NPR
void accumulateBand(inout ClothLights lights, float3 color, float3 direction,
                    float3 normalWS, float visibility)
{
    float3 capped = color / directLightCompression(color);
    float3 band = perLightBand(capped * visibility * bandFacing(normalWS, direction));
    lights.bandColor += band;
    lights.bandDirection = mad(direction, dot(band, float3(0.212673, 0.715152, 0.072175)), lights.bandDirection);
}
#endif

void addClothLight(inout ClothLights lights, uint index, float3 positionWS, float3 normalWS, float fade)
{
    PunctualLight light = getPunctualLight(index, positionWS);
#ifdef CLOTH_NPR
    if ((asuint(lightLayerMasks[index].x) & 2) == 0 || light.attenuation == 0)
        return;
#elif !defined(CLOTH_PREPASS)
    if ((asuint(lightLayerMasks[index].x) & asuint(renderingLayer.x)) == 0)
        return;
#endif
#ifdef CLOTH_PREPASS
    float visibility = 1;
#else
    float visibility = punctualVisibility(_AdditionalLightsShadowmapTexture, shadowCompare1, index,
                                         positionWS, light.direction, fade, false);
#endif
    float3 incident = (light.attenuation * visibility) * light.color;
#ifdef CLOTH_NPR
    accumulateBand(lights, light.attenuation * light.color, light.direction, normalWS, visibility);
#else
    DiffuseLobes diffuse = DiffuseLobes(normalWS, light.direction);
    lights.diffuse = mad(incident, diffuse.cosine, lights.diffuse);
    lights.wrapped = mad(incident, diffuse.wrapped, lights.wrapped);
    lights.unshaded = mad(light.color, light.attenuation, lights.unshaded);
#endif
}

public ClothLights gatherClothLights(float3 positionWS, float3 normalWS, float2 screenUV)
{
    ForwardPlusGrid grid = ForwardPlusGrid(_FPParams0, _FPParams1, _FPParams2.x);
    float3 fromCamera = positionWS - _WorldSpaceCameraPos.xyz;
    float viewDepth = dot(-float3(viewX.z, viewY.z, viewZ.z), fromCamera);
    ClusterLights cluster = grid.localLights(screenUV, viewDepth, unity_OrthoParams.w == 0);
    ClothLights lights = {};
#ifdef CLOTH_PREPASS
    float fade = 0;
#else
    float fade = saturate(mad(dot(fromCamera, fromCamera), additionalShadowFadeParams.x, additionalShadowFadeParams.y));
#endif
#ifdef CLOTH_NPR
    lights.bandDirection = float3(0, 0.0001, 0);
    [loop] for (uint i = 0; i < min(mapDirectionalCount, 32u); ++i)
        accumulateBand(lights, mapDirectionals[i].color.rgb, mapDirectionals[i].direction.xyz, normalWS, 1);
#else
    [loop] for (uint i = 0; i < grid.directionalCount; ++i)
        addClothLight(lights, i, positionWS, normalWS, fade);
#endif
    uint index;
    [loop] while (cluster.next(index))
        addClothLight(lights, index, positionWS, normalWS, fade);
#ifdef CLOTH_NPR
    lights.bandColor /= bandCompression(lights.bandColor);
    lights.band = bandWeight(lights.bandColor);
    lights.bandColor = max(lights.bandColor, 0.015);
    lights.bandDirection = dot(lights.bandDirection, lights.bandDirection) < 1e-12
        ? float3(0, 1, 0) : normalize(lights.bandDirection);
#endif
    return lights;
}
