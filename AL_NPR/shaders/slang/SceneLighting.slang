// Unit vectors are in world space. Bend a fresh normal for each light.
public float bandFacing(float3 normal, float3 lightDirection)
{
    float3 bent = mad(normal, 0.75, lightDirection * 0.25);
    bent *= rsqrt(max(dot(bent, bent), 1e-12));
    return saturate(dot(bent, lightDirection));
}

public float3 perLightBand(float3 arriving)
{
    float luminance = dot(arriving, float3(0.212673, 0.715152, 0.072175));
    float band = saturate(mad(luminance, 25.0, -1.0));
    return arriving * ((band * 0.18) / max(luminance, 1e-6));
}
