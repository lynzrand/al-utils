// One dispatch tests one authored light against the frozen caster TLAS. The host
// supplies current instance transforms and bounds for all eligible casters.
// Receiver position, geometric normal and flags must describe the same depth sample.
struct MapLight
{
    float3 towardDirection;
    uint type;                 // 0 directional, 1 punctual (point or spot).
    float3 position;
    uint valid;
    uint gameObjectCullingMask;
    uint lightingLayerMask;    // Receiver rendering layers.
    uint shadowLayerMask;      // Caster rendering layers.
    uint shadowsEnabled;
};                             // Native stride is 48 bytes.

RaytracingAccelerationStructure casters : register(t0);
Texture2D<float4> receiverPosition : register(t1);
Texture2D<float4> receiverNormal : register(t2);
// x: one-hot GameObject layer, y: rendering layers, z: receives shadows, w: valid.
Texture2D<uint4> receiverFlags : register(t3);
// Indexed by TLAS InstanceID. x and y use the same layer encoding as receiverFlags.
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
    uint sceneValid;
    uint casterCount;
    uint2 reserved;
};

static const float2 invalidReceiver = float2(1, 0);
static const float2 unoccluded = float2(1, 1);
static const float2 occluded = float2(0, 1);
static const float2 unaffected = float2(1, 2);

bool validFrame()
{
    return sceneValid == 1 && selectedLight < lightCount && casterCount != 0
        && all(isfinite(casterBoundsMin)) && all(isfinite(casterBoundsMax))
        && all(casterBoundsMin <= casterBoundsMax) && isfinite(normalBias)
        && normalBias >= 0 && isfinite(rayBias) && rayBias > 0;
}

// Parallel slabs avoid 0 * infinity at box faces. Punctual rays initially end
// at the lamp, while directional rays span the entire scene's caster bounds.
bool clipToCasters(inout RayDesc ray)
{
    [unroll] for (uint axis = 0; axis < 3; ++axis)
    {
        if (ray.Direction[axis] == 0)
        {
            if (ray.Origin[axis] < casterBoundsMin[axis] || ray.Origin[axis] > casterBoundsMax[axis])
                return false;
        }
        else
        {
            float a = (casterBoundsMin[axis] - ray.Origin[axis]) / ray.Direction[axis];
            float b = (casterBoundsMax[axis] - ray.Origin[axis]) / ray.Direction[axis];
            ray.TMin = max(ray.TMin, min(a, b));
            ray.TMax = min(ray.TMax, max(a, b));
        }
    }
    return ray.TMin <= ray.TMax;
}

float2 traceCasters(RayDesc ray, MapLight light)
{
    // Expose all triangles as candidates so independent caster layers can filter hits.
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
        if ((caster.x & light.gameObjectCullingMask) != 0 && (caster.y & light.shadowLayerMask) != 0)
            query.CommitNonOpaqueTriangleHit();
    }
    if (invalidInstance) return invalidReceiver;
    return query.CommittedStatus() == COMMITTED_TRIANGLE_HIT ? occluded : unoccluded;
}

float2 receiverVisibility(uint2 pixel)
{
    if (!validFrame()) return invalidReceiver;
    MapLight light = lights[selectedLight];
    float4 position = receiverPosition[pixel];
    uint4 flags = receiverFlags[pixel];
    bool oneLayer = flags.x != 0 && (flags.x & (flags.x - 1)) == 0;
    if (light.valid != 1 || light.type > 1 || flags.w != 1 || position.w != 1
        || !all(isfinite(position.xyz)) || !oneLayer)
        return invalidReceiver;
    if (flags.z == 0 || light.shadowsEnabled == 0 || (flags.x & light.gameObjectCullingMask) == 0
        || (flags.y & light.lightingLayerMask) == 0)
        return unaffected;

    float3 normal = receiverNormal[pixel].xyz;
    float lengthSquared = dot(normal, normal);
    if (!all(isfinite(normal)) || !isfinite(lengthSquared) || lengthSquared <= 1e-20)
        return invalidReceiver;
    RayDesc ray;
    ray.Origin = position.xyz + (normal * rsqrt(lengthSquared)) * normalBias;
    float3 direction = light.type == 0 ? light.towardDirection : light.position - ray.Origin;
    lengthSquared = dot(direction, direction);
    if (!all(isfinite(ray.Origin)) || !all(isfinite(direction)) || !isfinite(lengthSquared) || lengthSquared <= 1e-20)
        return invalidReceiver;
    float distance = sqrt(lengthSquared);
    ray.Direction = direction / distance;
    ray.TMin = rayBias;
    ray.TMax = light.type == 0 ? 3.402823466e+38f : distance - rayBias;
    if (ray.TMax < ray.TMin) return invalidReceiver;
    if (!clipToCasters(ray)) return unoccluded;
    if (!isfinite(ray.TMin) || !isfinite(ray.TMax)) return invalidReceiver;
    return traceCasters(ray, light);
}

[shader("compute")]
[numthreads(8, 8, 1)]
void Main(uint3 id : SV_DispatchThreadID)
{
    if (all(id.xy < dimensions))
        visibility[id.xy] = receiverVisibility(id.xy);
}
