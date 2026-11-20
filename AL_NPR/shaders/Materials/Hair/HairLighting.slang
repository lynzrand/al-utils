/// Return the unit bisector of the world-space light and view vectors, guarded against opposite directions.
float3 reflectionHalfVector(float3 lightDirection, float3 viewDirection)
{
    float3 halfVector = lightDirection + viewDirection;
    return halfVector * rsqrt(max(dot(halfVector, halfVector), 1e-8));
}

/// Return one light's painted highlight using strand U, a half-vector V offset, and explicit 2D UV gradients.
/// Compute UV gradients before entering a divergent light loop.
public float paintedReflection(Texture2D<float4> highlight, SamplerState state,
                              float3 normal, float3 tangent, float3 lightDirection,
                              float3 viewDirection, float strandU, float2 dx, float2 dy)
{
    float3 halfVector = reflectionHalfVector(lightDirection, viewDirection);
    float across = dot(cross(normal, tangent), halfVector);
    float2 uv = float2(strandU, mad(across, 0.85, 0.5));
    float stamp = highlight.SampleGrad(state, uv, dx, dy).r;
    float shoulder = saturate((saturate(dot(normal, halfVector)) - 0.60) * 4.0);
    return ((stamp * shoulder) * 1.4) * saturate(dot(normal, lightDirection) * 3.0);
}

/// Evaluate the analytic anisotropic ribbon highlight from the normal, strand tangent, light, and view.
public float ribbonReflection(float3 normal, float3 tangent, float3 lightDirection, float3 viewDirection)
{
    float3 halfVector = reflectionHalfVector(lightDirection, viewDirection);
    float facing = saturate(dot(normal, halfVector));
    float across = dot(tangent, halfVector);
    float error = max(0, 1 - facing * facing - 0.86 * across * across);
    float core = saturate((0.052 - error) * 48);
    float shoulder = saturate((0.18 - error) * 7);
    float shape = (0.76 * core + 0.24 * shoulder) * saturate((facing - 0.48) * 4);
    return shape * saturate(3 * dot(normal, lightDirection));
}

/// Evaluate the narrow half-vector gloss lobe used by the non-ribbon analytic variant.
public float glossReflection(float3 normal, float3 lightDirection, float3 viewDirection)
{
    float facing = saturate(dot(normal, reflectionHalfVector(lightDirection, viewDirection)));
    return saturate((facing - 0.91) * 18) * saturate(3 * dot(normal, lightDirection));
}

/// Compress accumulated RGB streaks and apply highlight RGB, its alpha strength, and the scalar detail mask.
public float3 finishHairReflection(float3 reflected, float detailMask, float4 highlightTint)
{
    float3 rgb = 6 * reflected;
    float peak = max(rgb.r, max(rgb.g, rgb.b));
    rgb /= 1 + 1.25 * max(peak - 0.58, 0);
    return rgb * highlightTint.rgb * saturate(highlightTint.a) * mad(detailMask, 0.55, 0.45);
}
