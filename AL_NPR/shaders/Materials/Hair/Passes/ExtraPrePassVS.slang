import Geometry.VertexTransforms;

/// Camera and main-light inputs consumed by the hair vertex stage.
cbuffer Globals : register(b0)
{
    /// XYZ stores the main light world vector. W controls the transform's translation term when expressing it
    /// in object space.
    float4 mainLight : packoffset(c5);
    /// World-to-clip transform for this camera.
    TransformColumns viewProjection : packoffset(c82);
};

/// Object transforms and handedness for this draw.
cbuffer UnityPerDraw : register(b1)
{
    /// Mesh-to-world transform for the vertex position and tangent.
    TransformColumns objectToWorld : packoffset(c0);
    /// Inverse transform for the surface normal and object-space light vector.
    TransformColumns worldToObject : packoffset(c4);
    /// World-transform handedness multiplier for the tangent sign.
    float worldSign : packoffset(c9.w);
};

/// Mesh attributes from the game's hair extra prepass vertex signature.
struct StageInput
{
    /// Mesh vertex position. XYZ is transformed to world space and the original XYZW is forwarded for region
    /// masks.
    float4 positionOS : POSITION0;
    /// Mesh normal in object space, also forwarded unchanged for the rim.
    float3 normalOS : NORMAL0;
    /// Mesh tangent in XYZ and its handedness sign in W.
    float4 tangentOS : TANGENT0;
    /// Mesh UV1. XY is packed into the first two lanes of TEXCOORD5.
    float4 uv1 : TEXCOORD1;
    /// Mesh UV2 declared by the stock vertex signature and unused by this stage.
    float4 uv2 : TEXCOORD2;
    /// Mesh UV0. XY is packed into the last two lanes of TEXCOORD5.
    float4 uv0 : TEXCOORD0;
};

/// Raster position and interpolants expected by the extra prepass color stage.
struct StageOutput
{
    /// Homogeneous clip position used by the rasterizer.
    float4 positionCS : SV_POSITION;
    /// XYZ world position for lighting. W is written as zero.
    float4 positionWS : TEXCOORD0;
    /// World-space normal transformed with the inverse object matrix.
    float3 normalWS : TEXCOORD1;
    /// World-space tangent in XYZ and handedness corrected for the object's transform in W.
    float4 tangentWS : TEXCOORD2;
    /// TEXCOORD3 is reserved and filled with zero.
    float4 unused4 : TEXCOORD3;
    /// TEXCOORD4 is reserved and filled with zero.
    float4 unused5 : TEXCOORD4;
    /// XY carries UV1 for strand normals and painted stripes. ZW carries UV0 for detail and wetness.
    float4 uv1Uv0 : TEXCOORD5;
    /// XYZ main light vector transformed into object space. W is written as zero.
    float4 mainLightOS : TEXCOORD6;
    /// Mesh normal in object space, also forwarded unchanged for the rim.
    float3 normalOS : NORMAL0;
    /// Original mesh position. The fragment stage uses object-space Y and Z for wetness regions.
    float4 positionOS : TEXCOORD7;
};

/// Transform the hair mesh and pack the interpolants consumed by the color pass.
[shader("vertex")]
StageOutput main(StageInput input)
{
    float3 positionWS = objectToWorld.point(input.positionOS.xyz);

    StageOutput output;
    output.positionCS = viewProjection.clipPosition(positionWS);
    output.positionWS = float4(positionWS, 0);
    output.normalWS = surfaceNormal(input.normalOS, worldToObject);
    output.tangentWS = surfaceTangent(input.tangentOS, objectToWorld, worldSign);
    output.unused4 = 0;
    output.unused5 = 0;
    output.uv1Uv0 = float4(input.uv1.xy, input.uv0.xy);
    output.mainLightOS = float4(mad(worldToObject.origin.xyz, mainLight.w, worldToObject.direction(mainLight.xyz)), 0);
    output.normalOS = input.normalOS;
    output.positionOS = input.positionOS;
    return output;
}
