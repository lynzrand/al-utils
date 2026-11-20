// Unity-owned structured buffer, stride 4. Binding/ordering smoke only.
RWStructuredBuffer<uint> outputValues : register(u0);
cbuffer WriteParameters : register(b0) { uint count; uint seed; };
[numthreads(64, 1, 1)]
void Main(uint3 id : SV_DispatchThreadID)
{
    // Read-modify-write permits a preceding Unity producer to participate in
    // the ordering assertion. Zero input gives the basic known-write pattern.
    if (id.x < count) outputValues[id.x] ^= seed ^ (0x9e3779b9u * id.x);
}
