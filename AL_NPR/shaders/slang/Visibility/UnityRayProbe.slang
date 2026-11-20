import Visibility.OpaqueRay;

// Native ProbeRay records have a 32-byte stride and carry a unit direction.
struct ProbeRay
{
    float3 origin;
    float nearT;
    float3 direction;
    float farT;
};

StructuredBuffer<ProbeRay> rays : register(t1);
RWStructuredBuffer<uint> results : register(u0);
cbuffer Parameters : register(b0) { uint rayCount; }

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
