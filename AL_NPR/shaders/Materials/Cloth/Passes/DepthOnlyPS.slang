import Materials.Cloth.DepthPass;

/// Clips the garment silhouette for depth writes and returns zero to the color target.
[shader("fragment")]
float4 main(DepthInput input) : SV_Target0
{
    return clothDepth(input, false);
}
