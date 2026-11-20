import Materials.ClothAlpha.DentMaterial;
import Geometry.DentedDepthOnly;
import Geometry.DentedMesh;

/// Emits the dented clip position and both coverage UVs for the depth pass.
[shader("vertex")]
DepthOutput main(DentedMeshInput input)
{
    return depthOnlyVertex(input, _Dent_power);
}
