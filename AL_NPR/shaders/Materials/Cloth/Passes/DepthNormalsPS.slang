import Materials.Cloth.DepthPass;

/// Rasterizer values for silhouette clipping and writing the geometric world normal.
struct DepthNormalsInput
{
    /// Rasterized position. XY are render-target pixel coordinates for the dither pattern.
    float4 position : SV_POSITION;
    /// Interpolated mesh normal in world space, normalized again before writing the normals target.
    float3 worldNormal : TEXCOORD0;
    /// XY carries mesh UV0 and ZW carries mesh UV2 for the alternative garment coverage coordinates.
    float4 uv : TEXCOORD1;
};

/// Discards uncovered cloth and writes the normalized world-space mesh normal in RGB with zero alpha.
[shader("fragment")]
float4 main(DepthNormalsInput input) : SV_Target0
{
    ClothDepthCoverage coverage = depthCoverage(input.position.xy, input.uv, false);
    clip(coverage.opacity - coverage.cutoff);
    return float4(normalize(input.worldNormal), 0);
}
