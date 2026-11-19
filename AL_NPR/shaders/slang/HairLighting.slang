// Slide the painted streak across the strand with the reflected half vector.
// The caller computes UV gradients before entering the divergent light loop.
public float paintedReflection(Texture2D<float4> highlight, SamplerState state,
                              float3 normal, float3 tangent, float3 lightDirection,
                              float3 viewDirection, float strandU, float2 dx, float2 dy)
{
    float3 halfVector = lightDirection + viewDirection;
    halfVector *= rsqrt(max(dot(halfVector, halfVector), 1e-8));
    float across = dot(cross(normal, tangent), halfVector);
    float2 uv = float2(strandU, mad(across, 0.85, 0.5));
    float stamp = highlight.SampleGrad(state, uv, dx, dy).r;
    float shoulder = saturate((saturate(dot(normal, halfVector)) - 0.60) * 4.0);
    return ((shoulder * stamp) * 1.4) * saturate(dot(normal, lightDirection) * 3.0);
}
