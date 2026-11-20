#include "DepthMaterial.slang"

[shader("fragment")]
float4 main(float4 positionCS : SV_Position, float4 uv0Uv2 : TEXCOORD0) : SV_Target0
{
    float coverage = bodyCoverage(positionCS.xy, uv0Uv2);
    clipCoverage(coverage, 0.5, alphaToMaskAvailable != 0);
    return 0;
}
