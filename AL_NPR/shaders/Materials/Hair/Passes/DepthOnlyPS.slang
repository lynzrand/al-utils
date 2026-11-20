import Materials.Hair.Depth;

[shader("fragment")]
float4 main(float4 positionCS : SV_Position) : SV_Target0
{
    clipHairCoverage(positionCS.xy, 0.01);
    return 0;
}
