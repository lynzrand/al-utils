/// Camera and render-target values for clipping the depth or shadow silhouette.
public cbuffer Globals : register(b0)
{
    /// Render-target width and height in pixels for the ordered coverage dither.
    public float2 screenSize : packoffset(c3);
    /// Nonzero enables the derivative-adjusted alpha-to-coverage cutoff in depth and shadow passes.
    public float alphaToMask : packoffset(c4.z);
    /// World-space camera position for the outline coverage fade.
    public float3 cameraPosition : packoffset(c21);
    /// Projection flip sign used to orient the dither pattern on this render target.
    public float projectionSign : packoffset(c22);
    /// X scales and Y offsets normalized render-target Y before evaluating the dither cell.
    public float2 targetScaleBias : packoffset(c27);
};

/// Per-draw object origin for distance-scaled silhouette coverage.
public cbuffer UnityPerDraw : register(b1)
{
    /// Object translation in world space. Distance to the camera fades outline dilation.
    public float3 objectOrigin : packoffset(c3);
};

/// Samples garment pigment with a mip bias and outline-center alpha with an explicit mip.
public SamplerState sampler_Create_main_texture : register(s0);
/// Samples red wet/sheer detail and blue outline detail from the first detail mask.
public SamplerState sampler_Detail_mask_01 : register(s1);
/// Samples the three garment-region channels at transformed UV0.
public SamplerState sampler_liquidmask : register(s3);
/// RGB is the undyed garment pigment. Alpha supplies silhouette and outline coverage.
public Texture2D<float4> _Create_main_texture : register(t0);
/// R modulates sheerness and wet detail, G controls finish and shadow detail, B controls outlines and cutoff, and A suppresses rim light.
public Texture2D<float4> _Detail_mask_01 : register(t1);
/// RGB partitions garment regions for the wetness and sheerness calculations.
public Texture2D<float4> _liquidmask : register(t3);

// Cutout depth and shadow passes also bind the authored dye mask.
#ifdef CLOTH_CUTOUT_LAYOUT
/// Samples the ordered dye-layer weights at transformed UV0.
public SamplerState sampler_ColorMask : register(s2);
/// Samples liquid red/green amounts at the material’s liquid UV.
public SamplerState sampler_Liquid : register(s4);
/// Samples the lower garment mask at the UV shared by both coverage masks.
public SamplerState sampler_Cloth_alpha_bot : register(s5);
/// Samples the upper garment mask at the UV shared by both coverage masks.
public SamplerState sampler_Cloth_alpha : register(s6);
/// RGB selects dye layers 1, 2, and 3 over the default layer 4.
public Texture2D<float4> _ColorMask : register(t2);
/// Red and green encode the two liquid amounts combined with the four garment region strengths.
public Texture2D<float4> _Liquid : register(t4);
/// Bottom garment coverage. Red and blue pair with opposite channels of the top mask, and green limits bottom coverage.
public Texture2D<float4> _Cloth_alpha_bot : register(t5);
/// Top garment coverage. Red and blue pair with opposite channels of the bottom mask, and green limits top coverage.
public Texture2D<float4> _Cloth_alpha : register(t6);
#else
/// Samples liquid red/green amounts at the material’s liquid UV.
public SamplerState sampler_Liquid : register(s2);
/// Samples the lower garment mask at the UV shared by both coverage masks.
public SamplerState sampler_Cloth_alpha_bot : register(s4);
/// Samples the upper garment mask at the UV shared by both coverage masks.
public SamplerState sampler_Cloth_alpha : register(s5);
/// Red and green encode the two liquid amounts combined with the four garment region strengths.
public Texture2D<float4> _Liquid : register(t2);
/// Bottom garment coverage. Red and blue pair with opposite channels of the top mask, and green limits bottom coverage.
public Texture2D<float4> _Cloth_alpha_bot : register(t4);
/// Top garment coverage. Red and blue pair with opposite channels of the bottom mask, and green limits top coverage.
public Texture2D<float4> _Cloth_alpha : register(t5);
#endif
