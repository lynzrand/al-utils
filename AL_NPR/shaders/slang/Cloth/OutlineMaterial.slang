cbuffer UnityPerMaterial : register(b2)
{
    float _VertexColorNormal : packoffset(c31.x);
    float _Dent_power : packoffset(c31.y);
    float _LineWidthS : packoffset(c31.z);
    float _Line_width : packoffset(c31.w);
};

SamplerState sampler_Detail_mask_01 : register(s0);
SamplerState sampler_Create_dent_texture : register(s1);
Texture2D<float4> _Detail_mask_01 : register(t0);
Texture2D<float4> _Create_dent_texture : register(t1);
