import Materials.Body.DentMaterial;
import Geometry.DentedDepthNormals;
import Geometry.DentedMesh;

/// Projects the dented body vertex and forwards its world normal and packed UV0/UV2 for garment coverage.
[shader("vertex")]
DepthNormalsOutput main(DentedMeshInput input)
{
    return depthNormalsVertex(input, _Dent_power);
}
