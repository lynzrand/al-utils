import Face.DepthMaterial;
import DepthCoverage;

[shader("fragment")]
float4 main(float4 positionCS : SV_Position, float3 normalWS : TEXCOORD0) : SV_Target0
{
    float coverage = float(coveredPixel(positionCS.xy, _Dither));
    if (coverage < 0.5) discard;
    return float4(normalize(normalWS), 0);
}
