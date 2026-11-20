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
    float4 color : COLOR0;
    float4 uv1 : TEXCOORD1;
    float4 uv0 : TEXCOORD0;
    float4 uv2 : TEXCOORD2;
};

struct StageOutput
{
    float4 positionCS : SV_POSITION;
    float3 normalWS : TEXCOORD0;
    float4 uv0Uv2 : TEXCOORD1;
};

[shader("vertex")]
StageOutput main(StageInput input)
{
    float height = _Create_dent_texture.SampleLevel(sampler_Create_dent_texture, input.uv1.xy, 0).r * _Dent_power;
    float3 dent = mad(input.color.rgb, height * -0.14, height * 0.07);
    float3 positionWS = objectToWorld.point(input.positionOS.xyz + dent);

    StageOutput output;
    output.positionCS = viewProjection.clipPosition(positionWS);
    output.normalWS = surfaceNormal(input.normalOS, worldToObject);
    output.uv0Uv2 = float4(input.uv0.xy, input.uv2.xy);
    return output;
}
