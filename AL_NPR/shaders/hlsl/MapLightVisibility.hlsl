// Opaque, two-sided, frozen-geometry visibility experiment. No lighting/color,
// alpha coverage, soft shadows, temporal history or screen-space caster inference.
// The TLAS must contain all eligible casters, including offscreen geometry, and
// casterBounds must enclose their current world-space geometry. Skipped meshes
// or stale skinned positions invalidate that completeness contract.
//
// Dispatch ceil(width/8), ceil(height/8), 1 for one selected authored light.
// All input/output textures have the same dimensions and receiver sample identity.
// In particular, do not combine resolved depth with another MSAA sample's normal.
// Output R is visibility; G is 0 invalid, 1 traced/valid, 2 not affected or disabled.
// Invalid results use R=1 but MUST NOT be treated as verified unoccluded samples.
// Apply valid R only to this light's shadow factor; preserve AL skin/color math.
// Point/spot range, cone and distance attenuation remain in that lighting path.
// The host excludes disabled/non-casting renderers, supplies current instance
// transforms, and validates all InstanceIDs and one-hot caster GameObject layers.
// Mask filtering here does not replace those scene-construction responsibilities.

struct MapLight
{
    float3 towardDirection;
    uint type;                 // 0 directional, 1 punctual (point or spot).
    float3 position;
    uint valid;                // Exactly 1 after host validation.
    uint gameObjectCullingMask;
    uint lightingLayerMask;    // Receiver rendering-layer membership.
    uint shadowLayerMask;      // Caster rendering-layer membership, independent.
    uint shadowsEnabled;
};                            // StructuredBuffer stride 48 bytes.

RaytracingAccelerationStructure casters : register(t0);
Texture2D<float4> receiverPosition : register(t1); // xyz world, w=1 valid.
Texture2D<float4> receiverNormal : register(t2);   // xyz geometric world normal.
// x: one-hot GameObject layer; y: rendering layers; z: receives shadows; w: valid.
Texture2D<uint4> receiverFlags : register(t3);
// Indexed by TLAS InstanceID: x one-hot GameObject layer, y rendering layers.
// z/w reserved. Instances must use nonzero hardware InstanceMask.
StructuredBuffer<uint4> casterFlags : register(t4);
StructuredBuffer<MapLight> lights : register(t5);
RWTexture2D<float2> visibility : register(u0);

cbuffer VisibilityFrame : register(b0)
{
    uint2 dimensions;
    uint selectedLight;
    uint lightCount;
    float3 casterBoundsMin;
    float normalBias;
    float3 casterBoundsMax;
    float rayBias;
    uint sceneValid;           // Host asserts complete, current caster geometry.
    uint casterCount;          // Number of entries in casterFlags.
    uint2 reserved;
};                            // 64 bytes.

// Parallel slabs avoid 0 * infinity/NaN at box faces. The same interval clipping
// is used for finite punctual rays and directional rays through the full scene.
bool ClipToCasters(float3 origin, float3 direction, inout float nearT, inout float farT)
{
    [unroll] for (uint axis = 0; axis < 3; ++axis)
    {
        if (direction[axis] == 0.0)
        {
            if (origin[axis] < casterBoundsMin[axis] || origin[axis] > casterBoundsMax[axis])
                return false;
        }
        else
        {
            float a = (casterBoundsMin[axis] - origin[axis]) / direction[axis];
            float b = (casterBoundsMax[axis] - origin[axis]) / direction[axis];
            nearT = max(nearT, min(a, b));
            farT = min(farT, max(a, b));
        }
    }
    return nearT <= farT;
}

[numthreads(8, 8, 1)]
void Main(uint3 dispatchId : SV_DispatchThreadID)
{
    uint2 pixel = dispatchId.xy;
    if (any(pixel >= dimensions)) return;
    visibility[pixel] = float2(1, 0);
    if (sceneValid != 1 || selectedLight >= lightCount || casterCount == 0
        || !all(isfinite(casterBoundsMin)) || !all(isfinite(casterBoundsMax))
        || any(casterBoundsMin > casterBoundsMax)
        || !isfinite(normalBias) || normalBias < 0
        || !isfinite(rayBias) || rayBias <= 0) return;

    MapLight light = lights[selectedLight];
    float4 position = receiverPosition[pixel];
    uint4 flags = receiverFlags[pixel];
    if (light.valid != 1 || light.type > 1 || flags.w != 1 || position.w != 1
        || !all(isfinite(position.xyz)) || flags.x == 0
        || (flags.x & (flags.x - 1)) != 0) return;
    if (flags.z == 0 || light.shadowsEnabled == 0
        || (flags.x & light.gameObjectCullingMask) == 0
        || (flags.y & light.lightingLayerMask) == 0)
    {
        visibility[pixel] = float2(1, 2);
        return;
    }

    float3 normal = receiverNormal[pixel].xyz;
    float normalLength2 = dot(normal, normal);
    if (!all(isfinite(normal)) || !isfinite(normalLength2) || normalLength2 <= 1e-20) return;
    normal *= rsqrt(normalLength2);
    float3 origin = position.xyz + normal * normalBias;
    float3 direction = light.type == 0 ? light.towardDirection : light.position - origin;
    float length2 = dot(direction, direction);
    if (!all(isfinite(origin)) || !all(isfinite(direction))
        || !isfinite(length2) || length2 <= 1e-20) return;
    float distance = sqrt(length2);
    direction /= distance;
    float nearT = rayBias;
    // Directional TMax is clipped to real caster bounds, never a camera far plane.
    float farT = light.type == 0 ? 3.402823466e+38F : distance - rayBias;
    if (farT < nearT) return;
    if (!ClipToCasters(origin, direction, nearT, farT))
    {
        visibility[pixel] = float2(1, 1);
        return;
    }
    if (!isfinite(nearT) || !isfinite(farT)) return;

    RayDesc ray;
    ray.Origin = origin;
    ray.Direction = direction;
    ray.TMin = nearT;
    ray.TMax = farT;
    // FORCE_NON_OPAQUE allows explicit independent caster-mask filtering. This
    // is not alpha testing: every accepted triangle is fully opaque/two-sided.
    RayQuery<RAY_FLAG_FORCE_NON_OPAQUE | RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH
        | RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES> query;
    query.TraceRayInline(casters, RAY_FLAG_NONE, 0xff, ray);
    bool invalidInstance = false;
    while (query.Proceed())
    {
        if (query.CandidateType() != CANDIDATE_NON_OPAQUE_TRIANGLE) continue;
        uint instance = query.CandidateInstanceID();
        if (instance >= casterCount)
        {
            invalidInstance = true;
            continue;
        }
        uint4 caster = casterFlags[instance];
        if ((caster.x & light.gameObjectCullingMask) != 0
            && (caster.y & light.shadowLayerMask) != 0)
            query.CommitNonOpaqueTriangleHit();
    }
    if (invalidInstance) return;
    visibility[pixel] = float2(query.CommittedStatus() == COMMITTED_TRIANGLE_HIT ? 0 : 1, 1);
}
