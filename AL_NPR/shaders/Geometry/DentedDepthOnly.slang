import Geometry.VertexTransforms;
import Geometry.DentedMesh;

/// Camera constants used to project the displaced mesh.
cbuffer Globals : register(b0)
{
    /// Four columns transforming displaced world position to homogeneous clip space.
    TransformColumns viewProjection : packoffset(c78);
};

/// Per-draw Unity mesh transforms.
cbuffer UnityPerDraw : register(b1)
{
    /// Four object-to-world columns for positions and directions after mesh displacement.
    TransformColumns objectToWorld : packoffset(c0);
};

/// Displaced depth vertex and the two garment coverage UV sets.
public struct DepthOutput
{
    /// Homogeneous clip-space position for rasterization.
    public float4 positionCS : SV_POSITION;
    /// XY carries mesh UV0 and ZW carries mesh UV2 for garment clipping.
    public float4 uv0Uv2 : TEXCOORD0;
};

/// Projects the dented mesh and forwards UV0 and UV2 for depth clipping.
public DepthOutput depthOnlyVertex(DentedMeshInput input, float dentPower)
{
    float3 dent = meshDent(input.uv1.xy, input.color.rgb, dentPower);
    float3 positionWS = objectToWorld.point(input.positionOS.xyz + dent);

    DepthOutput output;
    output.positionCS = viewProjection.clipPosition(positionWS);
    output.uv0Uv2 = float4(input.uv0.xy, input.uv2.xy);
    return output;
}
