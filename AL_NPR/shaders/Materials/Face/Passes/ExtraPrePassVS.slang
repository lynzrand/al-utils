import Geometry.VertexTransforms;

/// Per-camera constants at the offsets used by this shader stage.
cbuffer Globals : register(b0)
{
    /// Four columns of the current world-to-clip transform, applied to the world-space vertex position.
    TransformColumns viewProjection : packoffset(c78);
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
    /// Normalized UV transform for _Detail_mask_01. XY scale and ZW offset before sampling.
    float4 _Detail_mask_01_ST : packoffset(c21);
    /// Caps face extrusion as a function of the red detail mask before applying depth scaling.
    float _LineWidthMax : packoffset(c29.y);
    /// Maximum clip W used to scale the face outline's object-space extrusion.
    float _DistanceCutoff : packoffset(c29.z);
    /// Scales outline extrusion and the line coverage derived from the detail mask.
    float _Line_width : packoffset(c34.w);
};

/// Reads the red outline-exclusion mask at mip zero before vertex extrusion.
SamplerState sampler_Detail_mask_01 : register(s0);
/// Primary face detail. R restricts outline and liquid coverage, G modulates detail and rim, B masks shade
/// and rim.
Texture2D<float4> _Detail_mask_01 : register(t0);

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
    /// Mesh UV1 in XY for cheek pigment and highlight placement.
    float4 uv1 : TEXCOORD1;
    /// Mesh UV3 in XY for lips and lip lines.
    float4 uv3 : TEXCOORD3;
    /// Mesh UV2 in XY for nose pigment, line and gloss.
    float4 uv2 : TEXCOORD2;
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
    /// XY carry mesh UV0 for pigment and detail. ZW carry UV1 for cheek placement.
    float4 uv0Uv1 : TEXCOORD3;
    /// Outline-specific packing. XY carry lip UV3 and ZW carry nose UV2.
    float4 uv3Uv2 : TEXCOORD4;
    /// Zero-filled interpolator retained at this register in the shipped stage signature.
    float4 unused6 : TEXCOORD5;
    /// Zero-filled interpolator retained at this register in the shipped stage signature.
    float4 unused7 : TEXCOORD6;
};

/// Extrudes the face outline, projects it into clip space and forwards the UV and basis required by its color
/// pass.
[shader("vertex")]
StageOutput main(StageInput input)
{
    float2 maskUV = mad(input.uv0.xy, _Detail_mask_01_ST.xy, _Detail_mask_01_ST.zw);
    float mask = _Detail_mask_01.SampleLevel(sampler_Detail_mask_01, maskUV, 0).r;
    float width = max(0, min(saturate(mad(mask, -1.2, 1)), (1 - mask) * _Line_width * 0.05));
    width = min(width, mad(mask, _LineWidthMax - 1, 1) * 0.05);
    float clipW = viewProjection.clipPosition(objectToWorld.point(input.positionOS.xyz)).w;
    float3 outline = mad(width * input.normalOS, min(clipW, _DistanceCutoff), input.positionOS.xyz);
    float3 positionWS = objectToWorld.point(outline);

    StageOutput output;
    output.positionCS = viewProjection.clipPosition(positionWS);
    output.positionWS = float4(positionWS, 0);
    output.normalWS = surfaceNormal(input.normalOS, worldToObject);
    output.tangentWS = surfaceTangent(input.tangentOS, objectToWorld, worldSign);
    output.uv0Uv1 = float4(input.uv0.xy, input.uv1.xy);
    output.uv3Uv2 = float4(input.uv3.xy, input.uv2.xy);
    output.unused6 = 0;
    output.unused7 = 0;
    return output;
}
