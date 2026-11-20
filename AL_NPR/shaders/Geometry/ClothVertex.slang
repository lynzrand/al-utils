import Geometry.VertexTransforms;
import Geometry.DentedMesh;

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

public struct ClothVertexInput
{
    public float4 positionOS : POSITION0;
    public float3 normalOS : NORMAL0;
    public float4 tangentOS : TANGENT0;
    public float4 color : COLOR0;
    public float4 uv1 : TEXCOORD1;
    public float4 uv2 : TEXCOORD2;
    public float4 uv0 : TEXCOORD0;
};

public struct ClothVertexOutput
{
    public float4 positionCS : SV_POSITION;
    public float4 positionWS : TEXCOORD0;
    public float3 normalWS : TEXCOORD1;
    public float4 tangentWS : TEXCOORD2;
    public float4 unused4 : TEXCOORD3;
    public float4 unused5 : TEXCOORD4;
    public float4 uv0Uv1 : TEXCOORD5;
    public float4 uv2Padded : TEXCOORD6;
    public float4 positionOS : TEXCOORD7;
    public float4 mainLightOS : TEXCOORD8;
    public float3 normalOS : NORMAL0;
};

public ClothVertexOutput clothVertex(ClothVertexInput input, float dentPower)
{
    float3 dent = meshDent(input.uv1.xy, input.color.rgb, dentPower);
    float3 positionWS = objectToWorld.point(input.positionOS.xyz + dent);

    ClothVertexOutput output;
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
