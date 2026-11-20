import Materials.ClothAlpha.OutlineMaterial;
import Geometry.ClothOutlineVertex;

/// Extrudes the colored cloth outline and emits its clip position and color-pass varyings.
[shader("vertex")]
ClothOutlineOutput main(ClothOutlineInput input)
{
    return clothOutlineVertex(input, _Dent_power, _LineWidthS * _Line_width, _VertexColorNormal);
}
