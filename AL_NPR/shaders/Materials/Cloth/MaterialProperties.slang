import Materials.Cloth.FabricOpacity;

/// Selects the opaque silhouette and render-target alpha rules for every pass of this material.
public typealias Fabric = OpaqueFabric;

#if defined(CLOTH_DEPTH_PASS)
/// Opaque cloth material properties at the active depth, outline, or forward binding.
public cbuffer UnityPerMaterial : register(b2)
#elif defined(CLOTH_PREPASS)
/// Opaque cloth material properties at the active depth, outline, or forward binding.
public cbuffer UnityPerMaterial : register(b5)
#else
/// Opaque cloth material properties at the active depth, outline, or forward binding.
public cbuffer UnityPerMaterial : register(b6)
#endif
{
    /// XY scales and ZW offsets UV0 for the wet-sheen normal sample. The base normal uses UV0 directly.
    public float4 _Normal_map_ST : packoffset(c0.x);
    /// RGB is the curvature tint. Alpha scales the red channel of the second detail mask when blending it into dry pigment.
    public float4 _Color_Cuvature : packoffset(c1.x);
    /// RGB dye selected by the color mask’s blue channel.
    public float4 _Main_color_03 : packoffset(c2.x);
    /// RGB dye selected by the color mask’s green channel.
    public float4 _Main_color_02 : packoffset(c3.x);
    /// XY scales and ZW offsets UV0 for the garment dye mask.
    public float4 _ColorMask_ST : packoffset(c4.x);
    /// RGB dye selected by the color mask’s red channel.
    public float4 _Main_color_01 : packoffset(c5.x);
    /// RGB dye used as the starting color before applying the three color-mask channels.
    public float4 _Main_color_04 : packoffset(c6.x);
    /// XY scales and ZW offsets UV0 for the wetness and sheerness region mask.
    public float4 _liquidmask_ST : packoffset(c8.x);
    /// XY is the UV offset and ZW the scale for the liquid amount and wet normal textures.
    public float4 _LiquidTiling : packoffset(c10.x);
    /// XY scales and ZW offsets UV0 for the red-channel detail sample used by wet and sheer shading.
    public float4 _Detail_mask_01_ST : packoffset(c11.x);
    /// XY is one fluid texel in UV units. The shader uses it for noise offsets and adjacent alpha-height samples.
    public float4 _FluidTex_TexelSize : packoffset(c12.x);
    /// XY scales and ZW offsets UV0 before fluid noise and height sampling.
    public float4 _FluidTex_ST : packoffset(c13.x);
    /// RGB supplies the material shadow tint blended by `_UseShadowColor`.
    public float4 _Shade_color : packoffset(c14.x);
    /// XY scales and ZW offsets both garment coverage UV sets before `_AlphaMaskuv` selects between them.
    public float4 _Cloth_alpha_ST : packoffset(c15.x);
    /// RGB outline pigment, mixed with the shaded surface according to `_Line_power`.
    public float3 _Line_color : packoffset(c16.x);
    /// Scales the first detail mask's adjusted green channel for palette shading and additive light.
    public float _mdGIntensity : packoffset(c16.w);
    /// Offset to fluid hue-space saturation when building its shaded tint.
    public float _FluidShadowSaturation : packoffset(c17.x);
    /// Blend from fluid texture RGB toward wet garment pigment before fluid lighting.
    public float _FluidTransmittance : packoffset(c17.y);
    /// Controls how rapidly increasing fluid alpha drives the scattering multiplier from one toward its minimum.
    public float _FluidColorScatter : packoffset(c17.z);
    /// Color multiplier approached as fluid alpha times the scatter strength increases.
    public float _FluidMinColorScale : packoffset(c17.w);
    /// Scales suppression of the rim by the first detail mask's green and alpha channels.
    public float _RimMaskIntensity : packoffset(c18.y);
    /// Strength of the primary rim and one of the limits on the additive rim.
    public float _TestRim : packoffset(c18.z);
    /// Sheer-effect blend for the wet normal. Cutout fabric also uses it to reduce dry opacity.
    public float _sukeONOFF : packoffset(c18.w);
    /// Scales the shift of the lamp texture coordinate by shadow detail and shadow power.
    public float _mdGShadeControle : packoffset(c19.x);
    /// Scales the pigment tint applied to the base color in shadow-detail regions.
    public float _BaseColorMix : packoffset(c19.y);
    /// Adjusts the denominator applied to the detail mask's green channel for palette shading.
    public float _mdGPower : packoffset(c19.z);
    /// Scales the difference between the fluid pigment and its shadow tint.
    public float _FluidShadowPower : packoffset(c19.w);
    /// Controls the shadow ramp shift and the minimum mix back toward white.
    public float _Shadow_power : packoffset(c20.x);
    /// Blends the computed palette shadow toward `_Shade_color.rgb`.
    public float _UseShadowColor : packoffset(c20.y);
    /// Detail-mask sheerness strength in the back lower garment region.
    public float _sukebbot : packoffset(c20.z);
    /// Shifts the edges of the shadow band on the fluid layer.
    public float _FluidShadowSize : packoffset(c20.w);
    /// Secondary rim strength. Also limits the additive rim together with `_TestRim`.
    public float _TestRimSub : packoffset(c21.x);
    /// Sets the transition from the fluid shadow band to its highlight.
    public float _FluidHighlightSize : packoffset(c21.y);
    /// Blends between mesh UV0 and UV2 when sampling both garment coverage masks.
    public float _AlphaMaskuv : packoffset(c21.z);
    /// Rounded switch for the top garment in the paired coverage masks.
    public float _alpha_a : packoffset(c21.w);
    /// Additional opacity multiplier for the colored outline pass.
    public float _alpha2 : packoffset(c22.x);
    /// Global garment opacity multiplier applied after alpha dithering.
    public float _alpha : packoffset(c22.y);
    /// Blends continuous opacity toward the ordered dither result.
    public float _AlphaDither : packoffset(c22.z);
    /// Additional whole-garment coverage gate compared to the pixel's dither threshold.
    public float _Dither : packoffset(c22.w);
    /// Blends the lit, lined garment color back toward dry pigment.
    public float _LightCancel : packoffset(c23.z);
    /// Scales the outline's contribution to color and silhouette coverage.
    public float _AlphaLine : packoffset(c23.w);
    /// Controls the blend from shaded pigment toward the authored line color.
    public float _Line_power : packoffset(c24.x);
    /// Final material weight for the backlighting term.
    public float _TestSSS : packoffset(c24.y);
    /// Scales the tinted light transmitted through the cloth.
    public float _SSSIntensity : packoffset(c24.z);
    /// Moves the backlighting threshold used to estimate cloth transmission.
    public float _SSSForce : packoffset(c24.w);
    /// Scales the front-face grazing highlight added to the primary rim.
    public float _AddRimIntensity : packoffset(c25.x);
    /// Detail-mask sheerness strength in the back upper garment region.
    public float _sukebtop : packoffset(c25.y);
    /// Scales the pigment overlay by pigment contrast and brightness.
    public float _TestOC : packoffset(c25.z);
    /// Blends in probe-tinted shading around the view rim.
    public float _TestMatcapShade : packoffset(c25.w);
    /// Scales fluid alpha when mixing the fluid layer over wet pigment.
    public float _FluidScale : packoffset(c26.x);
    /// Scales the brightening term derived from the fluid pigment's value.
    public float _FluidHighlightPower : packoffset(c26.y);
    /// Detail-mask sheerness strength in the front lower garment region.
    public float _sukefbot : packoffset(c26.z);
    /// Bias applied to the first detail mask's red channel before regional sheerness weights.
    public float _SukeOffset : packoffset(c27.x);
    /// Blends overlapping matcap mask channels toward exclusive color-layer regions.
    public float _MaskOverride : packoffset(c27.y);
    /// Matcap texture-array slice sampled for color layer 1.
    public float _MatcapIndex1 : packoffset(c27.z);
    /// Matcap texture-array slice sampled for color layer 2.
    public float _MatcapIndex2 : packoffset(c27.w);
    /// Matcap texture-array slice sampled for color layer 3.
    public float _MatcapIndex3 : packoffset(c28.x);
    /// Matcap texture-array slice sampled for color layer 4.
    public float _MatcapIndex4 : packoffset(c28.y);
    /// Explicit mip for the outline center and mip bias for the garment texture and outline neighbors.
    public float _Mip : packoffset(c28.z);
    /// Nonzero enables RGB dye multiplication from the color mask.
    public float _Main_color_switchtest : packoffset(c28.w);
    /// Liquid texture strength in the back lower garment region.
    public float _liquidbbot : packoffset(c29.x);
    /// Liquid texture strength in the back upper garment region.
    public float _liquidbtop : packoffset(c29.y);
    /// Liquid texture strength in the front lower garment region.
    public float _liquidfbot : packoffset(c29.z);
    /// Liquid texture strength in the front upper garment region.
    public float _liquidftop : packoffset(c29.w);
    /// Strength of the base garment normal decoded from the normal map.
    public float _BumpMapScale : packoffset(c30.x);
    /// Scales X/Y differences between adjacent fluid alpha samples to form the fluid normal.
    public float _FluidNormalScale : packoffset(c30.y);
    /// Amplitude of the fluid UV noise offset, in fluid texels.
    public float _Fluid_Noise_Amount : packoffset(c30.z);
    /// Frequency multiplier applied to fluid UVs before evaluating noise.
    public float _Fluid_Noise_Scale : packoffset(c30.w);
    /// Multiplier on the authored outline width, shared by extrusion, pigment, and alpha dilation.
    public float _LineWidthS : packoffset(c31.z);
    /// Authored outline width before multiplying by `_LineWidthS` and the detail mask.
    public float _Line_width : packoffset(c31.w);
    /// Controls the overlay and desaturation from matcap color layer 1.
    public float _Matcap_power_01 : packoffset(c32.x);
    /// Controls the overlay and desaturation from matcap color layer 2.
    public float _Matcap_power_02 : packoffset(c32.y);
    /// Controls the overlay and desaturation from matcap color layer 3.
    public float _Matcap_power_03 : packoffset(c32.z);
    /// Controls the overlay and desaturation from matcap color layer 4.
    public float _Matcap_power_04 : packoffset(c32.w);
    /// Gain applied to red detail before adding `_SukeOffset` and selecting sheer regions.
    public float _SukeScale : packoffset(c33.x);
    /// Scales detail-height differences to tilt the sheer normal.
    public float _SukeNormalPower : packoffset(c33.y);
    /// Controls the UV step for the sheer height gradient. The shader cubes it before sampling.
    public float _SukeNormalLength : packoffset(c33.z);
    /// Strength of the normal map in the wet sheen calculation.
    public float _NureNormalPower : packoffset(c33.w);
    /// Rounded switch for the bottom garment in the paired coverage masks.
    public float _alpha_b : packoffset(c34.x);
    /// Sets the minimum wet-sheen region weight and darkens the wet-detail tint.
    public float _AseIntensity : packoffset(c34.y);
    /// Wet sheen and wet normal strength in the back lower garment region.
    public float _nurebbot : packoffset(c34.z);
    /// Wet sheen and wet normal strength in the back upper garment region.
    public float _nurebtop : packoffset(c34.w);
    /// Wet sheen and wet normal strength in the front lower garment region.
    public float _nurefbot : packoffset(c35.x);
    /// Detail-mask sheerness strength in the front upper garment region.
    public float _sukeftop : packoffset(c35.y);
    /// Wet sheen and wet normal strength in the front upper garment region.
    public float _nureftop : packoffset(c35.z);
    /// Weight of metallic matcap slice 15 alpha in finish region 3.
    public float _Metallic_power_03 : packoffset(c35.w);
    /// Weight of metallic matcap slice 15 alpha in finish region 2.
    public float _Metallic_power_02 : packoffset(c36.x);
    /// Weight of metallic matcap slice 15 alpha in finish region 1.
    public float _Metallic_power_01 : packoffset(c36.y);
    /// Blends the matcap region mask toward exclusive regions for gloss and metallic response.
    public float _MaskOverrideGloss : packoffset(c36.z);
    /// Weight of gloss matcap slice 14 alpha in finish region 4.
    public float _Gloss_power_04 : packoffset(c36.w);
    /// Weight of gloss matcap slice 14 alpha in finish region 3.
    public float _Gloss_power_03 : packoffset(c37.x);
    /// Weight of gloss matcap slice 14 alpha in finish region 2.
    public float _Gloss_power_02 : packoffset(c37.y);
    /// Weight of gloss matcap slice 14 alpha in finish region 1.
    public float _Gloss_power_01 : packoffset(c37.z);
    /// Blends from dyed pigment to the result of the four matcap color layers.
    public float _Matcaponoff : packoffset(c37.w);
    /// Weight of metallic matcap slice 15 alpha in finish region 4.
    public float _Metallic_power_04 : packoffset(c38.x);
    /// For detail blue at or above 0.7, blends the material alpha cutoff toward 0.999.
    public float _AlphaClipForce : packoffset(c38.y);
    /// Base garment cutoff, clamped to [0.011, 1] before the detail adjustment.
    public float _AlphaClip : packoffset(c38.z);
};
