import VertexTransforms;

cbuffer Globals : register(b0)
{
    TransformColumns viewProjection : packoffset(c78);
};

cbuffer UnityPerDraw : register(b1)
{
    TransformColumns objectToWorld : packoffset(c0);
    TransformColumns worldToObject : packoffset(c4);
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
    float3 normalWS : TEXCOORD0;
};

[shader("vertex")]
StageOutput main(StageInput input)
{
    float3 positionWS = objectToWorld.point(input.positionOS.xyz);

    StageOutput output;
    output.positionCS = viewProjection.clipPosition(positionWS);
    output.normalWS = surfaceNormal(input.normalOS, worldToObject);
    return output;
}
