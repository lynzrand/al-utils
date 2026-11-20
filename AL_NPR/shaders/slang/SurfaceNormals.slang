// The interpolated tangent and normal share the normal's scale. Preserve the
// mesh handedness when reconstructing the bitangent after interpolation.
public struct TangentFrame
{
    public float3 tangent;
    public float3 bitangent;
    public float3 normal;

    public __init(float3 normalWS, float4 tangentWS)
    {
        float inverseLength = 1 / max(length(normalWS), 1.1754944e-38);
        normal = inverseLength * normalWS;
        tangent = inverseLength * tangentWS.xyz;
        bitangent = inverseLength * (cross(normalWS, tangentWS.xyz) * tangentWS.w);
    }

    public float3 toWorld(float3 normalTS)
    {
        return float3(dot(float3(tangent.x, bitangent.x, normal.x), normalTS),
                      dot(float3(tangent.y, bitangent.y, normal.y), normalTS),
                      dot(float3(tangent.z, bitangent.z, normal.z), normalTS));
    }

    public float3 toTangent(float3 normalWS)
    {
        return float3(dot(tangent, normalWS), dot(bitangent, normalWS), dot(normal, normalWS));
    }
}

// Unity normal maps store X in red times alpha and Y in green.
public float3 unpackScaledNormal(float4 packed, float strength)
{
    float2 xy = mad(float2(packed.r * packed.a, packed.g), 2, -1);
    float z = max(sqrt(1 - min(dot(xy, xy), 1)), 1e-16);
    return float3(xy * strength, lerp(1, z, saturate(strength)));
}
