import VertexTransforms;

cbuffer Globals : register(b0)
{
    float4 mainLight : packoffset(c5);
    TransformColumns viewProjection : packoffset(c82);
};

cbuffer UnityPerDraw : register(b1)
{
    TransformColumns objectToWorld : packoffset(c0);
    TransformColumns worldToObject : packoffset(c4);
    float worldSign : packoffset(c9.w);
};

struct StageInput
{
    float4 positionOS : POSITION0;
    float3 normalOS : NORMAL0;
    float4 tangentOS : TANGENT0;
    float4 color : COLOR0;
    float4 uv1 : TEXCOORD1;
    float4 uv2 : TEXCOORD2;
    float4 uv0 : TEXCOORD0;
};

struct StageOutput
{
    float4 positionCS : SV_POSITION;
    float4 positionWS : TEXCOORD0;
    float3 normalWS : TEXCOORD1;
    float4 tangentWS : TEXCOORD2;
    float4 unused4 : TEXCOORD3;
    float4 unused5 : TEXCOORD4;
    float4 uv0Uv1 : TEXCOORD5;
    float4 uv2Padded : TEXCOORD6;
    float4 positionOS : TEXCOORD7;
    float4 mainLightOS : TEXCOORD8;
    float3 normalOS : NORMAL0;
};

[shader("vertex")]
StageOutput main(StageInput input)
{
    float height = _Create_dent_texture.SampleLevel(sampler_Create_dent_texture, input.uv1.xy, 0).r * _Dent_power;
    float3 dent = mad(input.color.rgb, height * -0.14, height * 0.07);
    float3 positionWS = objectToWorld.point(input.positionOS.xyz + dent);

    StageOutput output;
    output.positionCS = viewProjection.clipPosition(positionWS);
    output.positionWS = float4(positionWS, 0);
    output.normalWS = surfaceNormal(input.normalOS, worldToObject);
    output.tangentWS = surfaceTangent(input.tangentOS, objectToWorld, worldSign);
    output.unused4 = 0;
    output.unused5 = 0;
    output.uv0Uv1 = float4(input.uv0.xy, input.uv1.xy);
    output.uv2Padded = float4(input.uv2.xy, 0, 0);
    output.positionOS = input.positionOS;
    output.mainLightOS = float4(mad(worldToObject.origin.xyz, mainLight.w, worldToObject.direction(mainLight.xyz)), 0);
    output.normalOS = input.normalOS;
    return output;
}
