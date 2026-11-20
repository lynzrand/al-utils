// Unity binds these textures and samplers separately for Forward and ExtraPrePass.

/// Samples explicit reflection-probe mips selected from wetness or droplet shape.
public SamplerState samplerunity_SpecCube0 : register(s0);
/// Samples the nipple artwork and the two neighboring taps for its height gradient.
public SamplerState sampler_Nip : register(s6);
/// Reads the wet tangent-space normal at the tiled liquid UV.
public SamplerState sampler_LiquidBump : register(s7);
/// Reads generated body pigment at transformed UV0.
public SamplerState sampler_Create_main_texture : register(s8);
/// Reads under-hair RGB and coverage from mesh UV3.
public SamplerState sampler_Under_hair_texture : register(s9);
/// Painted fluid. RGB is pigment and A drives coverage, scattering and height differences for the bump
/// normal.
public Texture2D<float4> _FluidTex : register(t0);
/// UV0 skin normal. Red times alpha supplies tangent X, green supplies tangent Y.
public Texture2D<float4> _Normal_map : register(t1);
/// Nipple artwork in UV2. RG provide height, R blends pigments, A covers the layer and B masks the rim.
public Texture2D<float4> _Nip : register(t2);
/// Tangent-space liquid normal map. Red times alpha encodes X and green encodes Y.
public Texture2D<float4> _LiquidBump : register(t3);
/// Generated body pigment. RGB blends over the default skin color through A.
public Texture2D<float4> _Create_main_texture : register(t4);
/// Under-hair pigment RGB and opacity A, sampled in UV3.
public Texture2D<float4> _Under_hair_texture : register(t5);
/// Secondary body detail. The transformed UV0 green channel supplies fine crease shading.
public Texture2D<float4> _Detail_mask_02 : register(t6);
/// Red dent height in UV1, used for vertex displacement and for the fragment's dent mask.
public Texture2D<float4> _Create_dent_texture : register(t7);
/// Artist palette ramp. The skin shader samples the blue channel along the texture diagonal.
public Texture2D<float4> _Lamp : register(t8);
/// Painted shine lobes. R and G are sampled at separate scaled, view-dependent coordinates.
public Texture2D<float4> _shine_texture : register(t9);
/// Bottom garment coverage. R and B pair with top B and R. G limits coverage.
public Texture2D<float4> _Cloth_alpha_bot : register(t10);
/// Top garment coverage. R and B pair with bottom B and R. G limits coverage.
public Texture2D<float4> _Cloth_alpha : register(t11);
/// World-space reflection probe. Wetness sets mip level and the per-draw HDR parameters decode its RGB.
public TextureCube<float4> unity_SpecCube0 : register(t12);

