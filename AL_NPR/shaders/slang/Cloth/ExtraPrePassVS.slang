import Cloth.OutlineMaterial;
import Geometry.ClothOutlineVertex;

[shader("vertex")]
ClothOutlineOutput main(ClothOutlineInput input)
{
    return clothOutlineVertex(input, _Dent_power, _LineWidthS * _Line_width, _VertexColorNormal);
}
