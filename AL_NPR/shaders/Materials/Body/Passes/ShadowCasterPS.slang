import Materials.Body.DepthMaterial;
import Surface.DepthCoverage;
import Surface.Coverage;

/// Applies ordered coverage at raster pixel positionCS.xy and garment coverage from UV0 in XY and UV2 in ZW.
/// Surviving fragments write zero color and retain raster depth for the depth or shadow attachment.
[shader("fragment")]
float4 main(float4 positionCS : SV_Position, float4 uv0Uv2 : TEXCOORD0) : SV_Target0
{
    float coverage = bodyCoverage(positionCS.xy, uv0Uv2);
    clipCoverage(coverage, 0.5, alphaToMaskAvailable != 0);
    return 0;
}
