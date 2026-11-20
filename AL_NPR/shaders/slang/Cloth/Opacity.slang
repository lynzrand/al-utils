// Dilate the alpha silhouette by one texel neighborhood near the camera.
// The center sample uses an explicit mip, while the neighbors use a mip bias.
float clothOutlineOpacity(float baseAlpha, float2 uv, float detail, float distanceFade)
{
    float lineWidth = ((1 - detail) * _Line_width) * _LineWidthS;
    float radius = lineWidth * distanceFade;
    float offset = clamp(radius, 0, 0.6) * 0.0007;
    float center = _Create_main_texture.SampleLevel(sampler_Create_main_texture, uv, _Mip).a;
    float peak = center;
    [unroll] for (int y = -1; y <= 1; ++y)
        [unroll] for (int x = -1; x <= 1; ++x)
            if (x != 0 || y != 0)
                peak = max(peak, _Create_main_texture.SampleBias(
                    sampler_Create_main_texture, mad(float2(x, y), offset, uv), _Mip).a);
    float dilated = lerp(center, saturate((peak - 0.3) * 2.5), saturate(radius * 2));
    return lerp(baseAlpha, dilated, saturate(lineWidth * 4) * _AlphaLine);
}

float maskedClothOpacity(float opacity, float4 uv, float threshold, bool suppressSpecks)
{
    float binaryAlpha = passesDither(opacity, threshold) ? 1 : 0;
    opacity = min(opacity, lerp(opacity, binaryAlpha, _AlphaDither)) * _alpha;
    opacity = min(opacity, passesDither(_Dither, threshold) ? 1 : 0);
    if (suppressSpecks)
        opacity = min(opacity, ceil(opacity - 0.009));

    float4 maskUVs = mad(uv, _Cloth_alpha_ST.xyxy, _Cloth_alpha_ST.zwzw);
    float2 maskUV = lerp(maskUVs.xy, maskUVs.zw, _AlphaMaskuv);
    float3 top = _Cloth_alpha.Sample(sampler_Cloth_alpha, maskUV).rgb;
    float3 bottom = _Cloth_alpha_bot.Sample(sampler_Cloth_alpha_bot, maskUV).rgb;
    return opacity * clothingMask(top, bottom, _alpha_a, _alpha_b);
}

float garmentOpacity(float4 base, float2 uv, float detail, float distanceFade, float wetness, float sheer)
{
    float opacity = clothOutlineOpacity(base.a, uv, detail, distanceFade);
#ifdef CLOTH_CUTOUT
    float luma = saturate(mad(dot(base.rgb, float3(0.299, 0.587, 0.114)), 0.6, 0.4));
    opacity = saturate(mad(-_sukeONOFF, luma * sqrt(sheer), opacity));
#endif
    return max(opacity, smoothstep(0.3, 1, base.a) * smoothstep(0.01, 0.7, wetness));
}

float clothCutoff(float detail)
{
    float cutoff = clamp(_AlphaClip, 0.011, 1);
    return mad(detail >= 0.7 ? _AlphaClipForce : 0, 0.999 - cutoff, cutoff);
}
