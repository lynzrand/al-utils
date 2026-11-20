// Unity stores these matrices as four consecutive constant registers. Keep
// the multiply-add order of the game for skinned meshes and shadow depth.
public struct TransformColumns
{
    public float4 x, y, z, origin;

    public float3 direction(float3 v)
    {
        return mad(z.xyz, v.z, mad(x.xyz, v.x, y.xyz * v.y));
    }

    public float3 point(float3 p)
    {
        return direction(p) + origin.xyz;
    }

    public float4 clipPosition(float3 p)
    {
        return mad(z, p.z, mad(x, p.x, y * p.y)) + origin;
    }
}

float3 unitVector(float3 v)
{
    return v * rsqrt(max(dot(v, v), 1.1754944e-38));
}

public float3 surfaceNormal(float3 normal, TransformColumns worldToObject)
{
    float3 transformed = float3(dot(normal, worldToObject.x.xyz),
                                dot(normal, worldToObject.y.xyz),
                                dot(normal, worldToObject.z.xyz));
    return unitVector(transformed);
}

public float4 surfaceTangent(float4 tangent, TransformColumns objectToWorld, float worldSign)
{
    float handedness = (tangent.w > 0 ? 1.0 : -1.0) * (worldSign >= 0 ? 1.0 : -1.0);
    return float4(unitVector(objectToWorld.direction(tangent.xyz)), handedness);
}

public float3 shadowCasterPosition(float3 positionWS, float3 normalOS, TransformColumns objectToWorld,
                                   float3 lightDirection, float2 bias)
{
    // The caster pass uses the object-to-world direction for its normal.
    float3 normalWS = unitVector(objectToWorld.direction(normalOS));
    float slope = 1 - saturate(dot(lightDirection, normalWS));
    return mad(normalWS, slope * bias.y, mad(lightDirection, bias.x, positionWS));
}

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
