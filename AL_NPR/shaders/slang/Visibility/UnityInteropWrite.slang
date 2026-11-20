// A Unity producer may fill the buffer before the native dispatch. Reading its
// previous contents makes ordering observable in addition to validating the UAV binding.
RWStructuredBuffer<uint> outputValues : register(u0);
cbuffer WriteParameters : register(b0)
{
    uint count;
    uint seed;
};

[shader("compute")]
[numthreads(64, 1, 1)]
void Main(uint3 id : SV_DispatchThreadID)
{
    if (id.x < count)
        outputValues[id.x] ^= seed ^ (0x9e3779b9u * id.x);
}
