import Lighting.AmbientProbe;

/// Interpolated inputs shared by the hair base and Forward color passes.
public struct HairInput
{
    /// Pixel coordinates in XY for the ordered 4 × 4 coverage test and Forward+ tile lookup.
    public float4 positionCS : SV_POSITION;
    /// XYZ is the world-space surface position used to find lights and project into shadow atlases.
    public float4 positionWS : TEXCOORD0;
    /// Interpolated world-space mesh normal before the strand normal map.
    public float3 normalWS : TEXCOORD1;
    /// XYZ is the world-space strand tangent. W gives the sign used to reconstruct the bitangent.
    public float4 tangentWS : TEXCOORD2;
    /// Reserved TEXCOORD3 varying. The stock hair base vertex stage writes zero.
    public float4 unused3 : TEXCOORD3;
    /// Reserved TEXCOORD4 varying. The stock hair base vertex stage writes zero.
    public float4 unused4 : TEXCOORD4;
    /// XY contains mesh UV1 for strand normals and painted highlights. ZW contains UV0 for pigment, detail,
    /// and wetness.
    public float4 uv1Uv0 : TEXCOORD5;
    /// XYZ is the main light transformed into object space. Hair uses Y to lift the rim.
    public float4 mainLightOS : TEXCOORD6;
    /// Original mesh normal in object space, retained for the elevation-dependent rim exponent.
    public float3 normalOS : NORMAL0;
    /// Object-space mesh position. Y and Z select the four wet-hair regions.
    public float4 positionOS : TEXCOORD7;
    /// Rasterizer winding flag used to orient the key and limit the outer rim to front faces.
    public bool frontFace : SV_IsFrontFace;
};

/// Unity camera and lighting constants for the two hair color passes.
public cbuffer Globals : register(b0)
{
    /// Scaled render-target width and height in pixels.
    public float2 screenSize : packoffset(c3);
    /// Nonzero selects the derivative-based coverage clip used with alpha-to-coverage.
    public float alphaToMaskAvailable : packoffset(c4.z);
    /// Unity's main light vector. The color passes use its XYZ direction in world space.
    public float4 mainLightDirection : packoffset(c5);
    /// RGB main-light radiance used by the key, palette, and wet highlights.
    public float4 mainLightColor : packoffset(c6);
    /// X and Y scale and offset the Z-bin coordinate. W counts leading additional directionals.
    public float4 fp0 : packoffset(c15);
    /// XY scales screen UV to tile coordinates. Z counts tiles per row and W counts mask words per tile.
    public float4 fp1 : packoffset(c16);
    /// X counts depth bins in the active camera's Forward+ grid.
    public float4 fp2 : packoffset(c17);
    /// XYZ is the camera's world position, used to form the surface-to-eye vector.
    public float4 cameraPosition : packoffset(c25);
    /// Negative when the projection flips vertically. Sets the Bayer pattern orientation.
    public float projectionSign : packoffset(c26);
    /// Zero selects perspective view and logarithmic depth bins. Nonzero selects orthographic view and linear
    /// bins.
    public float orthographic : packoffset(c29.w);
    /// X scales and Y biases the normalized vertical coordinate before its render-target flip.
    public float2 screenScaleBias : packoffset(c31);
    /// RGB ambient term added to the wet hair's diffuse response.
    public float4 ambientColor : packoffset(c59);
    /// View transform column for world X. XYZ orients the painted stripe and Z contributes to view depth.
    public float4 viewX : packoffset(c70);
    /// View transform column for world Y. XYZ orients the painted stripe and Z contributes to view depth.
    public float4 viewY : packoffset(c71);
    /// View transform column for world Z. XYZ orients the painted stripe and Z contributes to view depth.
    public float4 viewZ : packoffset(c72);
};

/// Per-renderer light-layer and probe inputs shared across the hair material's color draws.
public cbuffer UnityPerDraw : register(b4)
{
    /// X holds the renderer's light-layer mask as raw uint bits in a float lane.
    public float4 renderingLayer : packoffset(c10);
    /// Reflection-probe decode parameters. X scales RGB, Y is the exponent, and W controls encoded-alpha use.
    public float4 cubeDecode : packoffset(c15);
    /// Renderer's spherical-harmonic lighting coefficients for ambient palette and highlight colors.
    public SHCoefficients probe : packoffset(c25);
};

