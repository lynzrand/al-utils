import Materials.Cloth.Bindings;
import Materials.Cloth.LightGather;
import Surface.MaterialColor;
import Surface.SurfaceNormals;
import Lighting.ToonPalette;
#ifndef CLOTH_PREPASS
import Lighting.PunctualShadows;
#endif

public float3 sampleReflection(float3 direction, float lod)
{
    float4 encoded = unity_SpecCube0.SampleLevel(samplerunity_SpecCube0, direction, lod);
    return decodeProbe(encoded, specCubeDecode);
}

public float3 viewAxes(float3 world)
{
    return mad(viewZ.xyz, world.z, mad(viewX.xyz, world.x, viewY.xyz * world.y));
}

public struct ClothFrame
{
    public float3 positionWS;
    public float3 normal;
    public float3 normalBeforeNormalize;
    public TangentFrame basis;
    public float3 cameraDelta, view;
};

public ClothFrame clothFrame(ClothInput input, float3 mappedNormal)
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

public struct ClothKey
{
    public float3 color, direction, viewHalf, litColor;
    public PaletteDirections directions;
    public PaletteLight palette;
    public float visibility, shade;
    public float2 bands;
    public float3 ambient;
};

public ClothKey clothKey(ClothFrame frame, ClothLights lights, bool frontFace)
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
    key.palette = PaletteLight(key.color);
    key.shade = lerp(0.7, smoothstep(0.3, 0.7, key.visibility), key.palette.presence);
    key.litColor = key.visibility * (key.color / (peakChannel(key.color) + 1e-7));
    key.direction = sourceDirection * rsqrt(max(dot(sourceDirection, sourceDirection), 1.1754944e-38));
    float3 signedDirection = normalize(key.direction) * (frontFace ? 1 : -1);
    key.directions = PaletteDirections(key.color, frame.view, signedDirection);
    key.viewHalf = normalize(normalize(sourceDirection) + frame.view);
#ifdef CLOTH_NPR
    key.bands = lights.band;
#else
    float facing = dot(frame.normal, key.directions.diffuse);
    key.bands = saturate((facing + float2(-0.05, 0.2)) * float2(5, 2.5));
#endif
    key.ambient = saturate(probe.evaluate(frame.normal) + saturate(mad(key.shade * key.bands.x * key.color, 0.9, 0.1)));
    return key;
}
