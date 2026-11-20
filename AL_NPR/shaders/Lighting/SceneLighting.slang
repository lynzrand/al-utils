/// Linear RGB luminance weights used by the release band and fill calculations.
static const float3 luminanceWeights = float3(0.212673, 0.715152, 0.072175);

/// Return the divisor for an individual light's incident RGB, using its peak channel before banding.
public float directLightCompression(float3 incident)
{
    float peak = max(incident.r, max(incident.g, incident.b));
    return 1 + 7 * max(peak - 0.10, 0);
}

/// Return the divisor that limits the combined RGB bands after accumulation.
public float bandCompression(float3 sum)
{
    float peak = max(sum.r, max(sum.g, sum.b));
    return mad(max(peak - 0.18, 0), 4.5, 1);
}

/// Convert the compressed RGB band into a saturated scalar palette weight.
public float bandWeight(float3 compressed)
{
    return saturate(dot(compressed, luminanceWeights) * 5.5555553);
}

/// Bend the world-space normal toward this light and return the clamped cosine.
public float bandFacing(float3 normal, float3 lightDirection)
{
    float3 bent = 0.75 * normal + 0.25 * lightDirection;
    bent *= rsqrt(max(dot(bent, bent), 1e-12));
    return saturate(dot(bent, lightDirection));
}

/// Shape arriving RGB into a luminance-selected toon band while retaining the light's hue.
public float3 perLightBand(float3 arriving)
{
    float luminance = dot(arriving, luminanceWeights);
    float band = saturate(mad(luminance, 25.0, -1.0));
    return arriving * ((band * 0.18) / max(luminance, 1e-6));
}

/// Select the face band from incident RGB, then multiply by its scalar shadow visibility.
public float3 visibleFaceBand(float3 incident, float visibility)
{
    return perLightBand(incident) * visibility;
}

/// Blend the renderer's SH luminance and the scalar direct band into one material fill strength.
/// Each material tints this scalar fill with its own processed pigment.
float diffuseFill(float3 ambient, float directBand)
{
    return 0.84 * saturate(dot(ambient, luminanceWeights)) + 0.49 * directBand;
}

/// Diffuse fill strength added to the skin palette, before tinting by processed skin pigment.
public float skinFill(float3 ambient, float directBand)
{
    return 0.06 * diffuseFill(ambient, directBand);
}

/// Diffuse fill strength for cloth, before tinting by the fabric pigment.
public float fabricFill(float3 ambient, float directBand)
{
    return 0.97 * diffuseFill(ambient, directBand);
}
