/// The interpolated tangent and normal share the normal's scale. Preserve the
/// mesh handedness when reconstructing the bitangent after interpolation.
public struct TangentFrame
{
    /// Interpolated tangent along surface U in world space, scaled by the interpolated normal's inverse
    /// length.
    public float3 tangent;
    /// World-space perpendicular to normal and tangent, carrying the mesh's tangent handedness.
    public float3 bitangent;
    /// World-space geometric normal, normalized after interpolation.
    public float3 normal;

    /// Construct the shading frame from the interpolated world normal and signed tangent.
    public __init(float3 normalWS, float4 tangentWS)
    {
        float inverseLength = 1 / max(length(normalWS), 1.1754944e-38);
        normal = inverseLength * normalWS;
        tangent = inverseLength * tangentWS.xyz;
        bitangent = inverseLength * (cross(normalWS, tangentWS.xyz) * tangentWS.w);
    }

    /// Transform tangent-space XYZ into the world-space strand or skin frame.
    public float3 toWorld(float3 normalTS)
    {
        return float3(dot(float3(tangent.x, bitangent.x, normal.x), normalTS),
                      dot(float3(tangent.y, bitangent.y, normal.y), normalTS),
                      dot(float3(tangent.z, bitangent.z, normal.z), normalTS));
    }

    /// Project a world-space vector onto the tangent, bitangent, and geometric normal axes.
    public float3 toTangent(float3 normalWS)
    {
        return float3(dot(tangent, normalWS), dot(bitangent, normalWS), dot(normal, normalWS));
    }
}

/// Decode Unity's packed X from R times A and Y from G, reconstruct positive Z, and apply the supplied
/// strength.
public float3 unpackScaledNormal(float4 packed, float strength)
{
    float2 xy = mad(float2(packed.r * packed.a, packed.g), 2, -1);
    float z = max(sqrt(1 - min(dot(xy, xy), 1)), 1e-16);
    return float3(xy * strength, lerp(1, z, saturate(strength)));
}

/// Combine two tangent-space slopes in homogeneous form for normalization after layering.
/// Multiplying the two Z components retains the common denominator for the sum of the XY slopes.
public float3 combineNormalSlopes(float3 a, float3 b)
{
    return float3(mad(a.xy, b.z, a.z * b.xy), a.z * b.z);
}
