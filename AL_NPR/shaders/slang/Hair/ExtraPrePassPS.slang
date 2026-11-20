import Hair.Bindings;
import Hair.Color;

[shader("fragment")]
float4 main(HairInput input) : SV_Target0
{
    return shadeHair(input, true);
}
