import Materials.Face.DepthMaterial;
import Surface.DepthCoverage;

/// Writes the normalized interpolated world normal in RGB and zero in A for covered pixels. positionCS.xy is
/// the raster pixel position.
[shader("fragment")]
float4 main(float4 positionCS : SV_Position, float3 normalWS : TEXCOORD0) : SV_Target0
{
    float coverage = float(coveredPixel(positionCS.xy, _Dither));
    if (coverage < 0.5) discard;
    return float4(normalize(normalWS), 0);
}
