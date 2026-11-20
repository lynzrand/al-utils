#define HAIR_NPR
#include "Color.slang"

[shader("fragment")]
float4 main(HairInput input) : SV_Target0
{
    return shadeHair(input, true);
}
