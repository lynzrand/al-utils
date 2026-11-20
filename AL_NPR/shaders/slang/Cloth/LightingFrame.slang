import SurfaceNormals;
import MaterialColor;

float3 sampleReflection(float3 direction, float lod)
{
    float4 encoded = unity_SpecCube0.SampleLevel(samplerunity_SpecCube0, direction, lod);
    return decodeProbe(encoded, specCubeDecode);
}

float3 viewAxes(float3 world)
{
    return mad(viewZ.xyz, world.z, mad(viewX.xyz, world.x, viewY.xyz * world.y));
}

struct ClothFrame
{
    float3 positionWS;
    float3 normal;
    float3 normalBeforeNormalize;
    TangentFrame basis;
    float3 cameraDelta, view;

};

ClothFrame clothFrame(ClothInput input, float3 mappedNormal)
{
    ClothFrame frame;
    frame.positionWS = input.positionWS.xyz;
    frame.cameraDelta = _WorldSpaceCameraPos.xyz - frame.positionWS;
    frame.view = unity_OrthoParams.w == 0 ? normalize(frame.cameraDelta) : float3(viewX.z, viewY.z, viewZ.z);
    frame.basis = TangentFrame(input.normalWS, input.tangentWS);
    frame.normalBeforeNormalize = frame.basis.toWorld(mappedNormal);
    frame.normal = normalize(frame.normalBeforeNormalize);
    return frame;
}

struct ClothKey
{
    float3 color, direction, viewHalf, litColor;
    float3 facingDirection, facingDelta;
    float visibility, shade, strength, luma, hdrFade;
    float2 bands;
    float3 ambient;
};

ClothKey clothKey(ClothFrame frame, ClothLights lights, bool frontFace)
{
    ClothKey key;
#ifdef CLOTH_NPR
    key.color = lights.bandColor;
    float3 sourceDirection = lights.bandDirection;
#else
    key.color = _MainLightColor.rgb;
    float3 sourceDirection = _MainLightPosition.xyz;
#endif
#if defined(CLOTH_NPR) || defined(CLOTH_PREPASS)
    key.visibility = 1;
#else
    float3 uvz = mainShadowCoord(frame.positionWS);
    float shadow = _MainLightShadowmapTexture.SampleCmpLevelZero(shadowCompare1, uvz.xy, uvz.z);
    key.visibility = uvz.z <= 0 || uvz.z >= 1 ? 1 : mad(shadow, mainShadowParams.x, 1 - mainShadowParams.x);
#endif
    key.strength = saturate(dot(key.color, 1));
    key.shade = lerp(0.7, smoothstep(0.3, 0.7, key.visibility), key.strength);
    key.litColor = key.visibility * (key.color / (peakChannel(key.color) + 1e-7));
    key.direction = sourceDirection * rsqrt(max(dot(sourceDirection, sourceDirection), 1.1754944e-38));
    float3 signedDirection = normalize(key.direction) * (frontFace ? 1 : -1);
    key.facingDelta = signedDirection - frame.view;
    key.luma = dot(key.color, luminance709);
    key.hdrFade = saturate(mad(max(log2(key.luma), saturate(key.luma)) - 1, -0.1, 1));
    float mainWeight = key.hdrFade * saturate(2 * key.luma);
    key.facingDirection = mad(mainWeight, key.facingDelta, frame.view);
    key.viewHalf = normalize(normalize(sourceDirection) + frame.view);
#ifdef CLOTH_NPR
    key.bands = lights.band;
#else
    float facing = dot(frame.normal, key.facingDirection);
    key.bands = saturate((facing + float2(-0.05, 0.2)) * float2(5, 2.5));
#endif
    key.ambient = saturate(probe.evaluate(frame.normal) + saturate(mad(key.shade * key.bands.x * key.color, 0.9, 0.1)));
    return key;
}
