static const float3 luminanceWeights = float3(0.212673, 0.715152, 0.072175);

// Material response compresses the brightest channel before each light's band,
// then uses a softer shoulder on the combined skin and cloth illumination.
public float directLightCompression(float3 incident)
{
    float peak = max(incident.r, max(incident.g, incident.b));
    return 1 + 7 * max(peak - 0.10, 0);
}

public float bandCompression(float3 sum)
{
    float peak = max(sum.r, max(sum.g, sum.b));
    return mad(max(peak - 0.18, 0), 4.5, 1);
}

public float bandWeight(float3 compressed)
{
    return saturate(dot(compressed, luminanceWeights) * 5.5555553);
}

// Unit vectors are in world space. Bend a fresh normal for each light.
public float bandFacing(float3 normal, float3 lightDirection)
{
    float3 bent = 0.75 * normal + 0.25 * lightDirection;
    bent *= rsqrt(max(dot(bent, bent), 1e-12));
    return saturate(dot(bent, lightDirection));
}

public float3 perLightBand(float3 arriving)
{
    float luminance = dot(arriving, luminanceWeights);
    float band = saturate(mad(luminance, 25.0, -1.0));
    return arriving * ((band * 0.18) / max(luminance, 1e-6));
}

// For the face, choose the palette band before weighting it by shadow visibility.
public float3 visibleFaceBand(float3 incident, float visibility)
{
    return perLightBand(incident) * visibility;
}

// The ambient input is Unity's SH probe evaluated at the surface normal.
// Both materials tint this fill with their processed pigment.
float diffuseFill(float3 ambient, float directBand)
{
    return 0.84 * saturate(dot(ambient, luminanceWeights)) + 0.49 * directBand;
}

public float skinFill(float3 ambient, float directBand)
{
    return 0.06 * diffuseFill(ambient, directBand);
}

public float fabricFill(float3 ambient, float directBand)
{
    return 0.97 * diffuseFill(ambient, directBand);
}
