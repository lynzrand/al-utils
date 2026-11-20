import Materials.Body.DentMaterial;
import Geometry.DentedShadowCaster;
import Geometry.DentedMesh;

/// Projects the dented, biased body into the shadow map and carries UV0/UV2 for garment coverage.
[shader("vertex")]
ShadowCasterOutput main(DentedMeshInput input)
{
    return shadowCasterVertex(input, _Dent_power);
}