#if SKIN_PREPASS
/// Samples the primary detail masks for lines and regional shading.
public SamplerState detailArraySampler : register(s1);
/// Reads body overlay slices by material UV and array index.
public SamplerState extraArraySampler : register(s2);
/// Samples the dent height at mesh UV1.
public SamplerState sampler_Create_dent_texture : register(s3);
/// Samples paint RGB and alpha at the center and both offset height taps.
public SamplerState sampler_FluidTex : register(s4);
/// Reads the tangent-space skin normal from mesh UV0.
public SamplerState sampler_Normal_map : register(s5);
/// Samples fine shadow detail at its transformed material UV.
public SamplerState sampler_Detail_mask_02 : register(s10);
/// Reads the palette ramp along its diagonal at the computed lighting coordinate.
public SamplerState sampler_Lamp : register(s11);
/// Samples the red and green shine lobes at different scaled, view-dependent coordinates.
public SamplerState sampler_shine_texture : register(s12);
/// Reads the bottom garment mask at the UV selected by _AlphaMaskuv.
public SamplerState sampler_Cloth_alpha_bot : register(s13);
/// Reads the top garment mask at the UV selected by _AlphaMaskuv.
public SamplerState sampler_Cloth_alpha : register(s14);
/// Body detail array. Slice 0 packs outline in R, creases in G, shade in B and bust selection in A. Slice 1 R
/// covers lines.
public Texture2DArray<float4> _Detail_mask_01 : register(t13);
/// Body overlays by array slice. 0 holds liquid regions, 1 liquid patterns, 2 pigment and outline masks, 3
/// shading regions.
public Texture2DArray<float4> _TexEX : register(t14);
#else
/// Depth comparison sampler shared by the main and additional shadow atlases.
public SamplerComparisonState shadowCompare1 : register(s1);
/// Samples the dent height at mesh UV1.
public SamplerState sampler_Create_dent_texture : register(s2);
/// Samples paint RGB and alpha at the center and both offset height taps.
public SamplerState sampler_FluidTex : register(s3);
/// Reads the tangent-space skin normal from mesh UV0.
public SamplerState sampler_Normal_map : register(s4);
/// Reads body overlay slices by material UV and array index.
public SamplerState extraArraySampler : register(s5);
/// Samples the primary detail masks for lines and regional shading.
public SamplerState detailArraySampler : register(s10);
/// Samples fine shadow detail at its transformed material UV.
public SamplerState sampler_Detail_mask_02 : register(s11);
/// Reads the palette ramp along its diagonal at the computed lighting coordinate.
public SamplerState sampler_Lamp : register(s12);
/// Samples the red and green shine lobes at different scaled, view-dependent coordinates.
public SamplerState sampler_shine_texture : register(s13);
/// Reads the bottom garment mask at the UV selected by _AlphaMaskuv.
public SamplerState sampler_Cloth_alpha_bot : register(s14);
/// Reads the top garment mask at the UV selected by _AlphaMaskuv.
public SamplerState sampler_Cloth_alpha : register(s15);
/// Cascade depth atlas sampled with the shadow comparison sampler for stock key visibility.
public Texture2D<float4> _MainLightShadowmapTexture : register(t13);
/// Spot and point shadow atlas sampled for clustered-light visibility.
public Texture2D<float4> _AdditionalLightsShadowmapTexture : register(t14);
/// Body overlays by array slice. 0 holds liquid regions, 1 liquid patterns, 2 pigment and outline masks, 3
/// shading regions.
public Texture2DArray<float4> _TexEX : register(t15);
/// Body detail array. Slice 0 packs outline in R, creases in G, shade in B and bust selection in A. Slice 1 R
/// covers lines.
public Texture2DArray<float4> _Detail_mask_01 : register(t16);
#endif

/// Interpolated fragment inputs and rasterizer values for the selected Forward or outline signature.
public struct StageInput
{
    /// Rasterized SV_Position. XY are render-target pixels used for ordered coverage and Forward+ tiles.
    public float4 positionCS : SV_POSITION;
    /// Interpolated vertex position in world units in XYZ. The vertex shader sets W to zero.
    public float4 positionWS : TEXCOORD0;
    /// World-space mesh normal for lighting. Interpolation can change its length.
    public float3 normalWS : TEXCOORD1;
    /// World-space tangent direction in XYZ and signed bitangent handedness in W.
    public float4 tangentWS : TEXCOORD2;
#if SKIN_PREPASS
    /// Zero-filled interpolator retained at this register in the shipped stage signature.
    public float4 unused4 : TEXCOORD3;
#else
    /// XY carry mesh UV0 for pigment and detail. ZW carry UV1 for the dent mask.
    public float4 uv0Uv1 : TEXCOORD3;
#endif
    /// Zero-filled interpolator retained at this register in the shipped stage signature.
    public float4 unused5 : TEXCOORD4;
#if SKIN_PREPASS
    /// XY carry mesh UV0 for pigment and detail. ZW carry UV1 for the dent mask.
    public float4 uv0Uv1 : TEXCOORD5;
#else
    /// Zero-filled interpolator retained at this register in the shipped stage signature.
    public float4 unused6 : TEXCOORD5;
#endif
    /// XY carry UV2 for nipple placement or clothing cutouts. ZW carry UV3 for under-hair pigment.
    public float4 uv2Uv3 : TEXCOORD6;
    /// Original object-space mesh position. XY anchor wet-skin grain to the surface.
    public float4 positionOS : TEXCOORD7;
    /// Main-light vector in object space in XYZ, with W set to zero. The rim uses its vertical component.
    public float4 mainLightOS : TEXCOORD8;
    /// Original mesh normal in object space, interpolated for the vertical rim falloff.
    public float3 normalOS : NORMAL0;
    /// Rasterizer face orientation used to flip the shading direction and suppress back-facing rims.
    public bool frontFacing : SV_IsFrontFace;
}
