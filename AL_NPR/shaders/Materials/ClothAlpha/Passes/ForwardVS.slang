import Materials.ClothAlpha.DentMaterial;
import Geometry.ClothVertex;

/// Projects the dented garment and emits the varyings for forward color shading.
[shader("vertex")]
ClothVertexOutput main(ClothVertexInput input)
{
    return clothVertex(input, _Dent_power);
}
