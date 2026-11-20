import Materials.Body.Bindings;
import Materials.Body.Color;

/// Shades the extruded body outline with fog and ordered coverage. Alpha carries coverage when alpha-to-mask
/// is available.
[shader("fragment")]
float4 main(StageInput input) : SV_Target0
{
    return shadeBody(input);
}
