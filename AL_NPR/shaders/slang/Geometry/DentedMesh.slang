SamplerState sampler_Create_dent_texture : register(s0);
Texture2D<float4> _Create_dent_texture : register(t0);

public struct DentedMeshInput
{
    public float4 positionOS : POSITION0;
    public float3 normalOS : NORMAL0;
    public float4 tangentOS : TANGENT0;
    public float4 color : COLOR0;
    public float4 uv1 : TEXCOORD1;
    public float4 uv0 : TEXCOORD0;
    public float4 uv2 : TEXCOORD2;
};

// Vertex color encodes the displacement direction around its midpoint.
public float3 meshDent(float2 uv, float3 color, float strength)
{
    float height = _Create_dent_texture.SampleLevel(sampler_Create_dent_texture, uv, 0).r * strength;
    return mad(color, height * -0.14, height * 0.07);
}
