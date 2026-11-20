// Static opaque geometry probe. No Unity capability flag, shading or filtering.
struct ProbeRay { float3 origin; float tMin; float3 direction; float tMax; };
RaytracingAccelerationStructure scene : register(t0);
StructuredBuffer<ProbeRay> rays : register(t1);
RWStructuredBuffer<uint> results : register(u0);
cbuffer Parameters : register(b0) { uint rayCount; };
[numthreads(64, 1, 1)]
void Main(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= rayCount) return;
    ProbeRay input = rays[id.x];
    results[id.x] = 2;
    float length2 = dot(input.direction, input.direction);
    if (!all(isfinite(input.origin)) || !all(isfinite(input.direction))
        || !isfinite(input.tMin) || !isfinite(input.tMax) || !isfinite(length2)
        || abs(length2 - 1.0) > 0.001 || input.tMin < 0 || input.tMax <= input.tMin) return;
    RayDesc ray;
    ray.Origin = input.origin; ray.Direction = input.direction;
    ray.TMin = input.tMin; ray.TMax = input.tMax;
    RayQuery<RAY_FLAG_FORCE_OPAQUE | RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH
        | RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES> query;
    query.TraceRayInline(scene, RAY_FLAG_NONE, 0xff, ray);
    while (query.Proceed()) { }
    results[id.x] = query.CommittedStatus() == COMMITTED_TRIANGLE_HIT ? 1 : 0;
}
