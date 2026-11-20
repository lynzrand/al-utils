// One dispatch tests one authored light against the frozen caster TLAS. The host
// supplies current instance transforms and bounds for all eligible casters.
// Receiver position, geometric normal and flags must describe the same depth sample.
struct MapLight
{
    /// World-space direction from a receiver toward a directional light. Punctual lights use position.
    float3 towardDirection;
    /// Native light kind. Zero selects a directional ray and one selects a point or spot light.
    uint type;
    /// World-space light center used to set the end of a punctual shadow ray.
    float3 position;
    /// The host sets this to one when the light record can be used.
    uint valid;
    /// Unity GameObject layer bits accepted for both receivers and casters.
    uint gameObjectCullingMask;
    /// Rendering-layer bits that a receiver must share with this light.
    uint lightingLayerMask;
    /// Rendering-layer bits that a caster must share with this light.
    uint shadowLayerMask;
    /// Zero makes eligible receivers fully visible without a ray.
    uint shadowsEnabled;
};                             // Native stride is 48 bytes.

/// Frozen top-level acceleration structure. InstanceID indexes casterFlags.
RaytracingAccelerationStructure casters : register(t0);
/// World-space receiver XYZ. W must be one for a valid depth sample.
Texture2D<float4> receiverPosition : register(t1);
/// World-space geometric normal in XYZ for the origin offset. W is unused.
Texture2D<float4> receiverNormal : register(t2);
/// X is the one-hot GameObject layer, Y the rendering-layer mask, Z enables shadows and W marks a valid receiver.
Texture2D<uint4> receiverFlags : register(t3);
/// One record per InstanceID. X carries the GameObject layer bit and Y the rendering-layer mask. ZW are unused.
StructuredBuffer<uint4> casterFlags : register(t4);
/// Host light records indexed by selectedLight, with a native stride of 48 bytes.
StructuredBuffer<MapLight> lights : register(t5);
/// Per-pixel X is visibility (0 blocked, 1 clear). Y is the status (0 invalid, 1 tested, 2 unaffected).
RWTexture2D<float2> visibility : register(u0);

cbuffer VisibilityFrame : register(b0)
{
    /// Width and height in pixels of the receiver inputs and visibility output.
    uint2 dimensions;
    /// Index into lights for this whole dispatch.
    uint selectedLight;
    /// Number of uploaded records in lights.
    uint lightCount;
    /// Minimum world-space corner enclosing the frozen casters. Rays are clipped to this box.
    float3 casterBoundsMin;
    /// World-space distance to move the ray origin along the normalized receiver normal.
    float normalBias;
    /// Maximum world-space corner of the same caster box.
    float3 casterBoundsMax;
    /// Minimum world-space ray distance. A punctual ray also stops this far short of its light.
    float rayBias;
    /// The host sets this to one when the caster data and acceleration structure are ready.
    uint sceneValid;
    /// Number of caster flag records available for TLAS instance lookups.
    uint casterCount;
    /// Unused words that preserve the native frame layout.
    uint2 reserved;
};

static const float2 invalidReceiver = float2(1, 0);
static const float2 unoccluded = float2(1, 1);
static const float2 occluded = float2(0, 1);
static const float2 unaffected = float2(1, 2);

/// Checks host counts, finite bounds and bias values before indexing buffers or issuing a ray.
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

/// Tests candidate triangle instances against the light's caster masks and returns the visibility/status pair.
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

/// Validates one receiver, applies the two layer masks and traces the selected light.
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
