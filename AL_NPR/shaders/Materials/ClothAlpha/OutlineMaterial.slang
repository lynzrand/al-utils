/// Vertex material controls for dent displacement and outline extrusion.
public cbuffer UnityPerMaterial : register(b2)
{
    /// Blends between mesh-normal extrusion and the vertex-color/dent contribution to the outline.
    public float _VertexColorNormal : packoffset(c31.y);
    /// Scales the dent texture's red channel before converting mesh vertex color to displacement.
    public float _Dent_power : packoffset(c31.z);
    /// Multiplier on the authored outline width, shared by extrusion, pigment, and alpha dilation.
    public float _LineWidthS : packoffset(c31.w);
    /// Authored outline width before multiplying by `_LineWidthS` and the detail mask.
    public float _Line_width : packoffset(c32.x);
};
