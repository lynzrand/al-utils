import Materials.Body.Bindings;
import Materials.Body.Color;

/// Shades a covered body fragment into HDR RGB. Alpha carries coverage when alpha-to-mask is available, and
/// one otherwise.
[shader("fragment")]
float4 main(StageInput input) : SV_Target0
{
    return shadeBody(input);
}
