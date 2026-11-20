// Unity binds these textures and samplers separately for Forward and ExtraPrePass.

/// Lip artwork in UV3. Red selects pigment coverage and blue selects the highlight.
public Texture2D<float4> _Lip_texture : register(t5);

#if SKIN_PREPASS
/// Samples the primary detail masks for lines and regional shading.
public SamplerState sampler_Detail_mask_01 : register(s0);
/// Samples fine shadow detail at its transformed material UV.
public SamplerState sampler_Detail_mask_02 : register(s1);
/// Reads the generated head pigment and its coverage in UV0.
public SamplerState sampler_Create_jm_main_skin_head : register(s2);
/// Reads spot, shade and line masks together at their placed UV.
public SamplerState sampler_spmap : register(s3);
/// Samples UV0 blush coverage from the expression texture.
public SamplerState sampler_expressionmap : register(s4);
/// Used for both the pigment and independently transformed cheek highlight samples.
public SamplerState sampler_Cheek_texture : register(s5);
/// Reads the lip pigment and highlight masks together in UV3.
public SamplerState sampler_Lip_texture : register(s6);
/// Samples the nose artwork at its placed UV and the Forward gloss at its displaced UV.
public SamplerState sampler_Nose_texture : register(s7);
/// Samples paint RGB and alpha at the center and both offset height taps.
public SamplerState sampler_FluidTex : register(s8);
/// Reads the wet tangent-space normal at the tiled liquid UV.
public SamplerState sampler_LiquidBump : register(s9);
/// Reads the two coverage levels of the tiled face liquid pattern.
public SamplerState sampler_Texture2 : register(s10);
/// Secondary face detail. G modulates direct light and B controls rim, liquid coverage and shading-normal
/// blends.
public Texture2D<float4> _Detail_mask_02 : register(t0);
/// Generated head pigment in UV0. RGB supplies the base color and A blends it over white.
public Texture2D<float4> _Create_jm_main_skin_head : register(t1);
/// Face spot overlay in UV0. Red covers pigment, green contributes shade and blue covers line tint.
public Texture2D<float4> _spmap : register(t2);
/// Red expression mask scales the face blush tint.
public Texture2D<float4> _expressionmap : register(t3);
/// Red carries cheek pigment and blue carries its highlight. Each channel uses its own placement transform.
public Texture2D<float4> _Cheek_texture : register(t4);
/// UV2 nose artwork. R selects pigment, G contributes shade, B covers the nose line and A controls gloss.
public Texture2D<float4> _Nose_texture : register(t6);
/// Painted fluid. RGB is pigment and A drives coverage, scattering and height differences for the bump
/// normal.
public Texture2D<float4> _FluidTex : register(t7);
/// Tiled liquid pattern. R and G supply the two coverage levels used with _liquidface.
public Texture2D<float4> _Texture2 : register(t8);
/// Primary face detail. R restricts outline and liquid coverage, G modulates detail and rim, B masks shade
/// and rim.
public Texture2D<float4> _Detail_mask_01 : register(t9);
/// Tangent-space liquid normal map. Red times alpha encodes X and green encodes Y.
public Texture2D<float4> _LiquidBump : register(t10);
#else
/// Samples explicit reflection-probe mips selected from wetness or droplet shape.
public SamplerState samplerunity_SpecCube0 : register(s0);
/// Depth comparison sampler shared by the main and additional shadow atlases.
public SamplerComparisonState shadowCompare1 : register(s1);
/// Samples paint RGB and alpha at the center and both offset height taps.
public SamplerState sampler_FluidTex : register(s2);
/// Reads the wet tangent-space normal at the tiled liquid UV.
public SamplerState sampler_LiquidBump : register(s3);
/// Reads the two coverage levels of the tiled face liquid pattern.
public SamplerState sampler_Texture2 : register(s4);
/// Samples the primary detail masks for lines and regional shading.
public SamplerState sampler_Detail_mask_01 : register(s5);
/// Samples fine shadow detail at its transformed material UV.
public SamplerState sampler_Detail_mask_02 : register(s6);
/// Reads the lip pigment and highlight masks together in UV3.
public SamplerState sampler_Lip_texture : register(s7);
/// Used for both the pigment and independently transformed cheek highlight samples.
public SamplerState sampler_Cheek_texture : register(s8);
/// Reads the generated head pigment and its coverage in UV0.
public SamplerState sampler_Create_jm_main_skin_head : register(s9);
/// Reads the lip detail and final line mask together in UV3.
public SamplerState sampler_Lip_line_texture : register(s10);
/// Reads spot, shade and line masks together at their placed UV.
public SamplerState sampler_spmap : register(s11);
/// Samples the nose artwork at its placed UV and the Forward gloss at its displaced UV.
public SamplerState sampler_Nose_texture : register(s12);
/// Reads the palette ramp along its diagonal at the computed lighting coordinate.
public SamplerState sampler_Lamp : register(s13);
/// Samples UV0 blush coverage from the expression texture.
public SamplerState sampler_expressionmap : register(s14);
/// Painted fluid. RGB is pigment and A drives coverage, scattering and height differences for the bump
/// normal.
public Texture2D<float4> _FluidTex : register(t0);
/// Tiled liquid pattern. R and G supply the two coverage levels used with _liquidface.
public Texture2D<float4> _Texture2 : register(t1);
/// Primary face detail. R restricts outline and liquid coverage, G modulates detail and rim, B masks shade
/// and rim.
public Texture2D<float4> _Detail_mask_01 : register(t2);
/// Secondary face detail. G modulates direct light and B controls rim, liquid coverage and shading-normal
/// blends.
public Texture2D<float4> _Detail_mask_02 : register(t3);
/// Tangent-space liquid normal map. Red times alpha encodes X and green encodes Y.
public Texture2D<float4> _LiquidBump : register(t4);
/// Red carries cheek pigment and blue carries its highlight. Each channel uses its own placement transform.
public Texture2D<float4> _Cheek_texture : register(t6);
/// Generated head pigment in UV0. RGB supplies the base color and A blends it over white.
public Texture2D<float4> _Create_jm_main_skin_head : register(t7);
/// UV3 lip detail. Red contributes to shading and blue covers the final line tint.
public Texture2D<float4> _Lip_line_texture : register(t8);
/// Face spot overlay in UV0. Red covers pigment, green contributes shade and blue covers line tint.
public Texture2D<float4> _spmap : register(t9);
/// UV2 nose artwork. R selects pigment, G contributes shade, B covers the nose line and A controls gloss.
public Texture2D<float4> _Nose_texture : register(t10);
/// Artist palette ramp. The skin shader samples the blue channel along the texture diagonal.
public Texture2D<float4> _Lamp : register(t11);
/// Red expression mask scales the face blush tint.
public Texture2D<float4> _expressionmap : register(t12);
/// World-space reflection probe. Wetness sets mip level and the per-draw HDR parameters decode its RGB.
public TextureCube<float4> unity_SpecCube0 : register(t13);
/// Cascade depth atlas sampled with the shadow comparison sampler for stock key visibility.
public Texture2D<float4> _MainLightShadowmapTexture : register(t14);
/// Spot and point shadow atlas sampled for clustered-light visibility.
public Texture2D<float4> _AdditionalLightsShadowmapTexture : register(t15);
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
    /// XY carry mesh UV0 for pigment and detail. ZW carry UV1 for cheek placement.
    public float4 uv0Uv1 : TEXCOORD3;
    /// Outline-specific packing. XY carry lip UV3 and ZW carry nose UV2.
    public float4 uv3Uv2 : TEXCOORD4;
    /// Zero-filled interpolator retained at this register in the shipped stage signature.
    public float4 unused6 : TEXCOORD5;
    /// Zero-filled interpolator retained at this register in the shipped stage signature.
    public float4 unused7 : TEXCOORD6;
#else
    /// Zero-filled interpolator retained at this register in the shipped stage signature.
    public float4 unused4 : TEXCOORD3;
    /// Zero-filled interpolator retained at this register in the shipped stage signature.
    public float4 unused5 : TEXCOORD4;
    /// XY carry mesh UV0 for pigment and detail. ZW carry UV1 for cheek placement.
    public float4 uv0Uv1 : TEXCOORD5;
    /// XY carry UV2 for the nose. ZW carry UV3 for lips and lip lines.
    public float4 uv2Uv3 : TEXCOORD6;
    /// Main-light vector in object space in XYZ, with W set to zero. The rim uses its vertical component.
    public float4 mainLightOS : TEXCOORD7;
    /// Original mesh normal in object space, interpolated for the vertical rim falloff.
    public float3 normalOS : NORMAL0;
    /// Original object-space mesh position. XY anchor wet-skin grain to the surface.
    public float4 positionOS : TEXCOORD8;
#endif
    /// Rasterizer face orientation used to flip the shading direction and suppress back-facing rims.
    public bool frontFacing : SV_IsFrontFace;
}
