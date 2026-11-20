// Replay control for map002 materials with proven opaque coverage.
struct Interpolators
{
    float4 position : SV_Position;
    float3 unusedWorldPosition : TEXCOORD0;
    float4 uv : TEXCOORD1;
};

float4 main(Interpolators input) : SV_Target
{
    return 0;
}
