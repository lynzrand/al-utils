import Visibility.OpaqueRay;

// Native ProbeRay records have a 32-byte stride and carry a unit direction.
struct ProbeRay
{
    /// World-space start of the probe ray.
    float3 origin;
    /// Minimum distance along the unit ray in world units, inclusive.
    float nearT;
    /// Finite world-space unit vector. The probe rejects a squared length differing from one by more than 0.001.
    float3 direction;
    /// Maximum world-space ray distance. It must exceed nearT.
    float farT;
};

/// Native ProbeRay records, one 32-byte record per ray.
StructuredBuffer<ProbeRay> rays : register(t1);
/// One word per ray. Zero means clear, one means an opaque triangle hit, and two means invalid ray input.
RWStructuredBuffer<uint> results : register(u0);
cbuffer Parameters : register(b0)
{
    /// Number of valid input and output slots to process.
    uint rayCount;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void Main(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= rayCount) return;
    ProbeRay input = rays[id.x];
    float lengthSquared = dot(input.direction, input.direction);
    if (!all(isfinite(input.origin)) || !all(isfinite(input.direction)) || !isfinite(lengthSquared)
        || abs(lengthSquared - 1) > 0.001 || !isfinite(input.nearT) || !isfinite(input.farT)
        || input.nearT < 0 || input.farT <= input.nearT)
    {
        results[id.x] = 2;
        return;
    }
    results[id.x] = occluded(rayInterval(input.origin, input.direction, input.nearT, input.farT)) ? 1 : 0;
}
