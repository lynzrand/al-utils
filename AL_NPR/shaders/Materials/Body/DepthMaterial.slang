import Surface.DepthCoverage;
import Surface.Coverage;

/// Material properties at the serialized byte offsets for this pass.
public cbuffer UnityPerMaterial : register(b1)
{
    /// Normalized UV transform for _Cloth_alpha. XY scale and ZW offset before sampling.
    float4 _Cloth_alpha_ST : packoffset(c14);
    /// Fraction of the ordered 4×4 screen pattern allowed to pass, from zero to one.
    float _Dither : packoffset(c22.x);
    /// Rounded top-garment coverage switch used with the top and bottom clothing masks.
    float _alpha_a : packoffset(c22.y);
    /// Blends clothing-mask coordinates from transformed UV0 at zero to transformed UV2 at one.
    float _AlphaMaskuv : packoffset(c22.z);
    /// Rounded bottom-garment coverage switch used with the top and bottom clothing masks.
    float _alpha_b : packoffset(c28.x);
};

/// Reads the bottom garment mask at the UV selected by _AlphaMaskuv.
SamplerState bottomSampler : register(s0);
/// Reads the top garment mask at the UV selected by _AlphaMaskuv.
SamplerState topSampler : register(s1);
/// Bottom garment coverage. R and B pair with top B and R. G limits coverage.
Texture2D<float4> _Cloth_alpha_bot : register(t0);
/// Top garment coverage. R and B pair with bottom B and R. G limits coverage.
Texture2D<float4> _Cloth_alpha : register(t1);

/// Returns garment cutout times ordered dither. positionCS is in pixels and uv0Uv2 packs UV0 in XY and UV2 in
/// ZW.
public float bodyCoverage(float2 positionCS, float4 uv0Uv2)
{
    float4 uv = mad(uv0Uv2, _Cloth_alpha_ST.xyxy, _Cloth_alpha_ST.zwzw);
    float2 maskUV = mad(_AlphaMaskuv, uv.zw - uv.xy, uv.xy);
    float3 top = _Cloth_alpha.Sample(topSampler, maskUV).rgb;
    float3 bottom = _Cloth_alpha_bot.Sample(bottomSampler, maskUV).rgb;
    return float(coveredPixel(positionCS, _Dither)) * clothingMask(top, bottom, _alpha_a, _alpha_b);
}
