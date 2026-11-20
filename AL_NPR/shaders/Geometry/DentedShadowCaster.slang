import Geometry.VertexTransforms;
import Geometry.DentedMesh;

/// Camera and light constants used by this Unity vertex pass.
cbuffer Globals : register(b0)
{
    /// Four columns transforming displaced world position to homogeneous clip space.
    TransformColumns viewProjection : packoffset(c78);
    /// X offsets the caster along the light direction. Y scales the normal offset at grazing angles.
    float2 shadowBias : packoffset(c129);
    /// World-space light direction used to bias the shadow-caster position.
    float3 shadowLightDirection : packoffset(c130);
};

/// Per-draw Unity mesh transforms.
cbuffer UnityPerDraw : register(b1)
{
    /// Four object-to-world columns for positions and directions after mesh displacement.
    TransformColumns objectToWorld : packoffset(c0);
};

/// Biased shadow projection and the garment UVs used for caster clipping.
public struct ShadowCasterOutput
{
    /// Homogeneous clip-space position for rasterization.
    public float4 positionCS : SV_POSITION;
    /// XY carries mesh UV0 and ZW carries mesh UV2 for garment clipping.
    public float4 uv0Uv2 : TEXCOORD0;
};

/// Adds caster bias to the dented world position and clamps the resulting clip Z to one.
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
