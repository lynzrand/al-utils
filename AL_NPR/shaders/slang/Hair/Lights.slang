import ForwardPlus;
import PunctualLighting;
#ifndef HAIR_STOCK_BASE
import PunctualShadows;
#endif
#ifdef HAIR_NPR
import HairLighting;

import MapLighting;
#endif

float hairKeyVisibility(float3 positionWS)
{
#ifdef HAIR_STOCK_BASE
    return 1;
#else
    float3 uvz = mainShadowCoord(positionWS);
    float shadow = mainShadowAtlas.SampleCmpLevelZero(shadowCompare, uvz.xy, uvz.z);
    return uvz.z > 0 && uvz.z < 1 ? mad(shadow, mainShadowParams.x, 1 - mainShadowParams.x) : 1;
#endif
}

struct HairLights
{
    float3 diffuse, wrapped, reflected;
};

struct HairLightInput
{
    float3 position, normal;
#ifndef HAIR_STOCK_BASE
    float shadowFade;
#endif
#ifdef HAIR_NPR
    float3 strandNormal, strandTangent, view;
    float strandU;
    float2 strandGradient;

    float streak(float3 lightDirection)
    {
        // The release binds zero and ddx(UV) to the two explicit gradient operands.
        return paintedReflection(paintedHighlight, paintedHighlightSampler, strandNormal, strandTangent,
                                 lightDirection, view, strandU, 0, strandGradient);
    }
#endif
};

void accumulateHairLight(inout HairLights sum, HairLightInput s, uint index, bool clustered)
{
    PunctualLight light = getPunctualLight(index, s.position);
    float visibility = 1;
#ifndef HAIR_STOCK_BASE
#ifdef HAIR_NPR
    uint layer = 2u;
#else
    uint layer = asuint(renderingLayer.x);
#endif
    if ((asuint(lightLayerMasks[index].x) & layer) == 0 || light.attenuation == 0)
        return;
    visibility = punctualVisibility(additionalShadowAtlas, shadowCompare, index, s.position,
                                    light.direction, s.shadowFade, false);
#endif
    float3 arriving = (light.attenuation * visibility) * light.color;
#ifdef HAIR_NPR
    float3 incident = light.attenuation * light.color;
    if (clustered)
    {
        float peak = max(incident.r, max(incident.g, incident.b));
        float energy = (peak + dot(incident, float3(0.212673, 0.715152, 0.072175))) * 0.5;
        float excess = max(energy - 0.5, 0);
        float gain = (0.5 + excess / (1 + 2 * excess)) / (0.5 + excess);
        sum.reflected += (arriving * gain) * s.streak(light.direction);
    }
    arriving *= hairDiffuseGain(incident);
#endif
    float facing = dot(s.normal, light.direction);
    sum.diffuse += saturate(facing) * arriving;
    sum.wrapped += mad(facing, 0.5, 0.5) * arriving;
}

HairLights gatherHairLights(HairSurface surface, HairInput input)
{
    HairLights sum = {};
    HairLightInput s;
    s.position = input.positionWS.xyz;
    s.normal = surface.shadingNormal;
#ifndef HAIR_STOCK_BASE
    s.shadowFade = saturate(mad(dot(surface.toCamera, surface.toCamera), additionalShadowFadeParams.x,
                                 additionalShadowFadeParams.y));
#endif
#ifdef HAIR_NPR
    s.view = surface.view;
    s.strandNormal = input.normalWS * rsqrt(max(dot(input.normalWS, input.normalWS), 1e-8));
    float3 tangent = input.tangentWS.xyz - s.strandNormal * dot(input.tangentWS.xyz, s.strandNormal);
    s.strandTangent = tangent * rsqrt(max(dot(tangent, tangent), 1e-8));
    s.strandU = input.uv1Uv0.x;
    s.strandGradient = ddx(input.uv1Uv0.xy);
    [loop] for (uint i = 0; i < min(mapDirectionalCount, 32u); ++i)
    {
        float3 color = mapDirectionals[i].color.rgb;
        float peak = max(color.r, max(color.g, color.b));
        color /= 1 + 1.2 * max(peak - 0.5, 0);
        sum.reflected += color * s.streak(mapDirectionals[i].direction.xyz);
    }
#endif
    uint leading = uint(fp0.w);
    [loop] for (uint i = 0; i < min(leading, 256u); ++i)
        accumulateHairLight(sum, s, i, false);

    float2 screenUV = input.positionCS.xy / screenSize;
    screenUV.y = 1 - mad(screenUV.y, screenScaleBias.x, screenScaleBias.y);
    float viewDepth = dot(float3(viewX.z, viewY.z, viewZ.z), surface.toCamera);
    ClusterLights cluster = clusterForPixel(screenUV, viewDepth, orthographic == 0, fp0, fp1, fp2.x);
    uint local;
    [loop] while (cluster.next(local))
        accumulateHairLight(sum, s, leading + local, true);
    return sum;
}
