import Geometry.VertexTransforms;

/// Per-camera constants at the offsets used by this shader stage.
cbuffer Globals : register(b0)
{
    /// Four columns of the current world-to-clip transform, applied to the world-space vertex position.
    TransformColumns viewProjection : packoffset(c78);
};

/// Per-renderer transforms and lighting data for this stage.
cbuffer UnityPerDraw : register(b1)
{
    /// Four columns of the current object-to-world transform, including translation in the last column.
    TransformColumns objectToWorld : packoffset(c0);
};

/// Mesh attributes in the vertex register order used by this pass.
struct StageInput
{
    /// Object-space mesh position. XYZ enters the object-to-world transform.
    float4 positionOS : POSITION0;
    /// Object-space mesh normal retained in the depth-only input signature.
    float3 normalOS : NORMAL0;
    /// Mesh tangent and handedness retained in the original vertex input signature.
    float4 tangentOS : TANGENT0;
};

/// Clip position and varyings in the register order expected by the original fragment stage.
struct StageOutput
{
    /// Homogeneous clip-space position for rasterization.
    float4 positionCS : SV_POSITION;
};

/// Projects the original face vertex into camera clip space for depth-only rendering.
[shader("vertex")]
StageOutput main(StageInput input)
{
    float3 positionWS = objectToWorld.point(input.positionOS.xyz);

    StageOutput output;
    output.positionCS = viewProjection.clipPosition(positionWS);
    return output;
}
