/// Vertex material layout for the garment dent displacement.
public cbuffer UnityPerMaterial : register(b2)
{
    /// Scales the dent texture's red channel before converting mesh vertex color to displacement.
    public float _Dent_power : packoffset(c31.z);
};
