cbuffer UnityPerMaterial : register(b2)
{
    float _Dent_power : packoffset(c31.y);
};

SamplerState sampler_Create_dent_texture : register(s0);
Texture2D<float4> _Create_dent_texture : register(t0);
