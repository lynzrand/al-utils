import Geometry.VertexTransforms;

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

cbuffer UnityPerMaterial : register(b2)
{
    float _Line_width : packoffset(c19.z);
    float _Bust_size : packoffset(c23.w);
    float _Dent_power : packoffset(c24.x);
    float _VertexColorNormal : packoffset(c24.y);
};

SamplerState detailSampler : register(s0);
SamplerState overlaySampler : register(s1);
SamplerState sampler_Create_dent_texture : register(s2);
Texture2D<float4> _Create_dent_texture : register(t0);
Texture2DArray<float4> _Detail_mask_01 : register(t1);
Texture2DArray<float4> _TexEX : register(t2);

struct StageInput
{
    float4 positionOS : POSITION0;
    float3 normalOS : NORMAL0;
    float4 tangentOS : TANGENT0;
    float4 uv0 : TEXCOORD0;
    float4 color : COLOR0;
    float4 uv1 : TEXCOORD1;
    float4 uv2 : TEXCOORD2;
    float4 uv3 : TEXCOORD3;
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
    float4 uv2Uv3 : TEXCOORD6;
    float4 positionOS : TEXCOORD7;
    float4 mainLightOS : TEXCOORD8;
    float3 normalOS : NORMAL0;
};

[shader("vertex")]
StageOutput main(StageInput input)
{
    float height = _Create_dent_texture.SampleLevel(sampler_Create_dent_texture, input.uv1.xy, 0).r * _Dent_power;
    float3 dent = mad(input.color.rgb, height * -0.4, height * 0.2);
    float bustMask = _TexEX.SampleLevel(overlaySampler, float3(input.uv0.xy, 2), 0).a;
    float bust = saturate((_Bust_size - 0.5) * 2.5);
    float taper = min(1, 1 - mad(bust, saturate((bustMask - 1) * -5.263158), -0.5));
    float edge = 1 - _Detail_mask_01.SampleLevel(detailSampler, float3(input.uv0.xy, 0), 0).r;
    float width = (edge * (taper * (edge * _Line_width))) * 0.2;
    float clipW = viewProjection.clipPosition(objectToWorld.point(input.positionOS.xyz)).w;
    float3 outline = outlinePosition(input.positionOS.xyz, input.normalOS, input.color.rgb, dent,
                                     width, _VertexColorNormal, clipW);
    float3 positionWS = objectToWorld.point(outline);

    StageOutput output;
    output.positionCS = viewProjection.clipPosition(positionWS);
    output.positionWS = float4(positionWS, 0);
    output.normalWS = surfaceNormal(input.normalOS, worldToObject);
    output.tangentWS = surfaceTangent(input.tangentOS, objectToWorld, worldSign);
    output.unused4 = 0;
    output.unused5 = 0;
    output.uv0Uv1 = float4(input.uv0.xy, input.uv1.xy);
    output.uv2Uv3 = float4(input.uv2.xy, input.uv3.xy);
    output.positionOS = input.positionOS;
    output.mainLightOS = float4(mad(worldToObject.origin.xyz, mainLight.w, worldToObject.direction(mainLight.xyz)), 0);
    output.normalOS = input.normalOS;
    return output;
}
