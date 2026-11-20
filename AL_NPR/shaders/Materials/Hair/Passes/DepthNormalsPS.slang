import Materials.Hair.Depth;

/// Clips tip coverage using pixel XY, then writes the normalized world normal directly into RGB and zero into
/// A.
[shader("fragment")]
float4 main(float4 positionCS : SV_Position, float3 normalWS : TEXCOORD0) : SV_Target0
{
    clip(hairCoverage(positionCS.xy) - 0.01);
    return float4(normalize(normalWS), 0);
}
