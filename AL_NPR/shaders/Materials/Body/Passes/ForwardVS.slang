import Materials.Body.DentMaterial;
import Geometry.DentedMesh;
import Geometry.VertexTransforms;

/// Per-camera constants at the offsets used by this shader stage.
cbuffer Globals : register(b0)
{
    /// World-space main-light vector. W weights translation when transforming the vector into object space.
    float4 mainLight : packoffset(c5);
    /// Four columns of the current world-to-clip transform, applied to the world-space vertex position.
    TransformColumns viewProjection : packoffset(c82);
};

/// Per-renderer transforms and lighting data for this stage.
cbuffer UnityPerDraw : register(b1)
{
    /// Four columns of the current object-to-world transform, including translation in the last column.
    TransformColumns objectToWorld : packoffset(c0);
    /// Inverse object transform. Its linear part supplies the inverse-transpose normal and the object-space
    /// light.
    TransformColumns worldToObject : packoffset(c4);
    /// Sign of the object transform, multiplied by tangent W when reconstructing handedness.
    float worldSign : packoffset(c9.w);
};

/// Mesh attributes in the vertex register order used by this pass.
struct StageInput
{
    /// Object-space mesh position. XYZ enters the object-to-world transform.
    float4 positionOS : POSITION0;
    /// Mesh normal in object space, before deformation and interpolation.
    float3 normalOS : NORMAL0;
    /// Object-space mesh tangent in XYZ. W gives the sign used to reconstruct the bitangent.
    float4 tangentOS : TANGENT0;
    /// Mesh vertex color. RGB encodes the object-space dent direction and can steer outline extrusion.
    float4 color : COLOR0;
    /// Mesh UV1 in XY for the painted dent height.
    float4 uv1 : TEXCOORD1;
    /// Primary material UV in XY for pigment, detail and wetness.
    float4 uv0 : TEXCOORD0;
    /// Mesh UV2 in XY for nipple placement and optional clothing cutout sampling.
    float4 uv2 : TEXCOORD2;
    /// Mesh UV3 in XY for under-hair pigment.
    float4 uv3 : TEXCOORD3;
};

/// Clip position and varyings in the register order expected by the original fragment stage.
struct StageOutput
{
    /// Homogeneous clip-space position for rasterization.
    float4 positionCS : SV_POSITION;
    /// Interpolated vertex position in world units in XYZ. The vertex shader sets W to zero.
    float4 positionWS : TEXCOORD0;
    /// World-space mesh normal for lighting. Interpolation can change its length.
    float3 normalWS : TEXCOORD1;
    /// World-space tangent direction in XYZ and signed bitangent handedness in W.
    float4 tangentWS : TEXCOORD2;
    /// XY carry mesh UV0 for pigment and detail. ZW carry UV1 for the dent mask.
    float4 uv0Uv1 : TEXCOORD3;
    /// Zero-filled interpolator retained at this register in the shipped stage signature.
    float4 unused5 : TEXCOORD4;
    /// Zero-filled interpolator retained at this register in the shipped stage signature.
    float4 unused6 : TEXCOORD5;
    /// XY carry UV2 for nipple placement or clothing cutouts. ZW carry UV3 for under-hair pigment.
    float4 uv2Uv3 : TEXCOORD6;
    /// Original object-space mesh position. XY anchor wet-skin grain to the surface.
    float4 positionOS : TEXCOORD7;
    /// Main-light vector in object space in XYZ, with W set to zero. The rim uses its vertical component.
    float4 mainLightOS : TEXCOORD8;
    /// Original mesh normal in object space, interpolated for the vertical rim falloff.
    float3 normalOS : NORMAL0;
};

/// Applies the vertex-color dent and projects the body vertex, forwarding the geometric basis, object-space
/// light, position and painted UV sets.
[shader("vertex")]
StageOutput main(StageInput input)
{
    float3 dent = meshDent(input.uv1.xy, input.color.rgb, _Dent_power);
    float3 positionWS = objectToWorld.point(input.positionOS.xyz + dent);

    StageOutput output;
    output.positionCS = viewProjection.clipPosition(positionWS);
    output.positionWS = float4(positionWS, 0);
    output.normalWS = surfaceNormal(input.normalOS, worldToObject);
    output.tangentWS = surfaceTangent(input.tangentOS, objectToWorld, worldSign);
    output.uv0Uv1 = float4(input.uv0.xy, input.uv1.xy);
    output.unused5 = 0;
    output.unused6 = 0;
    output.uv2Uv3 = float4(input.uv2.xy, input.uv3.xy);
    output.positionOS = input.positionOS;
    output.mainLightOS = float4(mad(worldToObject.origin.xyz, mainLight.w, worldToObject.direction(mainLight.xyz)), 0);
    output.normalOS = input.normalOS;
    return output;
}
