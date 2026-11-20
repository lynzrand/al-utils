import Lighting.AmbientProbe;

// The face outline prepass uses Unity's smaller global buffer layout.
#if SKIN_FACE && SKIN_PREPASS
/// Per-camera constants at the offsets used by this shader stage.
public cbuffer Globals : register(b0)
{
    /// XY are the scaled render-target width and height in pixels for dither and Forward+ lookup.
    public float4 _ScaledScreenParams : packoffset(c3);
    /// Nonzero enables derivative-based coverage clipping and coverage in output alpha.
    public float _AlphaToMaskAvailable : packoffset(c4.z);
    /// Unity's world-space main light vector. The skin fragment paths use XYZ as the direction toward the
    /// light.
    public float4 _MainLightPosition : packoffset(c5);
    /// Main light RGB radiance used by the stock palette and outline.
    public float4 _MainLightColor : packoffset(c6);
    /// Camera position in world units. Subtract the surface position to get the vector toward the eye.
    public float3 _WorldSpaceCameraPos : packoffset(c21);
    /// X is the projection Y-flip sign used to orient the screen-space dither pattern.
    public float4 _ProjectionParams : packoffset(c22);
    /// W selects the view direction and depth-bin mapping. Zero denotes a perspective camera.
    public float4 unity_OrthoParams : packoffset(c25);
    /// XY supply the Y scale and bias before converting screen coordinates to the render-target orientation.
    public float4 _ScaleBiasRt : packoffset(c27);
    /// X supplies the outline's fog blend weight, clamped to [0, 1].
    public float4 unity_FogParams : packoffset(c60);
    /// RGB fog tint blended over the face and body outline color.
    public float4 unity_FogColor : packoffset(c61);
    /// World-to-view column for the world X axis. Its Z lane contributes to the camera-back vector.
    public float4 unity_MatrixV0 : packoffset(c66);
    /// World-to-view column for the world Y axis. Its Z lane contributes to the camera-back vector.
    public float4 unity_MatrixV1 : packoffset(c67);
    /// World-to-view column for the world Z axis. Its Z lane contributes to the camera-back vector.
    public float4 unity_MatrixV2 : packoffset(c68);
};
#define SKIN_DRAW_SLOT b1
#else
/// Per-camera constants at the offsets used by this shader stage.
public cbuffer Globals : register(b0)
{
    /// XY are the scaled render-target width and height in pixels for dither and Forward+ lookup.
    public float4 _ScaledScreenParams : packoffset(c3);
    /// X is the mip-level bias for sampling body detail and overlay arrays.
    public float2 _GlobalMipBias : packoffset(c4);
    /// Nonzero enables derivative-based coverage clipping and coverage in output alpha.
    public float _AlphaToMaskAvailable : packoffset(c4.z);
    /// Unity's world-space main light vector. The skin fragment paths use XYZ as the direction toward the
    /// light.
    public float4 _MainLightPosition : packoffset(c5);
    /// Main light RGB radiance used by the stock palette and outline.
    public float4 _MainLightColor : packoffset(c6);
    /// XY scale and bias view depth into a Z bin. W counts leading directional lights and offsets local-light
    /// indices.
    public float4 _FPParams0 : packoffset(c15);
    /// XY convert screen UV to tile coordinates. Z gives tiles per row and W gives 32-bit mask words per
    /// tile.
    public float4 _FPParams1 : packoffset(c16);
    /// X is the number of Forward+ depth bins used to bound cluster lookup.
    public float4 _FPParams2 : packoffset(c17);
    /// X supplies time in seconds for droplet drift and the moving sweat cells.
    public float4 _TimeParameters : packoffset(c23);
    /// Camera position in world units. Subtract the surface position to get the vector toward the eye.
    public float3 _WorldSpaceCameraPos : packoffset(c25);
    /// X is the projection Y-flip sign used to orient the screen-space dither pattern.
    public float4 _ProjectionParams : packoffset(c26);
    /// W selects the view direction and depth-bin mapping. Zero denotes a perspective camera.
    public float4 unity_OrthoParams : packoffset(c29);
    /// XY supply the Y scale and bias before converting screen coordinates to the render-target orientation.
    public float4 _ScaleBiasRt : packoffset(c31);
    /// X supplies the outline's fog blend weight, clamped to [0, 1].
    public float4 unity_FogParams : packoffset(c64);
    /// RGB fog tint blended over the face and body outline color.
    public float4 unity_FogColor : packoffset(c65);
    /// World-to-view column for the world X axis. Its Z lane contributes to the camera-back vector.
    public float4 unity_MatrixV0 : packoffset(c70);
    /// World-to-view column for the world Y axis. Its Z lane contributes to the camera-back vector.
    public float4 unity_MatrixV1 : packoffset(c71);
    /// World-to-view column for the world Z axis. Its Z lane contributes to the camera-back vector.
    public float4 unity_MatrixV2 : packoffset(c72);
};
#define SKIN_DRAW_SLOT b4
#endif

/// Per-renderer transforms and lighting data for this stage.
public cbuffer UnityPerDraw : register(SKIN_DRAW_SLOT)
{
    /// Linear object-to-world column for the object X axis, used to transform shading directions.
    public float4 objectToWorld0 : packoffset(c0);
    /// Linear object-to-world column for the object Y axis, used to transform shading directions.
    public float4 objectToWorld1 : packoffset(c1);
    /// Linear object-to-world column for the object Z axis, used to transform shading directions.
    public float4 objectToWorld2 : packoffset(c2);
    /// Linear world-to-object column for the world X axis, used to shape normals in object space.
    public float4 worldToObject0 : packoffset(c4);
    /// Linear world-to-object column for the world Y axis, used to shape normals in object space.
    public float4 worldToObject1 : packoffset(c5);
    /// Linear world-to-object column for the world Z axis, used to shape normals in object space.
    public float4 worldToObject2 : packoffset(c6);
    /// X stores the renderer's layer bit mask as float bits. Stock tests it against each light with asuint.
    public float4 renderingLayer : packoffset(c10);
    /// Z scales the direct light added to the face outline.
    public float4 lightData : packoffset(c11);
    /// Probe decode parameters. X scales RGB, Y is the alpha exponent and W selects the encoded alpha
    /// contribution.
    public float4 specCubeHDR : packoffset(c15);
    /// Seven float4 registers of per-draw spherical harmonics for diffuse ambient and the NPR key.
    public SHCoefficients probe : packoffset(c25);
};
