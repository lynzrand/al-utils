import Body.Bindings;
import Body.Color;

[shader("fragment")]
float4 main(StageInput input) : SV_Target0
{
    return shadeBody(input);
}
