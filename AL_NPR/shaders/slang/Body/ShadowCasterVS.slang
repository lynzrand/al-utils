import Body.DentMaterial;
import Geometry.DentedShadowCaster;
import Geometry.DentedMesh;

[shader("vertex")]
ShadowCasterOutput main(DentedMeshInput input)
{
    return shadowCasterVertex(input, _Dent_power);
}
