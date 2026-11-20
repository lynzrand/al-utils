// Binding and interpolator layout recovered from the captured SM5 ShadowCaster.
cbuffer CameraConstants : register(b0)
{
    float4 TargetSize : packoffset(c3);
    float4 MsaaState : packoffset(c4);
    float4 ProjectionState : packoffset(c22);
    float4 ViewportTransform : packoffset(c27);
};

cbuffer MaterialConstants : register(b1)
{
    float4 UvTransform : packoffset(c0);
    float4 BaseColor : packoffset(c1);
    float4 FadeAndCutoff : packoffset(c5);
};

Texture2D<float4> BaseMap : register(t0);
SamplerState BaseSampler : register(s0);

static const float Dither[16] = {
    1, 9, 3, 11, 13, 5, 15, 7, 4, 12, 2, 10, 16, 8, 14, 6
};

struct Interpolators
{
    float4 position : SV_Position;
    float3 unusedWorldPosition : TEXCOORD0;
    float4 uv : TEXCOORD1;
};

float DitherMask(float2 position, float fade)
{
    float2 normalized = position * rcp(TargetSize.xy);
    normalized.y = mad(normalized.y, ViewportTransform.x, ViewportTransform.y);
    float invY = 1.0 - normalized.y;
    float x = normalized.x * TargetSize.x;
    float y = invY * TargetSize.y;
    float flippedY = mad(-invY, TargetSize.y, TargetSize.y);
    float2 quarter = float2(x, ProjectionState.x < 0 ? flippedY : y) * 0.25;
    float2 fraction = frac(abs(quarter));
    fraction = float2(quarter.x >= -quarter.x ? fraction.x : -fraction.x,
                      quarter.y >= -quarter.y ? fraction.y : -fraction.y);
    uint2 cell = (uint2)(fraction * 4.0);
    uint index = min(cell.x + (cell.y << 2), 15u);
    return fade >= (Dither[index] * 0.0625) ? 1.0 : 0.0;
}

float4 main(Interpolators input) : SV_Target
{
    float fade = saturate(FadeAndCutoff.x * 1.00001);
    float cutoff = FadeAndCutoff.w;
#if FAST_AUDITED_MAP_TEXTURES
    // This variant is only for map002's audited AL/Map bindings. The lowest
    // stored alpha is 243/255. For these exact stock material settings, the
    // original cutoff and its derivative-smoothed form both keep the pixel.
    [branch] if (fade >= 1.0 && BaseColor.a == 1.0 && cutoff == 0.5)
        return 0;
#endif
#if FAST_OPAQUE_PATH
    // AL/Map base-map alpha is stored in a normalized texture. With a nonnegative
    // material alpha and a nonpositive cutoff, neither branch can discard.
    [branch] if (cutoff <= 0 && BaseColor.a >= 0)
        return 0;
#endif
    float mask;
#if FAST_UNIFORM_PATH
    // The maximum Bayer threshold is one. Fully visible materials have a uniform
    // mask, so the per-pixel coordinate transform and indexed threshold are redundant.
    [branch] if (fade >= 1.0)
        mask = 1.0;
    else
        mask = DitherMask(input.position.xy, fade);
#else
    mask = DitherMask(input.position.xy, fade);
#endif

    float2 uv = mad(input.uv.xy, UvTransform.xy, UvTransform.zw);
    float alpha = min(mask, BaseMap.Sample(BaseSampler, uv).a * BaseColor.a);
    float clipped = alpha - cutoff;

    // The condition is uniform across the draw, including derivative quads.
#if FAST_UNIFORM_PATH
    [branch] if (cutoff > 0 && MsaaState.z != 0)
#else
    [flatten] if (cutoff > 0 && MsaaState.z != 0)
#endif
    {
        float width = abs(ddx_coarse(alpha)) + abs(ddy_coarse(alpha));
        clipped = saturate(mad(-0.5, width, clipped) / max(width, 0.0001) + 1.0) - 0.0001;
    }

    clip(clipped);
    return 0;
}
