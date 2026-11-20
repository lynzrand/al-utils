import Materials.ClothAlpha.DentMaterial;
import Geometry.DentedDepthNormals;
import Geometry.DentedMesh;

/// Emits the dented clip position, mesh normal, and coverage UVs for the depth-normal pass.
[shader("vertex")]
DepthNormalsOutput main(DentedMeshInput input)
{
    return depthNormalsVertex(input, _Dent_power);
}
