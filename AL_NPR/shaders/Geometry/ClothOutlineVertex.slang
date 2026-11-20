import Geometry.VertexTransforms;

/// Samples outline width suppression from blue detail at mip zero.
SamplerState sampler_Detail_mask_01 : register(s0);
/// Samples the mesh dent height at mip zero in the vertex stage.
SamplerState sampler_Create_dent_texture : register(s1);
/// R modulates sheerness and wet detail, G controls finish and shadow detail, B controls outlines and cutoff, and A suppresses rim light.
Texture2D<float4> _Detail_mask_01 : register(t0);
/// Red gives vertex displacement height at mip zero using mesh UV1.
Texture2D<float4> _Create_dent_texture : register(t1);

/// Camera and light constants used by this Unity vertex pass.
cbuffer Globals : register(b0)
{
    /// XYZ is the world-space light vector. W weights translation when transforming it into object space.
    float4 mainLight : packoffset(c5);
    /// Four columns transforming displaced world position to homogeneous clip space.
    TransformColumns viewProjection : packoffset(c82);
};

/// Per-draw Unity mesh transforms.
cbuffer UnityPerDraw : register(b1)
{
    /// Four object-to-world columns for positions and directions after mesh displacement.
    TransformColumns objectToWorld : packoffset(c0);
    /// Inverse transform used for inverse-transpose normals and, in color passes, the object-space light vector.
    TransformColumns worldToObject : packoffset(c4);
    /// Object transform handedness. Its sign corrects the tangent basis on mirrored meshes.
    float worldSign : packoffset(c9.w);
};

/// Mesh geometry, authored extrusion color, and UVs for the cloth outline vertex stage.
public struct ClothOutlineInput
{
    /// Object-space mesh position. XYZ is displaced before projection.
    public float4 positionOS : POSITION0;
    /// Mesh normal in object space before deformation.
    public float3 normalOS : NORMAL0;
    /// Object-space mesh tangent in XYZ and the tangent-frame handedness in W.
    public float4 tangentOS : TANGENT0;
    /// Mesh UV0 in XY, used for pigment, detail, and the primary coverage UV.
    public float4 uv0 : TEXCOORD0;
    /// Vertex RGB encodes dent direction about 0.5. The outline pass also uses it to steer extrusion.
    public float4 color : COLOR0;
    /// Mesh UV1 in XY, sampled by the dent map. Cloth color vertices also forward it in TEXCOORD5.zw.
    public float4 uv1 : TEXCOORD1;
    /// Mesh UV2 in XY, the alternative garment coverage UV.
    public float4 uv2 : TEXCOORD2;
};

/// Outline-extruded vertex position and the varyings consumed by the cloth color pass.
public struct ClothOutlineOutput
{
    /// Homogeneous clip-space position for rasterization.
    public float4 positionCS : SV_POSITION;
    /// Displaced world-space position in XYZ. W is zero.
    public float4 positionWS : TEXCOORD0;
    /// Unit mesh normal transformed to world space before interpolation.
    public float3 normalWS : TEXCOORD1;
    /// Unit world-space mesh tangent in XYZ and mirror-corrected tangent-frame handedness in W.
    public float4 tangentWS : TEXCOORD2;
    /// Reserved zero varying carried by the game's vertex-to-fragment signature.
    public float4 unused4 : TEXCOORD3;
    /// Reserved zero varying at TEXCOORD4 in the game's vertex-to-fragment signature.
    public float4 unused5 : TEXCOORD4;
    /// XY carries mesh UV0 and ZW carries mesh UV1.
    public float4 uv0Uv1 : TEXCOORD5;
    /// XY carries mesh UV2 and ZW is zero.
    public float4 uv2Padded : TEXCOORD6;
    /// Undeformed object-space mesh position. The original homogeneous W passes through the color varyings.
    public float4 positionOS : TEXCOORD7;
    /// XYZ is the main light transformed into object space using the light's homogeneous W. Output W is zero.
    public float4 mainLightOS : TEXCOORD8;
    /// Mesh normal in object space before deformation.
    public float3 normalOS : NORMAL0;
};

/// Uses detail blue, a mip-zero dent, and the authored line width to extrude the colored outline.
public ClothOutlineOutput clothOutlineVertex(ClothOutlineInput input, float dentPower, float lineWidth, float vertexColorNormal)
{
    float height = _Create_dent_texture.SampleLevel(sampler_Create_dent_texture, input.uv1.xy, 0).r * dentPower;
    float3 dent = mad(input.color.rgb, height * -0.4, height * 0.2);
    float edge = 1 - _Detail_mask_01.SampleLevel(sampler_Detail_mask_01, input.uv0.xy, 0).b;
    float width = (edge * edge) * lineWidth * 0.2;
    float clipW = viewProjection.clipPosition(objectToWorld.point(input.positionOS.xyz)).w;
    float3 outline = outlinePosition(input.positionOS.xyz, input.normalOS, input.color.rgb, dent,
                                     width, vertexColorNormal, clipW);
    float3 positionWS = objectToWorld.point(outline);

    ClothOutlineOutput output;
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
