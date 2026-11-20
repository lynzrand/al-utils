import Materials.Hair.Bindings;
import Materials.Hair.Color;

[shader("fragment")]
float4 main(HairInput input) : SV_Target0
{
    return shadeHair(input, true);
}
