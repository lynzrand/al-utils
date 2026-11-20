import Materials.Hair.Bindings;
import Materials.Hair.Color;

/// Returns the base hair RGB with unit alpha in pixels surviving ordered coverage.
[shader("fragment")]
float4 main(HairInput input) : SV_Target0
{
    return shadeHair(input, true);
}
