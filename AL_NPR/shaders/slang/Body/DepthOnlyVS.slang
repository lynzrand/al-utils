import Body.DentMaterial;
import Geometry.DentedDepthOnly;
import Geometry.DentedMesh;

[shader("vertex")]
DepthOutput main(DentedMeshInput input)
{
    return depthOnlyVertex(input, _Dent_power);
}
