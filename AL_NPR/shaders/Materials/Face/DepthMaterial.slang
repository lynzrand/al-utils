/// Material properties at the serialized byte offsets for this pass.
public cbuffer UnityPerMaterial : register(b1)
{
    /// Fraction of the ordered 4×4 screen pattern allowed to pass, from zero to one.
    public float _Dither : packoffset(c33.w);
};
