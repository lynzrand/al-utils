import Materials.Cloth.DentMaterial;
import Geometry.ClothVertex;

[shader("vertex")]
ClothVertexOutput main(ClothVertexInput input)
{
    return clothVertex(input, _Dent_power);
}
