import Visibility.OpaqueRay;

/// Resolved device-space depth at each camera pixel. Zero denotes sky in this reversed-depth capture.
Texture2D<float> sceneDepth : register(t1);
/// X holds blocked-light bits, the test override, or a 0/1 diagnostic flag. Y preserves the input depth bit pattern.
RWTexture2D<uint2> result : register(u0);
cbuffer Frame : register(b0)
{
    /// Row-major inverse GPU view-projection transform for the captured depth camera.
    row_major float4x4 clipToWorld;
    /// XYZ points from the receiver toward each directional light in world space. W is unused.
    float4 directions[32];
    /// Width and height of the depth texture and output in pixels.
    uint2 size;
    /// Number of populated directions. Each of the first 32 can set its corresponding bit in result.x.
    uint lightCount;
    /// A nonzero value writes these bits at valid depth pixels to test the output path without tracing.
    uint testMask;
};

#ifndef AL_RAY_OUTPUT_MASK
#define AL_RAY_OUTPUT_MASK 0xffffffffu
#endif

/// Unprojects a pixel center and raw device depth to a homogeneous world position.
float4 reconstruct(uint2 pixel, float depth)
{
    float2 screen = (float2(pixel) + 0.5) / float2(size);
    return mul(clipToWorld, float4(screen * float2(2, -2) + float2(-1, 1), depth, 1));
}

#ifdef AL_RAY_REPROJECT_RECEIVER
/// Divides the unprojected coordinates by W to obtain a world-space point.
float3 worldAt(uint2 pixel, float depth)
{
    float4 position = reconstruct(pixel, depth);
    return position.xyz / position.w;
}

/// Returns an adjacent pixel's absolute depth difference, or one when it cannot bound a receiver.
float neighborDifference(int2 pixel, float depth)
{
    if (any(pixel < 0) || any(pixel >= int2(size))) return 1;
    float neighbor = sceneDepth.Load(int3(pixel, 0));
    return neighbor > 0 && neighbor <= 1 && isfinite(neighbor) ? abs(neighbor - depth) : 1;
}

// Resolved MSAA depth can come from an off-center sample on a sloped triangle.
// Move the receiver to the center-ray hit only within the local depth footprint.
bool reprojectReceiver(uint2 pixel, float depth, inout float3 world)
{
    int2 p = int2(pixel);
    float dx = min(neighborDifference(p + int2(1, 0), depth), neighborDifference(p - int2(1, 0), depth));
    float dy = min(neighborDifference(p + int2(0, 1), depth), neighborDifference(p - int2(0, 1), depth));
    if (dx == 1 || dy == 1) return false;
    float tolerance = 0.5 * (dx + dy) + depth * 0.00000095367431640625;
    float3 origin = worldAt(pixel, 1);
    float3 direction = world - origin;
    float distance = length(direction);
    if (distance <= 0 || !isfinite(distance)) return false;
    direction /= distance;
    float nearT = dot(worldAt(pixel, min(1, depth + tolerance)) - origin, direction);
    float farT = dot(worldAt(pixel, max(depth - tolerance, depth * 0.5)) - origin, direction);
    if (!isfinite(nearT) || !isfinite(farT) || farT <= 0) return false;

    RayQuery<RAY_FLAG_FORCE_OPAQUE | RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES> query;
    query.TraceRayInline(scene, RAY_FLAG_NONE, 0xff, rayInterval(origin, direction, 0, farT));
    while (query.Proceed()) {}
    if (query.CommittedStatus() != COMMITTED_TRIANGLE_HIT || query.CommittedRayT() < nearT)
        return false;
    world = origin + direction * query.CommittedRayT();
    return true;
}
#endif

/// Traces from the receiver toward each light and keeps the bits requested by the output permutation.
uint blockedLights(float3 world)
{
    uint blocked = 0;
    [loop] for (uint light = 0; light < min(lightCount, 32u); ++light)
    {
        if (occluded(rayInterval(world, directions[light].xyz, 0.01, 10000)))
            blocked |= 1u << light;
    }
    return blocked & AL_RAY_OUTPUT_MASK;
}

[shader("compute")]
[numthreads(8, 8, 1)]
void Main(uint3 id : SV_DispatchThreadID)
{
    uint2 pixel = id.xy;
    if (any(pixel >= size)) return;
    float depth = sceneDepth.Load(int3(pixel, 0));
    result[pixel] = uint2(0, asuint(depth));
    if (depth <= 0 || depth > 1 || !isfinite(depth)) return;
    if (testMask != 0)
    {
        result[pixel] = uint2(testMask, asuint(depth));
        return;
    }
    float4 position = reconstruct(pixel, depth);
    if (abs(position.w) < 1e-8 || !all(isfinite(position))) return;
    float3 world = position.xyz / position.w;
#ifdef AL_RAY_REPROJECT_RECEIVER
    bool accepted = reprojectReceiver(pixel, depth, world);
#endif
#if defined(AL_RAY_REPROJECT_RECEIVER) && defined(AL_RAY_DIAG_REJECTED)
    result[pixel] = uint2(accepted ? 0u : 1u, asuint(depth));
#elif defined(AL_RAY_REPROJECT_RECEIVER) && defined(AL_RAY_DIAG_ACCEPTED)
    result[pixel] = uint2(accepted ? 1u : 0u, asuint(depth));
#else
    result[pixel] = uint2(blockedLights(world), asuint(depth));
#endif
}
