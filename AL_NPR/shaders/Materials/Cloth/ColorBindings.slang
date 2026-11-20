import Lighting.AmbientProbe;

/// Rasterizer interpolants for forward cloth shading and the colored outline.
public struct ClothInput
{
    /// Rasterized fragment position. XY are render-target pixel coordinates for light tiles and dithering.
    public float4 positionCS : SV_Position;
    /// Displaced world-space position in XYZ. W is zero.
    public float4 positionWS : TEXCOORD0;
    /// Interpolated world-space mesh normal used to reconstruct the shading basis.
    public float3 normalWS : TEXCOORD1;
    /// Interpolated world-space mesh tangent in XYZ and mirror-corrected handedness in W.
    public float4 tangentWS : TEXCOORD2;
    /// Reserved zero varying at TEXCOORD3 in the game's vertex-to-fragment signature.
    public float4 unused3 : TEXCOORD3;
    /// Reserved zero varying carried by the game's vertex-to-fragment signature.
    public float4 unused4 : TEXCOORD4;
    /// XY carries mesh UV0 and ZW carries mesh UV1. Color shading takes its base UV from XY.
    public float4 uv : TEXCOORD5;
    /// Mesh UV2 in XY for alternate garment coverage sampling. ZW is zero.
    public float4 maskUV : TEXCOORD6;
    /// Undeformed object-space mesh position. The original homogeneous W passes through the color varyings.
    public float4 positionOS : TEXCOORD7;
    /// Main light in object space. Its Y component displaces the material's rim direction.
    public float4 lightOS : TEXCOORD8;
    /// Mesh normal in object space before deformation.
    public float3 normalOS : NORMAL0;
    /// Rasterizer winding flag used to orient palette lighting and gate front-face rim effects.
    public bool frontFace : SV_IsFrontFace;
};

/// Per-pass camera, lighting, and render-target constants.
public cbuffer Globals : register(b0)
{
    /// XY holds the scaled render-target width and height in pixels for light tiles and dither coordinates.
    public float4 _ScaledScreenParams : packoffset(c3);
    /// X is the matcap mip bias. Nonzero Z enables alpha-to-coverage handling.
    public float4 mipAndAlpha : packoffset(c4);
    /// XYZ supplies the stock cloth key-light direction in world space.
    public float4 _MainLightPosition : packoffset(c5);
    /// RGB is the stock main light color used for the cloth palette.
    public float4 _MainLightColor : packoffset(c6);
    /// XY scales and biases view depth into a cluster bin. W gives the index after Unity's directional lights.
    public float4 _FPParams0 : packoffset(c15);
    /// XY scales normalized screen coordinates into tiles. Z is tiles per row and W is mask words per tile.
    public float4 _FPParams1 : packoffset(c16);
    /// X is the number of Forward+ depth bins.
    public float4 _FPParams2 : packoffset(c17);
    /// XYZ is the world-space camera position for view vectors, cluster depth, and outline distance fade.
    public float4 _WorldSpaceCameraPos : packoffset(c25);
    /// X is the projection flip sign used to orient the coverage dither pattern.
    public float4 _ProjectionParams : packoffset(c26);
    /// W is zero for perspective projection and nonzero for orthographic projection.
    public float4 unity_OrthoParams : packoffset(c29);
    /// X scales and Y offsets the normalized render-target Y coordinate before the final flip.
    public float4 _ScaleBiasRt : packoffset(c31);
    /// RGB provides the constant ambient term in dry and wet cloth highlights.
    public float4 glstate_lightmodel_ambient : packoffset(c59);
    /// X supplies the outline pass's fog blend, saturated before use.
    public float4 unity_FogParams : packoffset(c64);
    /// RGB is the fog color mixed into the lit outline.
    public float4 unity_FogColor : packoffset(c65);
    /// World-to-view column for the world X axis. Its Z component also contributes to view depth.
    public float4 viewX : packoffset(c70);
    /// World-to-view column for the world Y axis. Its Z component also contributes to view depth.
    public float4 viewY : packoffset(c71);
    /// World-to-view column for the world Z axis. Its Z component also contributes to view depth.
    public float4 viewZ : packoffset(c72);
};

/// Per-draw object origin, light layer, reflection decode, and ambient probe.
public cbuffer UnityPerDraw : register(b4)
{
    /// Object translation in world space. Distance to the camera fades outline dilation.
    public float4 objectOrigin : packoffset(c3);
    /// X carries a bit-packed layer mask for stock forward light selection.
    public float4 renderingLayer : packoffset(c10);
    /// X scales probe RGB, Y is the alpha exponent, and W controls use of encoded alpha.
    public float4 specCubeDecode : packoffset(c15);
    /// Seven consecutive Unity SH vectors for the per-draw diffuse ambient probe.
    public SHCoefficients probe : packoffset(c25);
};

