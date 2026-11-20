// Both Unity probes use the host's frozen opaque triangle TLAS at t0.
/// Frozen opaque triangle acceleration structure supplied by the Unity probe.
public RaytracingAccelerationStructure scene : register(t0);

/// Constructs a world-space ray segment. With a unit direction, nearT and farT are world-space distances.
public RayDesc rayInterval(float3 origin, float3 direction, float nearT, float farT)
{
    RayDesc ray;
    ray.Origin = origin;
    ray.Direction = direction;
    ray.TMin = nearT;
    ray.TMax = farT;
    return ray;
}

/// Returns true at the first committed opaque triangle within the supplied interval.
public bool occluded(RayDesc ray)
{
    RayQuery<RAY_FLAG_FORCE_OPAQUE | RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH
           | RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES> query;
    query.TraceRayInline(scene, RAY_FLAG_NONE, 0xff, ray);
    while (query.Proceed()) {}
    return query.CommittedStatus() == COMMITTED_TRIANGLE_HIT;
}
