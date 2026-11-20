import Cloth.DepthPass;

struct DepthNormalsInput
{
    float4 position : SV_POSITION;
    float3 worldNormal : TEXCOORD0;
    float4 uv : TEXCOORD1;
};

[shader("fragment")]
float4 main(DepthNormalsInput input) : SV_Target0
{
    ClothDepthCoverage coverage = depthCoverage(input.position.xy, input.uv, false);
    clip(coverage.opacity - coverage.cutoff);
    return float4(normalize(input.worldNormal), 0);
}
