cbuffer Globals : register(b0)
{
    // c78 .x unity_MatrixVP
    float4 GlobalsData[131];
};

cbuffer UnityPerDraw : register(b1)
{
    float4 UnityPerDrawData[4];
};

cbuffer UnityPerMaterial : register(b2)
{
    // c24 .x _Dent_power
    float4 UnityPerMaterialData[25];
};

SamplerState sampler_Create_dent_texture : register(s0);
Texture2D<float4> _Create_dent_texture : register(t0);

struct StageInput
{
    float4 v0 : POSITION0;
    float3 v1 : NORMAL0;
    float4 unused2 : TANGENT0;
    float4 v3 : COLOR0;
    float4 v4 : TEXCOORD1;
    float4 v5 : TEXCOORD0;
    float4 v6 : TEXCOORD2;
};

struct StageOutput
{
    float4 gl_Position : SV_POSITION;
    float4 o1 : TEXCOORD0;
};

[shader("vertex")]
StageOutput main(StageInput stage_input)
{
    float4 gl_Position = 0;
    float4 v0 = 0;
    float3 v1 = 0;
    float4 v3 = 0;
    float4 v4 = 0;
    float4 v5 = 0;
    float4 v6 = 0;
    float4 o1 = 0;
    float4 r0 = 0;
    float4 r1 = 0;
    v0 = stage_input.v0;
    v1 = stage_input.v1;
    v3 = stage_input.v3;
    v4 = stage_input.v4;
    v5 = stage_input.v5;
    v6 = stage_input.v6;
    r0.x = _Create_dent_texture.SampleLevel(sampler_Create_dent_texture, v4.xy, 0.0f).x;
    r0.x *= UnityPerMaterialData[24u].x;
    r0.xy = r0.xx * float2(0.07f, -0.14f);
    r0.xyz = mad(v3.xyz, r0.yyy, r0.xxx);
    r0.xyz = r0.xyz + v0.xyz;
    r1.xyz = r0.yyy * UnityPerDrawData[1u].xyz;
    r0.xyw = mad(UnityPerDrawData[0u].xyz, r0.xxx, r1.xyz);
    r0.xyz = mad(UnityPerDrawData[2u].xyz, r0.zzz, r0.xyw);
    r0.xyz = r0.xyz + UnityPerDrawData[3u].xyz;
    r0.xyz = mad(GlobalsData[130u].xyz, GlobalsData[129u].xxx, r0.xyz);
    r1.xyz = v1.yyy * UnityPerDrawData[1u].xyz;
    r1.xyz = mad(UnityPerDrawData[0u].xyz, v1.xxx, r1.xyz);
    r1.xyz = mad(UnityPerDrawData[2u].xyz, v1.zzz, r1.xyz);
    r0.w = dot(r1.xyz, r1.xyz);
    r0.w = max(r0.w, 1.1754944e-38f);
    r0.w = rsqrt(r0.w);
    r1.xyz = r0.www * r1.xyz;
    r0.w = clamp(dot(GlobalsData[130u].xyz, r1.xyz).x, 0.0f, 1.0f);
    r0.w = (-r0.wwww).w + 1.0f;
    r0.w *= GlobalsData[129u].y;
    r0.xyz = mad(r1.xyz, r0.www, r0.xyz);
    r1 = r0.yyyy * GlobalsData[79u];
    r1 = mad(GlobalsData[78u], r0.xxxx, r1);
    r0 = mad(GlobalsData[80u], r0.zzzz, r1);
    r0 += GlobalsData[81u];
    gl_Position.z = min(r0.z, 1.0f);
    gl_Position = float4(r0.x, r0.y, gl_Position.z, r0.w);
    o1 = float4(v5.x, v5.y, o1.z, o1.w);
    o1 = float4(o1.x, o1.y, v6.x, v6.y);
    StageOutput stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.o1 = o1;
    return stage_output;
}
