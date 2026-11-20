import VertexTransforms;
import Geometry.DentedMesh;

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

public struct ShadowCasterOutput
{
    public float4 positionCS : SV_POSITION;
    public float4 uv0Uv2 : TEXCOORD0;
};

public ShadowCasterOutput shadowCasterVertex(DentedMeshInput input, float dentPower)
{
    float3 dent = meshDent(input.uv1.xy, input.color.rgb, dentPower);
    float3 positionWS = objectToWorld.point(input.positionOS.xyz + dent);
    positionWS = shadowCasterPosition(positionWS, input.normalOS, objectToWorld, shadowLightDirection, shadowBias);

    ShadowCasterOutput output;
    output.positionCS = viewProjection.clipPosition(positionWS);
    output.positionCS.z = min(output.positionCS.z, 1);
    output.uv0Uv2 = float4(input.uv0.xy, input.uv2.xy);
    return output;
}
