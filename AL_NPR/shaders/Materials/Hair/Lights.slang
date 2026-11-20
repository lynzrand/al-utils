import Materials.Hair.LightResponse;
import Materials.Hair.Surface;
import Materials.Hair.Bindings;
import Lighting.Reflectance;
import Lighting.ForwardPlus;
import Lighting.PunctualLighting;
#ifndef HAIR_STOCK_BASE
import Lighting.PunctualShadows;
#endif
public float hairKeyVisibility(float3 positionWS)
{
#ifdef HAIR_STOCK_BASE
    return 1;
#else
    float3 uvz = mainShadowCoord(positionWS);
    float shadow = mainShadowAtlas.SampleCmpLevelZero(shadowCompare, uvz.xy, uvz.z);
    return uvz.z > 0 && uvz.z < 1 ? mad(shadow, mainShadowParams.x, 1 - mainShadowParams.x) : 1;
#endif
}

public struct HairLights
{
    public float3 diffuse, wrapped, reflected;
};

struct HairLightInput
{
    float3 position, normal;
#ifndef HAIR_STOCK_BASE
    float shadowFade;
#endif
};

void accumulateHairLight<R : IHairLightResponse>(inout HairLights sum, R response, HairLightInput s,
                                                 uint index, bool clustered)
{
    PunctualLight light = getPunctualLight(index, s.position);
    float visibility = 1;
#ifndef HAIR_STOCK_BASE
    if ((asuint(lightLayerMasks[index].x) & response.lightLayers) == 0 || light.attenuation == 0)
        return;
    visibility = punctualVisibility(additionalShadowAtlas, shadowCompare, index, s.position,
                                    light.direction, s.shadowFade, false);
#endif
    float3 arriving = response.punctualRadiance(light, visibility, clustered, sum.reflected);
    DiffuseLobes diffuse = DiffuseLobes(s.normal, light.direction);
    sum.diffuse += diffuse.cosine * arriving;
    sum.wrapped += diffuse.wrapped * arriving;
}

public HairLights gatherHairLights<R : IHairLightResponse>(R response, HairSurface surface, HairInput input)
{
    ForwardPlusGrid grid = ForwardPlusGrid(fp0, fp1, fp2.x);
    HairLights sum = {};
    HairLightInput s;
    s.position = input.positionWS.xyz;
    s.normal = surface.shadingNormal;
#ifndef HAIR_STOCK_BASE
    s.shadowFade = saturate(mad(dot(surface.toCamera, surface.toCamera), additionalShadowFadeParams.x,
                                 additionalShadowFadeParams.y));
#endif
    sum.reflected = response.mapReflections();
    [loop] for (uint i = 0; i < grid.directionalCount; ++i)
        accumulateHairLight(sum, response, s, i, false);

    float2 screenUV = input.positionCS.xy / screenSize;
    screenUV.y = 1 - mad(screenUV.y, screenScaleBias.x, screenScaleBias.y);
    float viewDepth = dot(float3(viewX.z, viewY.z, viewZ.z), surface.toCamera);
    ClusterLights cluster = grid.localLights(screenUV, viewDepth, orthographic == 0);
    uint index;
    [loop] while (cluster.next(index))
        accumulateHairLight(sum, response, s, index, true);
    return sum;
}
