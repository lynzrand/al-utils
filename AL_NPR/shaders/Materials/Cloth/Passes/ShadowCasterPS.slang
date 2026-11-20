import Materials.Cloth.DepthPass;

/// Applies the garment's caster cutoff and returns zero color for surviving shadow depth writes.
[shader("fragment")]
float4 main(DepthInput input) : SV_Target0
{
    return clothDepth(input, true);
}
