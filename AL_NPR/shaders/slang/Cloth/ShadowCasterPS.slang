import Cloth.DepthPass;

[shader("fragment")]
float4 main(DepthInput input) : SV_Target0
{
    return clothDepth(input, true);
}
