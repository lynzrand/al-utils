// Frozen-camera directional visibility. Reconstructed receiver depth must
// match the skin fragment before this result can affect lighting.
RaytracingAccelerationStructure scene : register(t0);
Texture2D<float> sceneDepth : register(t1);
RWTexture2D<uint2> result : register(u0);
cbuffer Frame : register(b0)
{
    row_major float4x4 clipToWorld;
    float4 directions[32];
    uint2 size;
    uint lightCount;
    uint testMask;
};

// Diagnostic variants keep the same native ABI and frozen-scene contract.
// Restricting the output to one light does not reduce the traced light count.
#ifndef AL_RAY_OUTPUT_MASK
#define AL_RAY_OUTPUT_MASK 0xffffffffu
#endif

float3 ReconstructWorld(uint2 pixel, float depth)
{
    float2 screen = (float2(pixel) + 0.5) / float2(size);
    float4 homogeneous = mul(clipToWorld, float4(screen * float2(2, -2) + float2(-1, 1), depth, 1));
    return homogeneous.xyz / homogeneous.w;
}

#ifdef AL_RAY_REPROJECT_RECEIVER
float NeighborDepthDifference(int2 pixel, float depth)
{
    if (any(pixel < 0) || any(pixel >= int2(size))) return 1;
    float neighbor = sceneDepth.Load(int3(pixel, 0));
    return neighbor > 0 && neighbor <= 1 && isfinite(neighbor) ? abs(neighbor - depth) : 1;
}

// A resolved depth sample can come from an off-center MSAA sample. Using that
// depth at the pixel center puts the reconstructed point inside a sloped
// triangle. Find the actual captured triangle along the center camera ray,
// but accept it only inside the local half-pixel depth footprint. A mismatch
// retains the original receiver, so rejecting pixels cannot hide their acne.
bool ReprojectReceiver(uint2 pixel, float depth, inout float3 world)
{
    int2 p = int2(pixel);
    float dx = min(NeighborDepthDifference(p + int2(1, 0), depth),
                   NeighborDepthDifference(p - int2(1, 0), depth));
    float dy = min(NeighborDepthDifference(p + int2(0, 1), depth),
                   NeighborDepthDifference(p - int2(0, 1), depth));
    if (dx == 1 || dy == 1) return false;
    float tolerance = 0.5 * (dx + dy) + depth * 0.00000095367431640625;
    float3 nearPoint = ReconstructWorld(pixel, 1);
    float3 direction = world - nearPoint;
    float distance = length(direction);
    if (distance <= 0 || !isfinite(distance)) return false;
    direction /= distance;
    float lower = dot(ReconstructWorld(pixel, min(1, depth + tolerance)) - nearPoint, direction);
    float upper = dot(ReconstructWorld(pixel, max(depth - tolerance, depth * 0.5)) - nearPoint, direction);
    if (!isfinite(lower) || !isfinite(upper) || upper <= 0) return false;

    RayDesc ray;
    ray.Origin = nearPoint;
    ray.Direction = direction;
    ray.TMin = 0;
    ray.TMax = upper;
    RayQuery<RAY_FLAG_FORCE_OPAQUE | RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES> query;
    query.TraceRayInline(scene, RAY_FLAG_NONE, 0xff, ray);
    while (query.Proceed()) { }
    if (query.CommittedStatus() != COMMITTED_TRIANGLE_HIT || query.CommittedRayT() < lower)
        return false;
    world = nearPoint + direction * query.CommittedRayT();
    return true;
}
#endif

[numthreads(8, 8, 1)]
void Main(uint3 id : SV_DispatchThreadID)
{
    if (any(id.xy >= size)) return;
    float depth = sceneDepth.Load(int3(id.xy, 0));
    result[id.xy] = uint2(0, asuint(depth));
    if (depth <= 0 || depth > 1 || !isfinite(depth)) return;
    if (testMask != 0)
    {
        result[id.xy].x = testMask;
        return;
    }
    float2 screen = (float2(id.xy) + 0.5) / float2(size);
    float4 homogeneous = mul(clipToWorld, float4(screen * float2(2, -2) + float2(-1, 1), depth, 1));
    if (abs(homogeneous.w) < 1e-8 || !all(isfinite(homogeneous))) return;
    float3 world = homogeneous.xyz / homogeneous.w;
#ifdef AL_RAY_REPROJECT_RECEIVER
    bool reprojected = ReprojectReceiver(id.xy, depth, world);
#if defined(AL_RAY_DIAG_ACCEPTED) || defined(AL_RAY_DIAG_REJECTED)
#ifdef AL_RAY_DIAG_REJECTED
    reprojected = !reprojected;
#endif
    result[id.xy] = uint2(reprojected ? 1u : 0u, asuint(depth));
    return;
#endif
#endif
    uint blocked = 0;
    [loop] for (uint light = 0; light < min(lightCount, 32); light++)
    {
        RayDesc ray;
        ray.Origin = world;
        ray.Direction = directions[light].xyz;
        ray.TMin = 0.01;
        ray.TMax = 10000;
        RayQuery<RAY_FLAG_FORCE_OPAQUE | RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH
            | RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES> query;
        query.TraceRayInline(scene, RAY_FLAG_NONE, 0xff, ray);
        while (query.Proceed()) { }
        if (query.CommittedStatus() == COMMITTED_TRIANGLE_HIT) blocked |= 1u << light;
    }
    result[id.xy] = uint2(blocked & AL_RAY_OUTPUT_MASK, asuint(depth));
}
