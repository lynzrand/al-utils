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
    /// Inverse transform used for inverse-transpose normals and, in color passes, the object-space light vector.
    TransformColumns worldToObject : packoffset(c4);
};

/// Displaced depth vertex, world normal, and the garment coverage UV sets.
public struct DepthNormalsOutput
{
    /// Homogeneous clip-space position for rasterization.
    public float4 positionCS : SV_POSITION;
    /// Unit mesh normal transformed to world space before interpolation.
    public float3 normalWS : TEXCOORD0;
    /// XY carries mesh UV0 and ZW carries mesh UV2 for garment clipping.
    public float4 uv0Uv2 : TEXCOORD1;
};

/// Projects the dented mesh and forwards the transformed mesh normal for the normal target.
public DepthNormalsOutput depthNormalsVertex(DentedMeshInput input, float dentPower)
{
    float3 dent = meshDent(input.uv1.xy, input.color.rgb, dentPower);
    float3 positionWS = objectToWorld.point(input.positionOS.xyz + dent);

    DepthNormalsOutput output;
    output.positionCS = viewProjection.clipPosition(positionWS);
    output.normalWS = surfaceNormal(input.normalOS, worldToObject);
    output.uv0Uv2 = float4(input.uv0.xy, input.uv2.xy);
    return output;
}
