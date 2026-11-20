/// Material properties at the serialized byte offsets for this pass.
public cbuffer UnityPerMaterial : register(b2)
{
    /// Strength of vertex displacement along the vertex-color dent direction and of the matching fragment
    /// mask.
    public float _Dent_power : packoffset(c24.x);
};
