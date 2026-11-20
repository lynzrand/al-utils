/// UnityPerDraw stores the three linear SH vectors at c25, the three
/// quadratic vectors at c28 and the final RGB coefficient at c31.
public struct SHCoefficients
{
    /// Red-channel linear SH coefficients for normal X, Y, Z, followed by the constant term.
    public float4 ar;
    /// Green-channel linear SH coefficients for normal X, Y, Z, followed by the constant term.
    public float4 ag;
    /// Blue-channel linear SH coefficients for normal X, Y, Z, followed by the constant term.
    public float4 ab;
    /// Red-channel quadratic SH coefficients for XY, YZ, ZZ, and ZX.
    public float4 br;
    /// Green-channel quadratic SH coefficients for XY, YZ, ZZ, and ZX.
    public float4 bg;
    /// Blue-channel quadratic SH coefficients for XY, YZ, ZZ, and ZX.
    public float4 bb;
    /// RGB coefficients for X squared minus Y squared. W is unused by the evaluator.
    public float4 c;

    /// Evaluate Unity's linear and quadratic SH polynomials without normalizing the supplied world-space
    /// vector.
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
