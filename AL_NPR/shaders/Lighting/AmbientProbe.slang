// UnityPerDraw stores the three linear SH vectors at c25, the three
// quadratic vectors at c28 and the final RGB coefficient at c31.
public struct SHCoefficients
{
    public float4 ar, ag, ab;
    public float4 br, bg, bb;
    public float4 c;

    public float3 evaluate(float3 normal)
    {
        float4 linear = float4(normal, 1);
        float4 quadratic = normal.yzzx * normal.xyzz;
        float3 first = float3(dot(ar, linear), dot(ag, linear), dot(ab, linear));
        float3 second = float3(dot(br, quadratic), dot(bg, quadratic), dot(bb, quadratic));
        float difference = mad(normal.x, normal.x, -(normal.y * normal.y));
        return first + mad(c.rgb, difference, second);
    }
}
