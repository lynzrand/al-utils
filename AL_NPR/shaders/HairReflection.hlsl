// N is the geometric hair normal. UV tangent T runs across a strand.
// L points to one scene light and V points to the eye.
float3 Unit(float3 v)
{
    return v * rsqrt(max(dot(v, v), 1e-8));
}

#ifdef HAIR_PAINTED
Texture2D<float4> Highlight : register(t1);
SamplerState HighlightSampler : register(s3);
#endif

float HairReflection(float3 normal : TEXCOORD0, float3 tangent : TEXCOORD1,
                     float3 L : TEXCOORD2, float3 V : TEXCOORD3
#ifdef HAIR_PAINTED
                     , float2 uv : TEXCOORD4, float2 dx : TEXCOORD5, float2 dy : TEXCOORD6
#endif
                     ) : SV_Target
{
    float3 H = Unit(L + V);
    float nh = saturate(dot(normal, H));
#if defined(HAIR_PAINTED)
    float across = dot(cross(normal, tangent), H);
    float2 at = float2(uv.x, 0.50 + 0.85 * across);
    float stamp = Highlight.SampleGrad(HighlightSampler, at, dx, dy).r;
    float shape = stamp * saturate((nh - 0.60) * 4) * 1.4;
#elif defined(HAIR_RIBBON)
    float th = dot(tangent, H);
   // Stretch the half-vector lobe across the strand. The wider shoulder
   // keeps the narrow ink-like core attached to a visible reflection.
    float error = max(0, 1 - nh * nh - 0.86 * th * th);
    float core = saturate((0.052 - error) * 48);
    float shoulder = saturate((0.18 - error) * 7);
    float shape = (0.76 * core + 0.24 * shoulder) * saturate((nh - 0.48) * 4);
#else
    float shape = saturate((nh - 0.91) * 18);
#endif
    return shape * saturate(3 * dot(normal, L));
}
// The palette already contains colored direct light. Use the skin's
// hue-preserving shoulder on its diffuse input before shadow attenuation.
float HairDiffuseGain(float3 raw : TEXCOORD0) : SV_Target
{
    float peak = max(raw.r, max(raw.g, raw.b));
    return rcp(1.0 + 7.0 * max(peak - 0.10, 0));
}

// RGB contains all reflected light. Alpha carries the material detail mask.
float3 HairFinish(float4 reflection : TEXCOORD0, float4 tint : TEXCOORD1) : SV_Target
{
    float3 rgb = 6.0 * reflection.rgb;
    float peak = max(rgb.r, max(rgb.g, rgb.b));
    rgb /= 1.0 + 1.25 * max(peak - 0.58, 0);
    return rgb * tint.rgb * saturate(tint.a) * lerp(0.45, 1.0, reflection.a);
}
