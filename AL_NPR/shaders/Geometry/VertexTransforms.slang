/// Unity stores these matrices as four consecutive constant registers. Keep
/// the multiply-add order of the game for skinned meshes and shadow depth.
public struct TransformColumns
{
    /// First matrix column, multiplying the input X component.
    public float4 x;
    /// Second matrix column, multiplying the input Y component.
    public float4 y;
    /// Third matrix column, multiplying the input Z component.
    public float4 z;
    /// Fourth matrix column, added when transforming positions with homogeneous W equal to one.
    public float4 origin;

    /// Transforms a direction by the XYZ portions of the first three columns, omitting translation.
    public float3 direction(float3 v)
    {
        return mad(z.xyz, v.z, mad(x.xyz, v.x, y.xyz * v.y));
    }

    /// Transforms an affine point and adds the translation column.
    public float3 point(float3 p)
    {
        return direction(p) + origin.xyz;
    }

    /// Transforms an affine point to homogeneous clip coordinates, retaining the computed W.
    public float4 clipPosition(float3 p)
    {
        return mad(z, p.z, mad(x, p.x, y * p.y)) + origin;
    }
}

/// Normalizes a direction with the squared-length floor used by the game.
float3 unitVector(float3 v)
{
    return v * rsqrt(max(dot(v, v), 1.1754944e-38));
}

/// Transforms an object-space normal by the inverse transpose and normalizes it in world space.
public float3 surfaceNormal(float3 normal, TransformColumns worldToObject)
{
    float3 transformed = float3(dot(normal, worldToObject.x.xyz),
                                dot(normal, worldToObject.y.xyz),
                                dot(normal, worldToObject.z.xyz));
    return unitVector(transformed);
}

/// Transforms the mesh tangent and multiplies its handedness by the transform's mirror sign.
public float4 surfaceTangent(float4 tangent, TransformColumns objectToWorld, float worldSign)
{
    float handedness = (tangent.w > 0 ? 1.0 : -1.0) * (worldSign >= 0 ? 1.0 : -1.0);
    return float4(unitVector(objectToWorld.direction(tangent.xyz)), handedness);
}

/// Offsets a dented world position along the light direction and the slope-scaled transformed normal.
public float3 shadowCasterPosition(float3 positionWS, float3 normalOS, TransformColumns objectToWorld,
                                   float3 lightDirection, float2 bias)
{
    // The caster pass uses the object-to-world direction for its normal.
    float3 normalWS = unitVector(objectToWorld.direction(normalOS));
    float slope = 1 - saturate(dot(lightDirection, normalWS));
    return mad(normalWS, slope * bias.y, mad(lightDirection, bias.x, positionWS));
}

/// Blends normal and vertex-color extrusion, applies the supplied dent, and scales the outline by clip W.
public float3 outlinePosition(float3 position, float3 normal, float3 color, float3 dent,
                             float width, float vertexColorNormal, float clipW)
{
    float depthScale = min(clipW, 0.3);
    float3 colored = width * (normal + color + float3(-0.5, 0, -0.5));
    float3 fromNormal = width * normal;
    float3 offset = mad(colored * depthScale, 0.5, dent);
    offset = mad(-fromNormal, depthScale, offset);
    offset = mad(vertexColorNormal, offset, fromNormal * depthScale);
    return mad(offset, min(clipW, 0.35), position);
}
