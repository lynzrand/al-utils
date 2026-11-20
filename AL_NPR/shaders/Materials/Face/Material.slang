// Unity binds the same material property layout at a different slot in the prepass.
#if SKIN_PREPASS
/// Material properties at the serialized byte offsets for this pass.
public cbuffer UnityPerMaterial : register(b2)
#else
/// Material properties at the serialized byte offsets for this pass.
public cbuffer UnityPerMaterial : register(b6)
#endif
{
    /// RGB used for the nose line, with alpha multiplied by the blue nose-mask channel for coverage.
    public float4 _Nose_line_color : packoffset(c0);
    /// Artist shadow RGB blended into the palette by _UseShadowColor.
    public float4 _Shade_color : packoffset(c1);
    /// Tiled liquid-pattern UV transform. ZW scale the mesh UV and XY supply the offset.
    public float4 _LiquidTiling : packoffset(c2);
    /// XY are the reciprocal paint width and height, in UV per texel, for displacement and height
    /// differences.
    public float4 _FluidTex_TexelSize : packoffset(c3);
    /// Normalized UV transform for _FluidTex. XY scale and ZW offset before sampling.
    public float4 _FluidTex_ST : packoffset(c4);
    /// Nose pigment RGB. Alpha scales the red mask before blending onto the face.
    public float4 _Nose_color : packoffset(c5);
    /// Highlight RGB and strength in A. The blue lip mask supplies coverage.
    public float4 _Lip_highlight_color : packoffset(c6);
    /// Normalized UV transform for _Lip_texture. XY scale and ZW offset before sampling.
    public float4 _Lip_texture_ST : packoffset(c7);
    /// Lip pigment RGB and opacity in A, applied through the red lip mask.
    public float4 _Lip_color : packoffset(c8);
    /// Base highlight placement. XY translate in UV, Z sets rotation in turns, and W biases the scale.
    public float4 _CheekHighlight_position : packoffset(c9);
    /// Base cheek placement. XY translate in UV, Z sets rotation in turns, and W biases the scale.
    public float4 _Cheek_position : packoffset(c10);
    /// Cheek pigment RGB and opacity in A, sampled through the red cheek mask.
    public float4 _Cheek_color : packoffset(c11);
    /// Normalized UV transform for _Lip_line_texture. XY scale and ZW offset before sampling.
    public float4 _Lip_line_texture_ST : packoffset(c12);
    /// Normalized UV transform for _Detail_mask_02. XY scale and ZW offset before sampling.
    public float4 _Detail_mask_02_ST : packoffset(c13);
    /// Normalized UV transform for _expressionmap. XY scale and ZW offset before sampling.
    public float4 _expressionmap_ST : packoffset(c14);
    /// Cheek highlight RGB. Alpha weights the blue channel at a separately placed UV.
    public float4 _Cheek_highlight_color : packoffset(c15);
    /// Normalized UV transform for _Create_jm_main_skin_head. XY scale and ZW offset before sampling.
    public float4 _Create_jm_main_skin_head_ST : packoffset(c16);
    /// Spot pigment RGB blended through the red channel of _spmap.
    public float4 _spcolor : packoffset(c17);
    /// RGB for the view-dependent shadow tint. Alpha controls its influence on contours, rims and palette
    /// shading.
    public float4 _Shadow_color : packoffset(c18);
    /// Normalized UV transform for _spmap. XY scale and ZW offset before sampling.
    public float4 _spmap_ST : packoffset(c19);
    /// Blush pigment RGB and opacity in A. The red expression mask and _HohoakaIntensity control coverage.
    public float4 _hohoakacolor : packoffset(c20);
    /// Normalized UV transform for _Detail_mask_01. XY scale and ZW offset before sampling.
    public float4 _Detail_mask_01_ST : packoffset(c21);
    /// RGB tint for the painted lines and outline pass.
    public float3 _Line_color : packoffset(c22);
    /// Lower and upper thresholds for mapping the animated cell-distance field to droplet height in [0, 1].
    public float2 _SweatNoise : packoffset(c23);
    /// Scales exclusion by regional detail masks before the main rim is applied.
    public float _RimMaskIntensity : packoffset(c23.z);
    /// Strength of the secondary grazing rim, capped by _TestRim.
    public float _TestRimSub : packoffset(c23.w);
    /// Nose gloss strength, squared before scaling the alpha mask sampled at a view-shifted UV.
    public float _NoseGlossIntensity : packoffset(c24);
    /// Overall wetness. Controls skin darkening and the roughness and strength of the reflection probe.
    public float _NureIntensity : packoffset(c24.y);
    /// Gain of the main silhouette rim and upper bound on the secondary rim strength.
    public float _TestRim : packoffset(c24.z);
    /// Artist ramp strength, remapped around 0.5 to set the depth of palette shading.
    public float _Shadow_power : packoffset(c24.w);
    /// Sweat intensity, scaling procedural droplet height, wet normals and reflection.
    public float _AseIntensity : packoffset(c25.y);
    /// Strength of the color overlay that darkens the matcap-shaded pigment.
    public float _TestOC : packoffset(c25.z);
    /// Coefficient multiplying paint alpha in the exponential attenuation of the fluid color.
    public float _FluidColorScatter : packoffset(c25.w);
    /// Blend from the fluid paint RGB at zero to the underlying skin RGB at one.
    public float _FluidTransmittance : packoffset(c26);
    /// Saturation added to the HSV tint of the fluid's shaded band.
    public float _FluidShadowSaturation : packoffset(c26.y);
    /// Overall weight of painted skin-detail darkening in the ramp.
    public float _mdGIntensity : packoffset(c26.z);
    /// Scale about the center and vertical offset for sampling the nose gloss mask.
    public float _NoseGlossScale : packoffset(c26.w);
    /// Adjusts the start and end of the fluid's facing-dependent shadow band.
    public float _FluidShadowSize : packoffset(c27);
    /// Adds brightness to the fluid highlight in proportion to pigment value.
    public float _FluidHighlightPower : packoffset(c27.y);
    /// Threshold in light-facing space that controls the width of the fluid highlight.
    public float _FluidHighlightSize : packoffset(c27.z);
    /// Scales paint alpha before blending the shaded fluid onto the underlying skin.
    public float _FluidScale : packoffset(c27.w);
    /// Opacity of the view-dependent shadow tint in the skin pigment.
    public float _TestMatcapShade : packoffset(c28);
    /// Lower limit on color throughput as scattering increases with paint alpha.
    public float _FluidMinColorScale : packoffset(c28.y);
    /// Multiplier for the fluid's colored shadow relative to its transmitted pigment.
    public float _FluidShadowPower : packoffset(c28.z);
    /// Warp amplitude in paint texels, converted to normalized UV by the paint texel size.
    public float _Fluid_Noise_Amount : packoffset(c28.w);
    /// Blends the artist shadow pigment into the base pigment using local shade coverage.
    public float _BaseColorMix : packoffset(c29);
    /// Scales the spot pigment and detail-shadow channels of _spmap.
    public float _sppower : packoffset(c29.w);
    /// Scales blush from the expression map before applying its tint and opacity.
    public float _HohoakaIntensity : packoffset(c30);
    /// Adjusts the UV scale of cheek pigment independently of its highlight.
    public float _Cheek_size : packoffset(c30.y);
    /// Horizontal cheek pigment placement control. One unit offsets the UV center by 0.37.
    public float _Cheek_position_x : packoffset(c30.z);
    /// Vertical cheek pigment placement control. One unit offsets the UV center by -0.23.
    public float _Cheek_position_y : packoffset(c30.w);
    /// Rotation in turns subtracted from the base cheek pigment angle.
    public float _Cheek_rotation : packoffset(c31);
    /// Adjusts the UV scale of the blue cheek highlight channel.
    public float _CheekHighlight_size : packoffset(c31.y);
    /// Horizontal highlight placement control. One unit offsets the UV center by 0.4.
    public float _CheekHighlight_position_x : packoffset(c31.z);
    /// Vertical highlight placement control. One unit offsets the UV center by -0.27.
    public float _CheekHighlight_position_y : packoffset(c31.w);
    /// Rotation in turns subtracted from the base cheek highlight angle.
    public float _CheekHighlight_rotation : packoffset(c32);
    /// Rescales nose UV around the center and adjusts vertical placement.
    public float _NoseScale : packoffset(c32.y);
    /// Controls the blend from shaded pigment to the authored line RGB.
    public float _Line_power : packoffset(c32.z);
    /// Spatial frequency of the procedural UV warp in paint texture space.
    public float _Fluid_Noise_Scale : packoffset(c32.w);
    /// Gain of the key-light backscatter tint added to the lit skin.
    public float _TestSSS : packoffset(c33);
    /// Converts neighbor differences in paint alpha into tangent-space slope.
    public float _FluidNormalScale : packoffset(c33.y);
    /// Layer level for face liquid. The second pattern enters as the level rises above one.
    public float _liquidface : packoffset(c33.z);
    /// Fraction of the ordered 4×4 screen pattern allowed to pass, from zero to one.
    public float _Dither : packoffset(c33.w);
    /// Blend from the calculated shadow shade to _Shade_color.rgb.
    public float _UseShadowColor : packoffset(c34);
    /// Gain of the detail-dependent ramp offset outside the primary blue mask.
    public float _mdGShadeControle : packoffset(c34.y);
    /// Adjusts contrast of the detail shadow before it enters the palette.
    public float _mdGPower : packoffset(c34.z);
    /// Scales outline extrusion and the line coverage derived from the detail mask.
    public float _Line_width : packoffset(c34.w);
};
