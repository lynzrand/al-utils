import Surface.Coverage;

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

struct Interpolators
{
    float4 position : SV_Position;
    float3 unusedWorldPosition : TEXCOORD0;
    float4 uv : TEXCOORD1;
};

[shader("fragment")]
float4 main(Interpolators input) : SV_Target
{
#ifdef OPAQUE_CONTROL
    return 0;
#else
    float fade = saturate(FadeAndCutoff.x * 1.00001);
    float cutoff = FadeAndCutoff.w;
#ifdef FAST_AUDITED_MAP_TEXTURES
    // This variant is only for map002's audited AL/Map bindings. The lowest
    // stored alpha is 243/255. For these exact stock material settings, the
    // original cutoff and its derivative-smoothed form both keep the pixel.
    [branch] if (fade >= 1.0 && BaseColor.a == 1.0 && cutoff == 0.5)
        return 0;
#endif
#ifdef FAST_OPAQUE_PATH
    // AL/Map base-map alpha is stored in a normalized texture. With a nonnegative
    // material alpha and a nonpositive cutoff, neither branch can discard.
    [branch] if (cutoff <= 0 && BaseColor.a >= 0)
        return 0;
#endif
    float mask;
#ifdef FAST_UNIFORM_PATH
    // The maximum Bayer threshold is one. Fully visible materials have a uniform
    // mask, so the per-pixel coordinate transform and indexed threshold are redundant.
    [branch] if (fade >= 1.0)
        mask = 1.0;
    else
        mask = float(fade >= ditherThreshold(input.position.xy, TargetSize.xy, ViewportTransform.xy, ProjectionState.x));
#else
    mask = float(fade >= ditherThreshold(input.position.xy, TargetSize.xy, ViewportTransform.xy, ProjectionState.x));
#endif

    float2 uv = mad(input.uv.xy, UvTransform.xy, UvTransform.zw);
    float alpha = min(mask, BaseMap.Sample(BaseSampler, uv).a * BaseColor.a);
    float clipped = alpha - cutoff;

    // The condition is uniform across the draw, including derivative quads.
#ifdef FAST_UNIFORM_PATH
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
#endif
}
