/// Samples the mesh dent height at mip zero in the vertex stage.
SamplerState sampler_Create_dent_texture : register(s0);
/// Red gives vertex displacement height at mip zero using mesh UV1.
Texture2D<float4> _Create_dent_texture : register(t0);

/// Mesh inputs shared by dented depth-only, depth-normal, and shadow-caster vertex programs.
public struct DentedMeshInput
{
    /// Object-space mesh position. XYZ is displaced before projection.
    public float4 positionOS : POSITION0;
    /// Mesh normal in object space before deformation.
    public float3 normalOS : NORMAL0;
    /// Mesh tangent and handedness in the shared Unity input signature. The depth and caster paths do not read it.
    public float4 tangentOS : TANGENT0;
    /// RGB encodes object-space dent direction about 0.5. Alpha is unused by these depth and caster vertices.
    public float4 color : COLOR0;
    /// Mesh UV1 in XY, sampled at mip zero for dent height.
    public float4 uv1 : TEXCOORD1;
    /// Mesh UV0 in XY, passed to the fragment stage for silhouette clipping.
    public float4 uv0 : TEXCOORD0;
    /// Mesh UV2 in XY, the alternative garment coverage UV.
    public float4 uv2 : TEXCOORD2;
};

/// Converts dent-map red and mesh vertex RGB into an object-space displacement at UV1.
public float3 meshDent(float2 uv, float3 color, float strength)
{
    float height = _Create_dent_texture.SampleLevel(sampler_Create_dent_texture, uv, 0).r * strength;
    return mad(color, height * -0.14, height * 0.07);
}
