import ClothAlpha.DentMaterial;
import Geometry.DentedDepthNormals;
import Geometry.DentedMesh;

[shader("vertex")]
DepthNormalsOutput main(DentedMeshInput input)
{
    return depthNormalsVertex(input, _Dent_power);
}
