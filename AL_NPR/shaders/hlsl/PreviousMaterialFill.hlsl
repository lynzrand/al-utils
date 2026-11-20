// Reconstructed from the November 18 per-light default. The two functions
// below describe only the supplemental neutral diffuse fill. Both materials
// already had authored palettes, reflections and per-light toon shading.

float3 PreviousSkinDiffuse(float3 shadedPalette)
{
    return shadedPalette;
}

float3 PreviousFabricDiffuse(float3 shadedFabric, float3 processedFabricColor,
                             float3 ambientSH, float mergedBand)
{
    float ambient = saturate(dot(ambientSH, float3(0.212673, 0.715152, 0.072175)));
    float fill = 0.84 * ambient + 0.49 * mergedBand;
    return shadedFabric + processedFabricColor * fill;
}
