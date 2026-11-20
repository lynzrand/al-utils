#include "DepthMaterial.slang"
import Coverage;

[shader("fragment")]
float4 main(float4 positionCS : SV_Position) : SV_Target0
{
    float coverage = float(coveredPixel(positionCS.xy, _Dither));
    clipCoverage(coverage, 0.5, alphaToMaskAvailable != 0);
    return 0;
}
