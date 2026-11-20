import Geometry.VertexTransforms;

/// Per-camera constants at the offsets used by this shader stage.
cbuffer Globals : register(b0)
{
    /// World-space main-light vector. W weights translation when transforming the vector into object space.
    float4 mainLight : packoffset(c5);
    /// Four columns of the current world-to-clip transform, applied to the world-space vertex position.
    TransformColumns viewProjection : packoffset(c82);
};

/// Per-renderer transforms and lighting data for this stage.
cbuffer UnityPerDraw : register(b1)
{
    /// Four columns of the current object-to-world transform, including translation in the last column.
    TransformColumns objectToWorld : packoffset(c0);
    /// Inverse object transform. Its linear part supplies the inverse-transpose normal and the object-space
    /// light.
    TransformColumns worldToObject : packoffset(c4);
    /// Sign of the object transform, multiplied by tangent W when reconstructing handedness.
    float worldSign : packoffset(c9.w);
};

/// Material properties at the serialized byte offsets for this pass.
cbuffer UnityPerMaterial : register(b2)
{
    /// Scales outline extrusion and the line coverage derived from the detail mask.
    float _Line_width : packoffset(c19.z);
    /// Chest shape control for normal flattening, painted shading and outline width.
    float _Bust_size : packoffset(c23.w);
    /// Strength of vertex displacement along the vertex-color dent direction and of the matching fragment
    /// mask.
    float _Dent_power : packoffset(c24.x);
    /// Blends normal-only outline extrusion toward the vertex-color direction and dent offset.
    float _VertexColorNormal : packoffset(c24.y);
};

/// Reads the red outline-exclusion mask at mip zero before vertex extrusion.
SamplerState detailSampler : register(s0);
/// Reads the chest outline taper from alpha in overlay slice 2 at mip zero.
SamplerState overlaySampler : register(s1);
/// Samples the dent height at mesh UV1.
SamplerState sampler_Create_dent_texture : register(s2);
/// Red dent height in UV1, used for vertex displacement and for the fragment's dent mask.
Texture2D<float4> _Create_dent_texture : register(t0);
/// Body detail array. Slice 0 packs outline in R, creases in G, shade in B and bust selection in A. Slice 1 R
/// covers lines.
Texture2DArray<float4> _Detail_mask_01 : register(t1);
/// Body overlays by array slice. 0 holds liquid regions, 1 liquid patterns, 2 pigment and outline masks, 3
/// shading regions.
Texture2DArray<float4> _TexEX : register(t2);

/// Mesh attributes in the vertex register order used by this pass.
struct StageInput
{
    /// Object-space mesh position. XYZ enters the object-to-world transform.
    float4 positionOS : POSITION0;
    /// Mesh normal in object space, before deformation and interpolation.
    float3 normalOS : NORMAL0;
    /// Object-space mesh tangent in XYZ. W gives the sign used to reconstruct the bitangent.
    float4 tangentOS : TANGENT0;
    /// Primary material UV in XY for pigment, detail and wetness.
    float4 uv0 : TEXCOORD0;
    /// Mesh vertex color. RGB encodes the object-space dent direction and can steer outline extrusion.
    float4 color : COLOR0;
    /// Mesh UV1 in XY for the painted dent height.
    float4 uv1 : TEXCOORD1;
    /// Mesh UV2 in XY for nipple placement and optional clothing cutout sampling.
    float4 uv2 : TEXCOORD2;
    /// Mesh UV3 in XY for under-hair pigment.
    float4 uv3 : TEXCOORD3;
};

/// Clip position and varyings in the register order expected by the original fragment stage.
struct StageOutput
{
    /// Homogeneous clip-space position for rasterization.
    float4 positionCS : SV_POSITION;
    /// Interpolated vertex position in world units in XYZ. The vertex shader sets W to zero.
    float4 positionWS : TEXCOORD0;
    /// World-space mesh normal for lighting. Interpolation can change its length.
    float3 normalWS : TEXCOORD1;
    /// World-space tangent direction in XYZ and signed bitangent handedness in W.
    float4 tangentWS : TEXCOORD2;
    /// Zero-filled interpolator retained at this register in the shipped stage signature.
    float4 unused4 : TEXCOORD3;
    /// Zero-filled interpolator retained at this register in the shipped stage signature.
    float4 unused5 : TEXCOORD4;
    /// XY carry mesh UV0 for pigment and detail. ZW carry UV1 for the dent mask.
    float4 uv0Uv1 : TEXCOORD5;
    /// XY carry UV2 for nipple placement or clothing cutouts. ZW carry UV3 for under-hair pigment.
    float4 uv2Uv3 : TEXCOORD6;
    /// Original object-space mesh position. XY anchor wet-skin grain to the surface.
    float4 positionOS : TEXCOORD7;
    /// Main-light vector in object space in XYZ, with W set to zero. The rim uses its vertical component.
    float4 mainLightOS : TEXCOORD8;
    /// Original mesh normal in object space, interpolated for the vertical rim falloff.
    float3 normalOS : NORMAL0;
};

/// Extrudes the body outline, projects it into clip space and forwards the UV and basis required by its color
/// pass.
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
