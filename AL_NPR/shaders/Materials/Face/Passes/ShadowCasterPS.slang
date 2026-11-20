import Materials.Face.DepthMaterial;
import Surface.DepthCoverage;
import Surface.Coverage;

/// Applies ordered coverage at raster pixel positionCS.xy. Surviving fragments write zero color and retain
/// raster depth for the depth or shadow attachment.
[shader("fragment")]
float4 main(float4 positionCS : SV_Position) : SV_Target0
{
    float coverage = float(coveredPixel(positionCS.xy, _Dither));
    clipCoverage(coverage, 0.5, alphaToMaskAvailable != 0);
    return 0;
}
