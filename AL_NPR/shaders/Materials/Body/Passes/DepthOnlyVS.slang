import Materials.Body.DentMaterial;
import Geometry.DentedDepthOnly;
import Geometry.DentedMesh;

/// Projects the dented body vertex into camera clip space for depth-only rendering. The returned UV0/UV2 pair
/// carries the garment mask coordinates.
[shader("vertex")]
DepthOutput main(DentedMeshInput input)
{
    return depthOnlyVertex(input, _Dent_power);
}