/// Samples the reflection cubemap at the mip chosen by the garment finish.
public SamplerState samplerunity_SpecCube0 : register(s0);
#ifdef CLOTH_PREPASS
/// Samples red wet/sheer detail and blue outline detail from the first detail mask.
public SamplerState sampler_Detail_mask_01 : register(s1);
#else
/// Depth comparison sampler for the main and additional-light shadow maps.
public SamplerComparisonState shadowCompare1 : register(s1);
#endif
/// Samples fluid pigment and adjacent alpha heights at noise-offset fluid UVs.
public SamplerState sampler_FluidTex : register(s2);
/// Samples the garment normal at UV0 and again at transformed UVs for the wet sheen.
public SamplerState sampler_Normal_map : register(s3);
/// Samples the wet normal at the liquid UV used by the amount map.
public SamplerState sampler_LiquidBump : register(s4);
/// Samples liquid red/green amounts at the material’s liquid UV.
public SamplerState sampler_Liquid : register(s5);
/// Samples the three garment-region channels at transformed UV0.
public SamplerState sampler_liquidmask : register(s6);
/// Samples garment pigment with a mip bias and outline-center alpha with an explicit mip.
public SamplerState sampler_Create_main_texture : register(s7);
/// Samples the ordered dye-layer weights at transformed UV0.
public SamplerState sampler_ColorMask : register(s8);
/// Sampler state for the matcap texture array, including its gloss and metallic slices.
public SamplerState matcapSampler : register(s9);
/// Samples the texture that partitions the garment into matcap and finish regions.
public SamplerState sampler_Matcap_mask : register(s10);
#ifdef CLOTH_PREPASS
/// Samples the paired curvature and line controls from the second detail texture.
public SamplerState sampler_Detail_mask_02 : register(s11);
/// Samples the blue-channel lighting ramp along the texture diagonal.
public SamplerState sampler_Lamp : register(s12);
/// Samples the lower garment mask at the UV shared by both coverage masks.
public SamplerState sampler_Cloth_alpha_bot : register(s13);
/// Samples the upper garment mask at the UV shared by both coverage masks.
public SamplerState sampler_Cloth_alpha : register(s14);
#else
/// Samples red wet/sheer detail and blue outline detail from the first detail mask.
public SamplerState sampler_Detail_mask_01 : register(s11);
/// Samples the paired curvature and line controls from the second detail texture.
public SamplerState sampler_Detail_mask_02 : register(s12);
/// Samples the blue-channel lighting ramp along the texture diagonal.
public SamplerState sampler_Lamp : register(s13);
/// Samples the lower garment mask at the UV shared by both coverage masks.
public SamplerState sampler_Cloth_alpha_bot : register(s14);
/// Samples the upper garment mask at the UV shared by both coverage masks.
public SamplerState sampler_Cloth_alpha : register(s15);
#endif
/// RGB is fluid pigment. Alpha supplies layer coverage, scatter, and neighboring height differences.
public Texture2D<float4> _FluidTex : register(t0);
/// Packed tangent-space garment normal used for the base surface and the wet sheen.
public Texture2D<float4> _Normal_map : register(t1);
/// Red and green encode the two liquid amounts combined with the four garment region strengths.
public Texture2D<float4> _Liquid : register(t2);
/// RGB partitions garment regions for the wetness and sheerness calculations.
public Texture2D<float4> _liquidmask : register(t3);
/// Packed tangent-space normal for surface wetness, sampled with liquid UVs.
public Texture2D<float4> _LiquidBump : register(t4);
/// RGB is the undyed garment pigment. Alpha supplies silhouette and outline coverage.
public Texture2D<float4> _Create_main_texture : register(t5);
/// RGB selects dye layers 1, 2, and 3 over the default layer 4.
public Texture2D<float4> _ColorMask : register(t6);
/// RGB defines the first three matcap regions. The remainder forms the fourth.
public Texture2D<float4> _Matcap_mask : register(t7);
/// R modulates sheerness and wet detail, G controls finish and shadow detail, B controls outlines and cutoff, and A suppresses rim light.
public Texture2D<float4> _Detail_mask_01 : register(t8);
/// R blends toward the curvature tint. G weights the painted line.
public Texture2D<float4> _Detail_mask_02 : register(t9);
/// Blue is the cloth lighting ramp sampled along its diagonal.
public Texture2D<float4> _Lamp : register(t10);
/// Bottom garment coverage. Red and blue pair with opposite channels of the top mask, and green limits bottom coverage.
public Texture2D<float4> _Cloth_alpha_bot : register(t11);
/// Top garment coverage. Red and blue pair with opposite channels of the bottom mask, and green limits top coverage.
public Texture2D<float4> _Cloth_alpha : register(t12);
/// Unity's encoded environment reflection cubemap for dry and wet cloth.
public TextureCube<float4> unity_SpecCube0 : register(t13);
#ifdef CLOTH_PREPASS
/// Texture-array color layers use RGB and alpha. Slices 14 and 15 supply gloss and metallic masks through alpha.
public Texture2DArray<float4> _TexTAMatcap : register(t14);
#else
/// Main-light shadow depth sampled with the projected world position in stock forward shading.
public Texture2D<float4> _MainLightShadowmapTexture : register(t14);
/// Atlas of additional-light shadow depths sampled by the forward light loop.
public Texture2D<float4> _AdditionalLightsShadowmapTexture : register(t15);
/// Texture-array color layers use RGB and alpha. Slices 14 and 15 supply gloss and metallic masks through alpha.
public Texture2DArray<float4> _TexTAMatcap : register(t16);
#endif
