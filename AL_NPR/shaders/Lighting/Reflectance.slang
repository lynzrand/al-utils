/// Angular weights of the game's stock diffuse lobes. Both directions are
/// world-space unit vectors. Shadowing and light intensity are applied by the caller.
public struct DiffuseLobes
{
    /// Direct diffuse weight, clamped from the normal/light dot product to [0, 1].
    public float cosine;
    /// Wrapped diffuse weight, mapping a normal/light dot product of −1 to 0 and +1 to 1.
    public float wrapped;

    /// Evaluate both diffuse weights from one dot product of the unit normal and light direction.
    public __init(float3 normal, float3 toLight)
    {
        float nDotL = dot(normal, toLight);
        cosine = saturate(nDotL);
        wrapped = mad(nDotL, 0.5, 0.5);
    }
}

/// Stock hair and cloth use a Blinn–Phong highlight for the wet layer.
/// The dry fabric finish uses the same lobe with a narrower exponent range.
/// Raise the nonnegative normal/half-vector dot product to the material's specular exponent.
public float blinnPhong(float3 normal, float3 halfVector, float exponent)
{
    return pow(max(dot(normal, halfVector), 0), exponent);
}

/// Evaluate a wet Blinn–Phong highlight with its exponent selected by wetness.
public float wetSpecular(float3 normal, float3 halfVector, float wetness)
{
    return blinnPhong(normal, halfVector, exp2(mad(wetness, 7.5, 1)));
}

/// The material tilts the view direction to move the painted rim across the
/// silhouette. Keep that authored length when evaluating the grazing angle.
/// Return the powered grazing angle for a material-adjusted view direction, retaining the authored vector
/// length.
public float grazingRim(float3 normal, float3 view, float exponent)
{
    return pow(max(1 - dot(normal, view), 0.0001), exponent);
}