// The stock base pass has no shadow atlas and binds the material one slot earlier.
#ifdef HAIR_STOCK_BASE
/// Hair material constants. The stock base pass binds these at b5 and the other color passes at b6.
public cbuffer UnityPerMaterial : register(b5)
#else
/// Hair material constants. The stock base pass binds these at b5 and the other color passes at b6.
public cbuffer UnityPerMaterial : register(b6)
#endif
{
    /// RGB secondary dye. A scales the green color-mask channel.
    public float4 _Sub_color_02 : packoffset(c0);
    /// RGB skin tint. A scales the blue channel of detail mask 2.
    public float4 _Add_skin_color : packoffset(c1);
    /// RGB secondary dye. A scales the blue color-mask channel.
    public float4 _Sub_color_01 : packoffset(c2);
    /// UV0 scale in XY and offset in ZW for the four-channel dye mask.
    public float4 _Hair_color_mask_ST : packoffset(c3);
    /// RGB starting pigment before dyes, skin tint, and extra colors.
    public float4 _Main_color : packoffset(c4);
    /// UV0 scale in XY and offset in ZW for the wetness mask.
    public float4 _Sampler302397_g100057_ST : packoffset(c5);
    /// UV0 scale in XY and offset in ZW for detail mask 2.
    public float4 _md_02_ST : packoffset(c6);
    /// RGB extra dye. A weights its blend through the inverted, shaped alpha color mask.
    public float4 _Ex_hair_color2 : packoffset(c7);
    /// UV0 scale in XY and offset in ZW for detail mask 1.
    public float4 _md_01_ST : packoffset(c8);
    /// RGB extra dye. A weights its blend through the red color mask.
    public float4 _Ex_hair_color : packoffset(c9);
    /// RGB secondary stripe tint. A scales the secondary stripe and its shadow.
    public float4 _Highlight_color02 : packoffset(c10);
    /// RGB primary stripe and scene-reflection tint. A controls their strength.
    public float4 _Highlight_color01 : packoffset(c11);
    /// RGB authored shadow pigment for the ramp, painted stripes, and material tint.
    public float4 _Shadow_color : packoffset(c12);
    /// UV0 scale in XY and offset in ZW for the wet normal map.
    public float4 _Sampler345397_g100057_ST : packoffset(c13);
    /// Strength of the tangent-space wet normal perturbation.
    public float _NureNormalPower : packoffset(c14.x);
    /// Gain for the backlit transmission contribution through the hair.
    public float _TestSSS : packoffset(c14.y);
    /// Strength of the secondary silhouette rim, capped by the primary rim gain.
    public float _TestRimSub : packoffset(c14.z);
    /// Strength of the grazing-angle suppression applied to the painted stripe.
    public float _Intensity1 : packoffset(c14.w);
    /// Exponent shaping the grazing-angle suppression of the painted stripe.
    public float _Intensity2 : packoffset(c15.x);
    /// Intensity multiplier for the secondary highlight in the green painted-stripe channel.
    public float _HairHigh2Multiply : packoffset(c15.y);
    /// Wet-mask gain in the intersection of the front and upper object-space regions.
    public float _nureftop : packoffset(c15.z);
    /// Wet-mask gain in the front region outside the upper region.
    public float _nurefbot : packoffset(c15.w);
    /// Blend weight for the view-dependent ambient shading of the strand pigment.
    public float _TestMatcapShade : packoffset(c16.x);
    /// Wet-mask gain outside both the front and upper regions.
    public float _nurebbot : packoffset(c16.y);
    /// Gain for sweat darkening, wet probe reflection, and the wet specular response.
    public float _AseIntensity : packoffset(c16.z);
    /// Wet-mask gain in the upper region outside the front region.
    public float _nurebtop : packoffset(c17.x);
    /// Scales the vertical painted-stripe offset from the tangent-space view direction.
    public float _hilightmove : packoffset(c17.y);
    /// Nonzero enables the extra dye driven by the color mask's alpha channel.
    public float _Ex_hair_color2_onoff : packoffset(c17.z);
    /// Nonzero enables the extra dye driven by the red color mask.
    public float _Ex_hair_color_onoff : packoffset(c17.w);
    /// Strength of rim suppression from the detail masks.
    public float _RimMaskIntensity : packoffset(c18.x);
    /// Shapes the green detail-mask contribution to rim suppression.
    public float _RimMaskPowermdG : packoffset(c18.y);
    /// Primary silhouette rim strength and ceiling for the secondary rim gain.
    public float _TestRim : packoffset(c18.z);
    /// Controls the ramp offset and minimum brightness of the shadow tint.
    public float _Shadow_power : packoffset(c18.w);
    /// Strength of the painted shade from the green channel of detail mask 1.
    public float _mdGIntensity : packoffset(c19.x);
    /// Changes the contrast of the painted shade in detail mask 1.
    public float _mdGPower : packoffset(c19.y);
    /// Strength of shadow-pigment mixing under the detail and grazing masks.
    public float _BaseColorMix : packoffset(c19.z);
    /// Strength of the negative ramp coordinate offset from the material's shade mask.
    public float _mdGShadeControle : packoffset(c19.w);
    /// Blend from ambient-derived shadow tint to the authored RGB shadow color.
    public float _ShadowColorControle : packoffset(c20.x);
    /// Changes the vertical stretch and origin of the painted-stripe lookup.
    public float _LightLength : packoffset(c20.y);
    /// Scales the horizontal shift of the painted stripe with tangent-space view X.
    public float _hilightmove2 : packoffset(c20.z);
    /// Adds a vertical offset to the painted stripe before sampling the highlight texture.
    public float _hilightmove3 : packoffset(c20.w);
    /// Material opacity tested against the screen-space Bayer threshold.
    public float _Dither : packoffset(c21.x);
    /// Forward tip opacity, saturated and floored at 0.01 for surviving dither samples.
    public float _TipAlpha : packoffset(c21.y);
};

