// Unity binds the same material property layout at a different slot in the prepass.
#if SKIN_PREPASS
/// Material properties at the serialized byte offsets for this pass.
public cbuffer UnityPerMaterial : register(b5)
#else
/// Material properties at the serialized byte offsets for this pass.
public cbuffer UnityPerMaterial : register(b6)
#endif
{
    /// Tiled liquid-pattern UV transform. ZW scale the mesh UV and XY supply the offset.
    public float4 _LiquidTiling : packoffset(c0);
    /// Secondary nipple pigment RGB. Alpha scales the red texture channel for the two-color blend.
    public float4 _Nip_color_02 : packoffset(c1);
    /// Normalized UV transform for _Create_main_texture. XY scale and ZW offset before sampling.
    public float4 _Create_main_texture_ST : packoffset(c2);
    /// RGB tint for the painted shine lobe. Alpha controls its strength.
    public float4 _Highlight_color : packoffset(c3);
    /// Tint for the red body detail mask. RGB is brightness-adjusted and A scales coverage.
    public float4 _Detail_color_02 : packoffset(c4);
    /// Artist shadow RGB blended into the palette by _UseShadowColor.
    public float4 _Shade_color : packoffset(c5);
    /// RGB for the view-dependent shadow tint. Alpha controls its influence on contours, rims and palette
    /// shading.
    public float4 _Shadow_color : packoffset(c6);
    /// Tint for the under-hair texture RGB. Alpha scales its opacity and its effect on shading.
    public float4 _Under_hair_color : packoffset(c8);
    /// Base nipple pigment RGB. Alpha scales surface coverage, bump and rim suppression.
    public float4 _Nip_color_01 : packoffset(c9);
    /// Blush tint RGB blended through the blue channel of the detail color slice and _SiriakaIntensity.
    public float4 _hohoakacolor : packoffset(c10);
    /// XY are the reciprocal paint width and height, in UV per texel, for displacement and height
    /// differences.
    public float4 _FluidTex_TexelSize : packoffset(c11);
    /// Normalized UV transform for _FluidTex. XY scale and ZW offset before sampling.
    public float4 _FluidTex_ST : packoffset(c12);
    /// Normalized UV transform for _Detail_mask_02. XY scale and ZW offset before sampling.
    public float4 _Detail_mask_02_ST : packoffset(c13);
    /// Normalized UV transform for _Cloth_alpha. XY scale and ZW offset before sampling.
    public float4 _Cloth_alpha_ST : packoffset(c14);
    /// RGB tint for the painted lines and outline pass.
    public float3 _Line_color : packoffset(c16);
    /// Lower and upper thresholds for mapping the animated cell-distance field to droplet height in [0, 1].
    public float2 _SweatNoise : packoffset(c17);
    /// Coefficient multiplying paint alpha in the exponential attenuation of the fluid color.
    public float _FluidColorScatter : packoffset(c17.z);
    /// Blend from the fluid paint RGB at zero to the underlying skin RGB at one.
    public float _FluidTransmittance : packoffset(c17.w);
    /// Strength of the color overlay that darkens the matcap-shaded pigment.
    public float _TestOC : packoffset(c18.y);
    /// Saturation added to the HSV tint of the fluid's shaded band.
    public float _FluidShadowSaturation : packoffset(c18.z);
    /// Multiplier for the fluid's colored shadow relative to its transmitted pigment.
    public float _FluidShadowPower : packoffset(c18.w);
    /// Opacity of the view-dependent shadow tint in the skin pigment.
    public float _TestMatcapShade : packoffset(c19);
    /// Lower limit on color throughput as scattering increases with paint alpha.
    public float _FluidMinColorScale : packoffset(c19.y);
    /// Scales outline extrusion and the line coverage derived from the detail mask.
    public float _Line_width : packoffset(c19.z);
    /// Adds brightness to the fluid highlight in proportion to pigment value.
    public float _FluidHighlightPower : packoffset(c19.w);
    /// Scales exclusion by regional detail masks before the main rim is applied.
    public float _RimMaskIntensity : packoffset(c20);
    /// Threshold in light-facing space that controls the width of the fluid highlight.
    public float _FluidHighlightSize : packoffset(c20.y);
    /// Scales paint alpha before blending the shaded fluid onto the underlying skin.
    public float _FluidScale : packoffset(c20.z);
    /// Controls shininess and the painted shine texture's view-dependent UV scale.
    public float _shine_scale : packoffset(c20.w);
    /// Power gain of the two painted shine texture lobes.
    public float _shine_power : packoffset(c21);
    /// Strength of the secondary grazing rim, capped by _TestRim.
    public float _TestRimSub : packoffset(c21.y);
    /// Gain of the key-light backscatter tint added to the lit skin.
    public float _TestSSS : packoffset(c21.z);
    /// Controls the blend from shaded pigment to the authored line RGB.
    public float _Line_power : packoffset(c21.w);
    /// Fraction of the ordered 4×4 screen pattern allowed to pass, from zero to one.
    public float _Dither : packoffset(c22);
    /// Rounded top-garment coverage switch used with the top and bottom clothing masks.
    public float _alpha_a : packoffset(c22.y);
    /// Blends clothing-mask coordinates from transformed UV0 at zero to transformed UV2 at one.
    public float _AlphaMaskuv : packoffset(c22.z);
    /// Adjusts the start and end of the fluid's facing-dependent shadow band.
    public float _FluidShadowSize : packoffset(c22.w);
    /// Gain of the main silhouette rim and upper bound on the secondary rim strength.
    public float _TestRim : packoffset(c23);
    /// Blends the artist shadow pigment into the base pigment using local shade coverage.
    public float _BaseColorMix : packoffset(c23.y);
    /// Overall weight of painted skin-detail darkening in the ramp.
    public float _mdGIntensity : packoffset(c23.z);
    /// Chest shape control for normal flattening, painted shading and outline width.
    public float _Bust_size : packoffset(c23.w);
    /// Strength of vertex displacement along the vertex-color dent direction and of the matching fragment
    /// mask.
    public float _Dent_power : packoffset(c24);
    /// Spatial frequency of the procedural UV warp in paint texture space.
    public float _Fluid_Noise_Scale : packoffset(c24.z);
    /// Warp amplitude in paint texels, converted to normalized UV by the paint texel size.
    public float _Fluid_Noise_Amount : packoffset(c24.w);
    /// Converts neighbor differences in paint alpha into tangent-space slope.
    public float _FluidNormalScale : packoffset(c25);
    /// Scales the base normal map and the fine detail shading sampled from the secondary mask.
    public float _SkinIntensity : packoffset(c25.y);
    /// Controls the size of the nipple texture placement in UV2.
    public float _Nip_size : packoffset(c25.z);
    /// Liquid level for the positive red-minus-green region of the body mask (front, upper).
    public float _liquidftop : packoffset(c25.w);
    /// Liquid level for the positive green-minus-red region of the body mask (front, lower).
    public float _liquidfbot : packoffset(c26);
    /// Artist ramp strength, remapped around 0.5 to set the depth of palette shading.
    public float _Shadow_power : packoffset(c26.y);
    /// Liquid level for the blue region of the body mask (back, upper).
    public float _liquidbtop : packoffset(c26.z);
    /// Sweat intensity, scaling procedural droplet height, wet normals and reflection.
    public float _AseIntensity : packoffset(c26.w);
    /// Overall wetness. Controls skin darkening and the roughness and strength of the reflection probe.
    public float _NureIntensity : packoffset(c27);
    /// Strength of the blush tint through blue in the body detail color slice.
    public float _SiriakaIntensity : packoffset(c27.y);
    /// Blend from the calculated shadow shade to _Shade_color.rgb.
    public float _UseShadowColor : packoffset(c27.z);
    /// Gain of the detail-dependent ramp offset outside the primary blue mask.
    public float _mdGShadeControle : packoffset(c27.w);
    /// Rounded bottom-garment coverage switch used with the top and bottom clothing masks.
    public float _alpha_b : packoffset(c28);
    /// Scales the chest-specific contribution to painted shadow coverage.
    public float _Bust_shadowonoff : packoffset(c28.y);
    /// Adjusts the contrast of the chest-specific shadow mask.
    public float _mdGBustPower : packoffset(c28.z);
    /// Strength of the chest-specific shadow when combined with general detail occlusion.
    public float _mdGBustIntensity : packoffset(c28.w);
    /// Adjusts contrast of the detail shadow before it enters the palette.
    public float _mdGPower : packoffset(c29);
    /// Liquid level for the red-times-green overlap in the body mask (back, lower).
    public float _liquidbbot : packoffset(c29.y);
    /// Gain of the body line mask read from the second detail-array slice.
    public float _linetexon : packoffset(c29.z);
};
