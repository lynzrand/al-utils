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
    // c19 .z _Line_width
    // c23 .w _Bust_size
    // c24 .x _Dent_power, .y _VertexColorNormal
    float4 UnityPerMaterialData[25];
};

SamplerState s0 : register(s0);
SamplerState s1 : register(s1);
SamplerState sampler_Create_dent_texture : register(s2);
Texture2D<float4> _Create_dent_texture : register(t0);
Texture2DArray<float4> _Detail_mask_01 : register(t1);
Texture2DArray<float4> _TexEX : register(t2);

struct StageInput
{
    float4 v0 : POSITION0;
    float3 v1 : NORMAL0;
    float4 v2 : TANGENT0;
    float4 v3 : TEXCOORD0;
    float4 v4 : COLOR0;
    float4 v5 : TEXCOORD1;
    float4 v6 : TEXCOORD2;
    float4 v7 : TEXCOORD3;
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
    float4 v7 = 0;
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
    float4 r2 = 0;
    float4 r3 = 0;
    v0 = stage_input.v0;
    v1 = stage_input.v1;
    v2 = stage_input.v2;
    v3 = stage_input.v3;
    v4 = stage_input.v4;
    v5 = stage_input.v5;
    v6 = stage_input.v6;
    v7 = stage_input.v7;
    r0 = float4(v3.x, v3.y, r0.z, r0.w);
    r0.z = 2.0f;
    r0.x = _TexEX.SampleLevel(s1, r0.xyz, 0.0f).w;
    r0.x += (-1.0f);
    r0.y = UnityPerMaterialData[23u].w + (-0.5f);
    r0.xy = clamp((r0.xyxx * float4(-5.263158f, 2.5f, 0.0f, 0.0f)).xy, 0.0f.xx, 1.0f.xx);
    r0.x = mad(r0.y, r0.x, -0.5f);
    r0.x = (-r0.xxxx).x + 1.0f;
    r0.x = min(r0.x, 1.0f);
    r1 = float4(v3.x, v3.y, r1.z, r1.w);
    r1.z = 0.0f;
    r0.y = _Detail_mask_01.SampleLevel(s0, r1.xyz, 0.0f).x;
    r0.y = (-r0.yyyy).y + 1.0f;
    r0.z = r0.y * UnityPerMaterialData[19u].z;
    r0.x *= r0.z;
    r0.x = r0.y * r0.x;
    r0.x *= 0.2f;
    r0.yzw = v1 + v4.xyz;
    r0.yzw = r0.yzw + float3(-0.5f, 0.0f, -0.5f);
    r0.yzw = r0.xxx * r0.yzw;
    r1.xyz = r0.xxx * v1;
    r2.xyz = v0.yyy * UnityPerDrawData[1u].xyz;
    r2.xyz = mad(UnityPerDrawData[0u].xyz, v0.xxx, r2.xyz);
    r2.xyz = mad(UnityPerDrawData[2u].xyz, v0.zzz, r2.xyz);
    r2.xyz = r2.xyz + UnityPerDrawData[3u].xyz;
    r0.x = r2.y * GlobalsData[83u].w;
    r0.x = mad(GlobalsData[82u].w, r2.x, r0.x);
    r0.x = mad(GlobalsData[84u].w, r2.z, r0.x);
    r0.x += GlobalsData[85u].w;
    r2.xy = min(r0.xx, float2(0.3f, 0.35f));
    r0.xyz = r0.yzw * r2.xxx;
    r0.w = _Create_dent_texture.SampleLevel(sampler_Create_dent_texture, v5.xy, 0.0f).x;
    r0.w *= UnityPerMaterialData[24u].x;
    r2.zw = r0.ww * float2(0.2f, -0.4f);
    r3.xyz = mad(v4.xyz, r2.www, r2.zzz);
    r0.xyz = mad(r0.xyz, 0.5f.xxx, r3.xyz);
    r0.xyz = mad((-r1.xyzx).xyz, r2.xxx, r0.xyz);
    r1.xyz = r1.xyz * r2.xxx;
    r0.xyz = mad(UnityPerMaterialData[24u].yyy, r0.xyz, r1.xyz);
    r0.xyz = mad(r0.xyz, r2.yyy, v0.xyz);
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
    uint2 _537 = asuint(r0.xy);
    bool2 _541 = bool2(_537.x != 0u, _537.y != 0u);
    r0.xy = float2(_541.x ? 1.0f.x : (-1.0f).x, _541.y ? 1.0f.x : (-1.0f).x);
    o3.w = r0.y * r0.x;
    o4 = 0.0f.xxxx;
    o5 = 0.0f.xxxx;
    o6 = float4(v3.x, v3.y, o6.z, o6.w);
    o6 = float4(o6.x, o6.y, v5.x, v5.y);
    o7 = float4(v6.x, v6.y, o7.z, o7.w);
    o7 = float4(o7.x, o7.y, v7.x, v7.y);
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
