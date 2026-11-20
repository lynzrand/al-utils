// Angular weights of the game's stock diffuse lobes. Both directions are
// world-space unit vectors. Shadowing and light intensity are applied by the caller.
public struct DiffuseLobes
{
    public float cosine;
    public float wrapped;

    public __init(float3 normal, float3 toLight)
    {
        float nDotL = dot(normal, toLight);
        cosine = saturate(nDotL);
        wrapped = mad(nDotL, 0.5, 0.5);
    }
}

// Stock hair and cloth use a Blinn–Phong highlight for the wet layer.
// The dry fabric finish uses the same lobe with a narrower exponent range.
public float blinnPhong(float3 normal, float3 halfVector, float exponent)
{
    return pow(max(dot(normal, halfVector), 0), exponent);
}

public float wetSpecular(float3 normal, float3 halfVector, float wetness)
{
    return blinnPhong(normal, halfVector, exp2(mad(wetness, 7.5, 1)));
}

// The material tilts the view direction to move the painted rim across the
// silhouette. Keep that authored length when evaluating the grazing angle.
public float grazingRim(float3 normal, float3 view, float exponent)
{
    return pow(max(1 - dot(normal, view), 0.0001), exponent);
}
