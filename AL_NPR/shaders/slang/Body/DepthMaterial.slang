import DepthCoverage;
import Coverage;

cbuffer UnityPerMaterial : register(b1)
{
    float4 _Cloth_alpha_ST : packoffset(c14);
    float _Dither : packoffset(c22.x);
    float _alpha_a : packoffset(c22.y);
    float _AlphaMaskuv : packoffset(c22.z);
    float _alpha_b : packoffset(c28.x);
};

SamplerState bottomSampler : register(s0);
SamplerState topSampler : register(s1);
Texture2D<float4> _Cloth_alpha_bot : register(t0);
Texture2D<float4> _Cloth_alpha : register(t1);

float bodyCoverage(float2 positionCS, float4 uv0Uv2)
{
    float4 uv = mad(uv0Uv2, _Cloth_alpha_ST.xyxy, _Cloth_alpha_ST.zwzw);
    float2 maskUV = mad(_AlphaMaskuv, uv.zw - uv.xy, uv.xy);
    float3 top = _Cloth_alpha.Sample(topSampler, maskUV).rgb;
    float3 bottom = _Cloth_alpha_bot.Sample(bottomSampler, maskUV).rgb;
    return float(coveredPixel(positionCS, _Dither)) * clothingMask(top, bottom, _alpha_a, _alpha_b);
}
