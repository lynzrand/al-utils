cbuffer Globals : register(b0)
{
    // c5 .x _MainLightPosition
    // c82 .x unity_MatrixVP
    float4 GlobalsData[86];
};

cbuffer UnityPerDraw : register(b1)
{
    float4 UnityPerDrawData[10];
};

cbuffer UnityPerMaterial : register(b2)
{
    // c31 .y _Dent_power
    float4 UnityPerMaterialData[32];
};

SamplerState sampler_Create_dent_texture : register(s0);
Texture2D<float4> _Create_dent_texture : register(t0);

struct StageInput
{
    float4 v0 : POSITION0;
    float3 v1 : NORMAL0;
    float4 v2 : TANGENT0;
    float4 v3 : COLOR0;
    float4 v4 : TEXCOORD1;
    float4 v5 : TEXCOORD2;
    float4 v6 : TEXCOORD0;
};

struct StageOutput
{
    float4 gl_Position : SV_POSITION;
    float4 o1 : TEXCOORD0;
    float3 o2 : TEXCOORD1;
    float4 o3 : TEXCOORD2;
    float4 o4 : TEXCOORD3;
    float4 o5 : TEXCOORD4;
    float4 o6 : TEXCOORD5;
    float4 o7 : TEXCOORD6;
    float4 o8 : TEXCOORD7;
    float4 o9 : TEXCOORD8;
    float3 o10 : NORMAL0;
};

[shader("vertex")]
StageOutput main(StageInput stage_input)
{
    float4 gl_Position = 0;
    float4 v0 = 0;
    float3 v1 = 0;
    float4 v2 = 0;
    float4 v3 = 0;
    float4 v4 = 0;
    float4 v5 = 0;
    float4 v6 = 0;
    float4 o1 = 0;
    float3 o2 = 0;
    float4 o3 = 0;
    float4 o4 = 0;
    float4 o5 = 0;
    float4 o6 = 0;
    float4 o7 = 0;
    float4 o8 = 0;
    float4 o9 = 0;
    float3 o10 = 0;
    float4 r0 = 0;
    float4 r1 = 0;
    v0 = stage_input.v0;
    v1 = stage_input.v1;
    v2 = stage_input.v2;
    v3 = stage_input.v3;
    v4 = stage_input.v4;
    v5 = stage_input.v5;
    v6 = stage_input.v6;
    r0.x = _Create_dent_texture.SampleLevel(sampler_Create_dent_texture, v4.xy, 0.0f).x;
    r0.x *= UnityPerMaterialData[31u].y;
    r0.xy = r0.xx * float2(0.07f, -0.14f);
    r0.xyz = mad(v3.xyz, r0.yyy, r0.xxx);
    r0.xyz = r0.xyz + v0.xyz;
    r1.xyz = r0.yyy * UnityPerDrawData[1u].xyz;
    r0.xyw = mad(UnityPerDrawData[0u].xyz, r0.xxx, r1.xyz);
    r0.xyz = mad(UnityPerDrawData[2u].xyz, r0.zzz, r0.xyw);
    r0.xyz = r0.xyz + UnityPerDrawData[3u].xyz;
    r1 = r0.yyyy * GlobalsData[83u];
    r1 = mad(GlobalsData[82u], r0.xxxx, r1);
    r1 = mad(GlobalsData[84u], r0.zzzz, r1);
    o1 = float4(r0.x, r0.y, r0.z, o1.w);
    gl_Position = r1 + GlobalsData[85u];
    o1.w = 0.0f;
    r0.x = dot(v1, UnityPerDrawData[4u].xyz);
    r0.y = dot(v1, UnityPerDrawData[5u].xyz);
    r0.z = dot(v1, UnityPerDrawData[6u].xyz);
    r0.w = dot(r0.xyz, r0.xyz);
    r0.w = max(r0.w, 1.1754944e-38f);
    r0.w = rsqrt(r0.w);
    o2 = r0.www * r0.xyz;
    r0.xyz = v2.yyy * UnityPerDrawData[1u].xyz;
    r0.xyz = mad(UnityPerDrawData[0u].xyz, v2.xxx, r0.xyz);
    r0.xyz = mad(UnityPerDrawData[2u].xyz, v2.zzz, r0.xyz);
    r0.w = dot(r0.xyz, r0.xyz);
    r0.w = max(r0.w, 1.1754944e-38f);
    r0.w = rsqrt(r0.w);
    o3.xyz = r0.www * r0.xyz;
    r0.x = asfloat((0.0f < v2.w) ? 4294967295u : 0u);
    r0.y = asfloat((UnityPerDrawData[9u].w >= 0.0f) ? 4294967295u : 0u);
    uint2 _285 = asuint(r0.xy);
    bool2 _291 = bool2(_285.x != 0u, _285.y != 0u);
    r0.xy = float2(_291.x ? 1.0f.x : (-1.0f).x, _291.y ? 1.0f.x : (-1.0f).x);
    o3.w = r0.y * r0.x;
    o4 = 0.0f.xxxx;
    o5 = 0.0f.xxxx;
    o6 = float4(v6.x, v6.y, o6.z, o6.w);
    o6 = float4(o6.x, o6.y, v4.x, v4.y);
    o7 = float4(v5.x, v5.y, o7.z, o7.w);
    o7 = float4(o7.x, o7.y, 0.0f.x, 0.0f.x);
    o8 = v0;
    r0.xyz = GlobalsData[5u].yyy * UnityPerDrawData[5u].xyz;
    r0.xyz = mad(UnityPerDrawData[4u].xyz, GlobalsData[5u].xxx, r0.xyz);
    r0.xyz = mad(UnityPerDrawData[6u].xyz, GlobalsData[5u].zzz, r0.xyz);
    o9.xyz = mad(UnityPerDrawData[7u].xyz, GlobalsData[5u].www, r0.xyz);
    o9.w = 0.0f;
    o10 = v1;
    StageOutput stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.o1 = o1;
    stage_output.o2 = o2;
    stage_output.o3 = o3;
    stage_output.o4 = o4;
    stage_output.o5 = o5;
    stage_output.o6 = o6;
    stage_output.o7 = o7;
    stage_output.o8 = o8;
    stage_output.o9 = o9;
    stage_output.o10 = o10;
    return stage_output;
}
