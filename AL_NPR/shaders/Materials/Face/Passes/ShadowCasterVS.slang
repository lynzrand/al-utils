import Geometry.VertexTransforms;

cbuffer Globals : register(b0)
{
    TransformColumns viewProjection : packoffset(c78);
    float2 shadowBias : packoffset(c129);
    float3 shadowLightDirection : packoffset(c130);
};

cbuffer UnityPerDraw : register(b1)
{
    TransformColumns objectToWorld : packoffset(c0);
};

struct StageInput
{
    float4 positionOS : POSITION0;
    float3 normalOS : NORMAL0;
    float4 tangentOS : TANGENT0;
};

struct StageOutput
{
    float4 positionCS : SV_POSITION;
};

[shader("vertex")]
StageOutput main(StageInput input)
{
    float3 positionWS = objectToWorld.point(input.positionOS.xyz);
    positionWS = shadowCasterPosition(positionWS, input.normalOS, objectToWorld, shadowLightDirection, shadowBias);

    StageOutput output;
    output.positionCS = viewProjection.clipPosition(positionWS);
    output.positionCS.z = min(output.positionCS.z, 1);
    return output;
}
