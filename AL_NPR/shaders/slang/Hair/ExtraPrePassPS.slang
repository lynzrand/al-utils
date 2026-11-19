#include "Color.slang"

[shader("fragment")]
StageOutput main(StageInput input)
{
    return shadeHair(input, true);
}
