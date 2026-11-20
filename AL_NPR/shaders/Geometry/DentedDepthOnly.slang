import Geometry.VertexTransforms;
import Geometry.DentedMesh;

cbuffer Globals : register(b0)
{
    TransformColumns viewProjection : packoffset(c78);
};

cbuffer UnityPerDraw : register(b1)
{
    TransformColumns objectToWorld : packoffset(c0);
};

public struct DepthOutput
{
    public float4 positionCS : SV_POSITION;
    public float4 uv0Uv2 : TEXCOORD0;
};

public DepthOutput depthOnlyVertex(DentedMeshInput input, float dentPower)
{
    float3 dent = meshDent(input.uv1.xy, input.color.rgb, dentPower);
    float3 positionWS = objectToWorld.point(input.positionOS.xyz + dent);

    DepthOutput output;
    output.positionCS = viewProjection.clipPosition(positionWS);
    output.uv0Uv2 = float4(input.uv0.xy, input.uv2.xy);
    return output;
}
