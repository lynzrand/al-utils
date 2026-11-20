import Materials.Body.DepthMaterial;

/// Writes the normalized interpolated world normal in RGB and zero in A for covered pixels. positionCS.xy is
/// the raster pixel position. uv0Uv2 packs garment-mask UV0 in XY and UV2 in ZW.
[shader("fragment")]
float4 main(float4 positionCS : SV_Position, float3 normalWS : TEXCOORD0, float4 uv0Uv2 : TEXCOORD1) : SV_Target0
{
    float coverage = bodyCoverage(positionCS.xy, uv0Uv2);
    if (coverage < 0.5) discard;
    return float4(normalize(normalWS), 0);
}
