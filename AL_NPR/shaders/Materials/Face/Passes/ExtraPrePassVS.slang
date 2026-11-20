import Geometry.VertexTransforms;

cbuffer Globals : register(b0)
{
    TransformColumns viewProjection : packoffset(c78);
};

cbuffer UnityPerDraw : register(b1)
{
    TransformColumns objectToWorld : packoffset(c0);
    TransformColumns worldToObject : packoffset(c4);
    float worldSign : packoffset(c9.w);
};

cbuffer UnityPerMaterial : register(b2)
{
    float4 _Detail_mask_01_ST : packoffset(c21);
    float _LineWidthMax : packoffset(c29.y);
    float _DistanceCutoff : packoffset(c29.z);
    float _Line_width : packoffset(c34.w);
};

SamplerState sampler_Detail_mask_01 : register(s0);
Texture2D<float4> _Detail_mask_01 : register(t0);

struct StageInput
{
    float4 positionOS : POSITION0;
    float3 normalOS : NORMAL0;
    float4 tangentOS : TANGENT0;
    float4 uv0 : TEXCOORD0;
    float4 uv1 : TEXCOORD1;
    float4 uv3 : TEXCOORD3;
    float4 uv2 : TEXCOORD2;
};

struct StageOutput
{
    float4 positionCS : SV_POSITION;
    float4 positionWS : TEXCOORD0;
    float3 normalWS : TEXCOORD1;
    float4 tangentWS : TEXCOORD2;
    float4 uv0Uv1 : TEXCOORD3;
    float4 uv3Uv2 : TEXCOORD4;
    float4 unused6 : TEXCOORD5;
    float4 unused7 : TEXCOORD6;
};

[shader("vertex")]
StageOutput main(StageInput input)
{
    float2 maskUV = mad(input.uv0.xy, _Detail_mask_01_ST.xy, _Detail_mask_01_ST.zw);
    float mask = _Detail_mask_01.SampleLevel(sampler_Detail_mask_01, maskUV, 0).r;
    float width = max(0, min(saturate(mad(mask, -1.2, 1)), (1 - mask) * _Line_width * 0.05));
    width = min(width, mad(mask, _LineWidthMax - 1, 1) * 0.05);
    float clipW = viewProjection.clipPosition(objectToWorld.point(input.positionOS.xyz)).w;
    float3 outline = mad(width * input.normalOS, min(clipW, _DistanceCutoff), input.positionOS.xyz);
    float3 positionWS = objectToWorld.point(outline);

    StageOutput output;
    output.positionCS = viewProjection.clipPosition(positionWS);
    output.positionWS = float4(positionWS, 0);
    output.normalWS = surfaceNormal(input.normalOS, worldToObject);
    output.tangentWS = surfaceTangent(input.tangentOS, objectToWorld, worldSign);
    output.uv0Uv1 = float4(input.uv0.xy, input.uv1.xy);
    output.uv3Uv2 = float4(input.uv3.xy, input.uv2.xy);
    output.unused6 = 0;
    output.unused7 = 0;
    return output;
}
