import Materials.Cloth.Bindings;
import Materials.Cloth.LightGather;
import Surface.MaterialColor;
import Surface.SurfaceNormals;
import Lighting.ToonPalette;
#ifndef CLOTH_PREPASS
import Lighting.PunctualShadows;
#endif

/// Samples the environment at the requested mip and decodes the probe into linear RGB.
public float3 sampleReflection(float3 direction, float lod)
{
    float4 encoded = unity_SpecCube0.SampleLevel(samplerunity_SpecCube0, direction, lod);
    return decodeProbe(encoded, specCubeDecode);
}

/// Transforms a world-space direction to view space using the rotational matrix columns.
public float3 viewAxes(float3 world)
{
    return mad(viewZ.xyz, world.z, mad(viewX.xyz, world.x, viewY.xyz * world.y));
}

/// Reconstructed surface frame, view direction, and the mapped world normal.
public struct ClothFrame
{
    /// World-space position of this fragment on the displaced mesh.
    public float3 positionWS;
    /// Unit world-space normal after the garment, wet, and fluid layers.
    public float3 normal;
    /// Mapped world normal before normalization, retained for the stock highlight response.
    public float3 normalBeforeNormalize;
    /// World-space tangent frame reconstructed from the interpolated mesh normal and tangent.
    public TangentFrame basis;
    /// World-space vector from the fragment to the camera, including distance.
    public float3 cameraDelta;
    /// World-space direction toward the camera, constant across an orthographic view.
    public float3 view;
};

/// Builds the displaced surface's tangent frame, world normal, and projection-dependent view direction.
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

/// Key lighting inputs for pigment shading, the lamp palette, and rim highlights.
public struct ClothKey
{
    /// Stock main-light RGB or the accumulated NPR band color.
    public float3 color;
    /// Unit world-space direction of the stock key or the weighted NPR band light.
    public float3 direction;
    /// Unit half-vector between the key-light direction and the view direction.
    public float3 viewHalf;
    /// Key color normalized by its peak channel and scaled by shadow visibility.
    public float3 litColor;
    /// Palette diffuse, ramp, and rim directions derived from the view and face-signed key.
    public PaletteDirections directions;
    /// Key-light exposure and presence used when assembling the cloth palette.
    public PaletteLight palette;
    /// Main shadow visibility in stock forward shading. NPR and outline use one here.
    public float visibility;
    /// Visibility remapped by key-light presence for the painted shadow response.
    public float shade;
    /// X gives the narrow and Y the broader stock facing band. NPR copies the gathered band weight into both lanes.
    public float2 bands;
    /// Clamped sum of probe irradiance and the key-light band on the mapped normal.
    public float3 ambient;
};

/// Resolves the stock main light or NPR band into palette directions, facing weights, and visibility.
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
