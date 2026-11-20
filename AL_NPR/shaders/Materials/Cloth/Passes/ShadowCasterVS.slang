import Materials.Cloth.DentMaterial;
import Geometry.DentedShadowCaster;
import Geometry.DentedMesh;

/// Emits the dented, biased shadow clip position and coverage UVs for the shadow caster.
[shader("vertex")]
ShadowCasterOutput main(DentedMeshInput input)
{
    return shadowCasterVertex(input, _Dent_power);
}
