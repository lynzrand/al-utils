import Materials.Hair.Depth;

/// Clips at 0.01 tip coverage and returns zero color. The pass writes rasterized depth for surviving pixels.
[shader("fragment")]
float4 main(float4 positionCS : SV_Position) : SV_Target0
{
    clipHairCoverage(positionCS.xy, 0.01);
    return 0;
}
