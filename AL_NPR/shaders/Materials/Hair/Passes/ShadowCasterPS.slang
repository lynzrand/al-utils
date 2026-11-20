import Materials.Hair.Depth;

/// Clips the atlas pixel using the shadow pass's 0.001 threshold. Surviving fragments write rasterized depth.
[shader("fragment")]
float4 main(float4 positionCS : SV_Position) : SV_Target0
{
    clipHairCoverage(positionCS.xy, 0.001);
    return 0;
}
