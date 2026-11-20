#include "Depth.slang"

[shader("fragment")]
float4 main(float4 positionCS : SV_Position) : SV_Target0
{
    clipCoverage(hairCoverage(positionCS.xy), 0.001, alphaToMaskAvailable != 0);
    return 0;
}
