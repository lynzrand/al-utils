/// Use the smooth mesh axis closest to increasing highlight UV1 V. Hair cards
/// with collapsed highlight charts retain the mesh bitangent.
public float3 paintedFiberAxis(float3 normal, float3 tangent, float2 uv, float3 position)
{
    float2 dx = ddx(uv), dy = ddy(uv);
    float3 alongV = dx.x * ddy(position) - dy.x * ddx(position);
    float3 bitangent = cross(normal, tangent);
    // Interpolating a constant UV can leave a few ULPs of screen-space variation.
    // The determinant must exceed that error before its sign can orient a fiber.
    float determinant = dx.x * dy.y - dx.y * dy.x;
    float2 gradient = max(abs(dx), abs(dy));
    float2 precision = 1e-6 * max(1, abs(uv));
    if (abs(determinant) <= dot(gradient, precision.yx))
        return bitangent;
    alongV *= sign(determinant);
    float alongT = dot(alongV, tangent);
    float alongB = dot(alongV, bitangent);
    float3 signedTangent = alongT < 0 ? -tangent : tangent;
    float3 signedBitangent = alongB < 0 ? -bitangent : bitangent;
    return abs(alongT) > abs(alongB) ? signedTangent : signedBitangent;
}

float fiberNoiseCorner(int2 cell)
{
    uint hash = uint(cell.x) * 0x8da6b343u ^ uint(cell.y) * 0xd8163841u;
    hash ^= hash >> 16;
    hash *= 0x7feb352du;
    hash ^= hash >> 15;
    return float(hash >> 8) / 16777216.0;
}

/// UV1 V follows the length of the painted lock. Use elongated noise cells
/// and fade their contrast as the screen footprint approaches one cell.
float filteredFiberNoise(float2 p, float amplitude)
{
    int2 cell = int2(floor(p));
    float2 f = smoothstep(0, 1, frac(p));
    float nearRow = lerp(fiberNoiseCorner(cell), fiberNoiseCorner(cell + int2(1, 0)), f.x);
    float farRow = lerp(fiberNoiseCorner(cell + int2(0, 1)), fiberNoiseCorner(cell + int2(1, 1)), f.x);
    float2 footprint = fwidth(p);
    float contrast = 1 - smoothstep(0.25, 1, max(footprint.x, footprint.y));
    return amplitude * contrast * (2 * lerp(nearRow, farRow, f.y) - 1);
}

public float fiberSheenNoise(float2 uv)
{
    return 1 + filteredFiberNoise(uv * float2(32, 3), 0.36);
}

/// A fine patch of neighboring fibers leans slightly toward or away from the
/// card normal. The tilt fades to zero when this strand pattern is subpixel.
public float fiberStrandTilt(float2 uv)
{
    return filteredFiberNoise(uv * float2(160, 15) + float2(19, 37), 0.14);
}

/// An untilted cylindrical fiber reflects most strongly where its axis is
/// perpendicular to the light/view half vector. Center the artist's red-channel
/// stamp at that angle, retaining its broken outline across the lock.
public float fiberStreak(Texture2D<float4> highlight, SamplerState state,
                         float3 normal, float3 fiber, float3 light, float3 view,
                         float strandU, float2 dx, float2 dy, float sheenScale = 1, float strandTilt = 0)
{
    float3 h = light + view;
    float3 halfVector = h * rsqrt(max(dot(h, h), 1e-8));
    float error = dot(fiber, halfVector);
    float facing = saturate(3 * dot(normal, light)) * smoothstep(0.25, 0.7, dot(normal, halfVector));
    float envelope = exp2(-38 * error * error);
#if defined(HAIR_FIBER_HALF)
#ifdef HAIR_FIBER_EXTENDED
    // The fixed soft envelope trims the ends of the stretched painted marks.
    float stampScale = 0.61;
#else
    float stampScale = 0.78;
#endif
    float2 uv = float2(strandU, clamp(0.5 + stampScale * error, 0.01, 0.99));
#elif defined(HAIR_FIBER_WIDE)
    // Let the geometric lobe carry a continuous sheen across the lock. Read
    // just the center of the stamp so its narrow motifs span more of the lobe.
    float2 uv = float2(strandU, clamp(0.5 + 0.32 * error, 0.01, 0.99));
#else
    float2 uv = float2(strandU, clamp(0.5 + 1.8 * error, 0.01, 0.99));
#endif
    // Both screen axes use the authored UV footprint as a first approximation
    // to stripe minification inside the divergent clustered-light loop.
    float stamp = highlight.SampleGrad(state, uv, dx, dy).r;
#if defined(HAIR_FIBER_DENSE)
    // Project H onto normalize(fiber + strandTilt * normal). Neighboring
    // strands meet the reflection angle at different points along the lock.
    float tiltedError = error + strandTilt * dot(normal, halfVector);
    float tiltedEnvelope = exp2(-38 * tiltedError * tiltedError / (1 + strandTilt * strandTilt));
    float sheen = 0.22 * sheenScale * lerp(envelope, tiltedEnvelope, 0.65);
    return 1.4 * facing * lerp(sheen, envelope, stamp);
#else
#if defined(HAIR_FIBER_NOISE)
    stamp = lerp(0.22 * sheenScale, 1.0, stamp);
#elif defined(HAIR_FIBER_WIDE) || defined(HAIR_FIBER_HALF)
    stamp = lerp(0.22, 1.0, stamp);
#endif
    return 1.4 * facing * envelope * stamp;
#endif
}
