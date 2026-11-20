public cbuffer UnityPerMaterial : register(b2)
{
    public float _VertexColorNormal : packoffset(c31.x);
    public float _Dent_power : packoffset(c31.y);
    public float _LineWidthS : packoffset(c31.z);
    public float _Line_width : packoffset(c31.w);
};
