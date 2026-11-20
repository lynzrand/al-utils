// Shared by the face and body color passes. Stock evaluates Unity's directional
// prefix and local cluster. NPR substitutes the scene's authored directionals.
import Materials.Skin.Frame;
#if SKIN_FACE
import Materials.Face.Bindings;
#else
import Materials.Body.Bindings;
#endif
import Lighting.PunctualLighting;
import Materials.Skin.LightResponse;
import Lighting.ForwardPlus;
#if !SKIN_PREPASS
import Lighting.PunctualShadows;
#endif
#if SKIN_NPR
import Lighting.MapLighting;
public typealias SkinLights = ToonSkinResponse<SKIN_FACE != 0>;
#else
public typealias SkinLights = StockSkinResponse<SKIN_PREPASS != 0>;
#endif

void accumulatePunctualSkin<T : ISkinLightResponse>(
    inout T sum, uint index, float3 positionWS, float3 normal, float3 bandNormal, float shadowFade)
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
#else
    float visibility = punctualVisibility(_AdditionalLightsShadowmapTexture, shadowCompare1,
        index, positionWS, light.direction, shadowFade, (SKIN_FACE != 0) && (SKIN_NPR != 0));
#endif
    sum.addPunctual(light, visibility, normal, bandNormal);
}

public SkinLights evaluateSkinLights(StageInput input, float3 normal, float3 bandNormal)
{
    ForwardPlusGrid grid = ForwardPlusGrid(_FPParams0, _FPParams1, _FPParams2.x);
    SkinLights sum = SkinLights();
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
        sum.addDirectional(direction, light.color.rgb, bandNormal);
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
    sum.finishAccumulation();
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