/// Strand normal texture sampled with UV1. X is encoded in red times alpha and Y in green.
public Texture2D<float4> normalMap : register(t0);
/// UV1 stripe texture. R and G shape primary and secondary lobes, B shapes stripe shadow. The scene reflection
/// samples R.
public Texture2D<float4> paintedHighlight : register(t1);
/// Green drives detail shade and rim suppression.
public Texture2D<float4> detailMask1 : register(t2);
/// Blue stores the shadow weight sampled along the diagonal at the computed lighting coordinate.
public Texture2D<float4> toonRamp : register(t3);
/// R masks highlights, G suppresses rim, and B blends in the skin tint.
public Texture2D<float4> detailMask2 : register(t4);
/// R selects extra dye, G/B select the two secondary dyes, and A shapes the second extra dye.
public Texture2D<float4> colorMask : register(t5);
/// Red gives the maximum textured wetness used by each of the four region controls.
public Texture2D<float4> wetMask : register(t6);
/// Wet tangent-space normal sampled with transformed UV0.
public Texture2D<float4> wetNormalMap : register(t7);
/// Renderer reflection probe sampled along the wet reflected view direction.
public TextureCube<float4> environmentCube : register(t8);
/// Sampler used for the reflection cube's explicit mip lookup.
public SamplerState environmentCubeSampler : register(s0);

#ifdef HAIR_STOCK_BASE
/// Sampler for the UV1 strand normal.
public SamplerState normalMapSampler : register(s1);
/// Sampler for the painted-stripe texture, including its explicit-gradient lookups inside light loops.
public SamplerState paintedHighlightSampler : register(s2);
/// Sampler for the UV0 detail shade mask.
public SamplerState detailMask1Sampler : register(s3);
/// Sampler for the diagonal toon-ramp lookup.
public SamplerState toonRampSampler : register(s4);
/// Sampler for the UV0 highlight, rim, and skin-tint masks.
public SamplerState detailMask2Sampler : register(s5);
/// Sampler for the four-channel dye mask.
public SamplerState colorMaskSampler : register(s6);
/// Sampler for the regional wetness mask.
public SamplerState wetMaskSampler : register(s7);
/// Sampler for the wet tangent-space normal map.
public SamplerState wetNormalMapSampler : register(s8);
#else
/// Main-light cascade depth atlas sampled in projected shadow coordinates.
public Texture2D<float4> mainShadowAtlas : register(t9);
/// Depth atlas shared by additional spot lights and point-light faces.
public Texture2D<float4> additionalShadowAtlas : register(t10);
/// Hardware depth-comparison sampler for the main and additional shadow atlases.
public SamplerComparisonState shadowCompare : register(s1);
/// Sampler for the UV1 strand normal.
public SamplerState normalMapSampler : register(s2);
/// Sampler for the painted-stripe texture, including its explicit-gradient lookups inside light loops.
public SamplerState paintedHighlightSampler : register(s3);
/// Sampler for the UV0 detail shade mask.
public SamplerState detailMask1Sampler : register(s4);
/// Sampler for the diagonal toon-ramp lookup.
public SamplerState toonRampSampler : register(s5);
/// Sampler for the UV0 highlight, rim, and skin-tint masks.
public SamplerState detailMask2Sampler : register(s6);
/// Sampler for the four-channel dye mask.
public SamplerState colorMaskSampler : register(s7);
/// Sampler for the regional wetness mask.
public SamplerState wetMaskSampler : register(s8);
/// Sampler for the wet tangent-space normal map.
public SamplerState wetNormalMapSampler : register(s9);
#endif
