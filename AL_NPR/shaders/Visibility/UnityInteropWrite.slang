// A Unity producer may fill the buffer before the native dispatch. Reading its
// previous contents makes ordering observable in addition to validating the UAV binding.
/// Unity's writable word buffer. The probe XORs its pattern into the preceding producer's value.
RWStructuredBuffer<uint> outputValues : register(u0);
cbuffer WriteParameters : register(b0)
{
    /// Number of uint elements supplied by the host.
    uint count;
    /// Host pattern mixed with each element index during the XOR read-modify-write.
    uint seed;
};

[shader("compute")]
[numthreads(64, 1, 1)]
void Main(uint3 id : SV_DispatchThreadID)
{
    if (id.x < count)
        outputValues[id.x] ^= seed ^ (0x9e3779b9u * id.x);
}
