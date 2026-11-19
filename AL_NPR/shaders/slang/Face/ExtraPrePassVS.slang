cbuffer Globals : register(b0)
{
    // c78 .x unity_MatrixVP
    float4 GlobalsData[82];
};

cbuffer UnityPerDraw : register(b1)
{
    float4 UnityPerDrawData[10];
};

cbuffer UnityPerMaterial : register(b2)
{
    // c21 .x _Detail_mask_01_ST
    // c29 .y _LineWidthMax, .z _DistanceCutoff
    // c34 .w _Line_width
    float4 UnityPerMaterialData[35];
};

SamplerState sampler_Detail_mask_01 : register(s0);
Texture2D<float4> _Detail_mask_01 : register(t0);

struct StageInput
{
    float4 v0 : POSITION0;
    float3 v1 : NORMAL0;
    float4 v2 : TANGENT0;
    float4 v3 : TEXCOORD0;
    float4 v4 : TEXCOORD1;
    float4 v5 : TEXCOORD3;
    float4 v6 : TEXCOORD2;
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
    float4 r0 = 0;
    float4 r1 = 0;
    v0 = stage_input.v0;
    v1 = stage_input.v1;
    v2 = stage_input.v2;
    v3 = stage_input.v3;
    v4 = stage_input.v4;
    v5 = stage_input.v5;
    v6 = stage_input.v6;
    r0.xy = mad(v3.xy, UnityPerMaterialData[21u].xy, UnityPerMaterialData[21u].zw);
    r0.x = _Detail_mask_01.SampleLevel(sampler_Detail_mask_01, r0.xy, 0.0f).x;
    r0.y = (-r0.xxxx).y + 1.0f;
    r0.y *= UnityPerMaterialData[34u].w;
    r0.y *= 0.05f;
    r0.z = clamp(mad(r0.xxxx, (-1.2f).xxxx, 1.0f.xxxx).z, 0.0f, 1.0f);
    r0.y = min(r0.z, r0.y);
    r0.y = max(r0.y, 0.0f);
    r0.z = UnityPerMaterialData[29u].y + (-1.0f);
    r0.x = mad(r0.x, r0.z, 1.0f);
    r0.x *= 0.05f;
    r0.x = min(r0.x, r0.y);
    r0.xyz = r0.xxx * v1;
    r1.xyz = v0.yyy * UnityPerDrawData[1u].xyz;
    r1.xyz = mad(UnityPerDrawData[0u].xyz, v0.xxx, r1.xyz);
    r1.xyz = mad(UnityPerDrawData[2u].xyz, v0.zzz, r1.xyz);
    r1.xyz = r1.xyz + UnityPerDrawData[3u].xyz;
    r0.w = r1.y * GlobalsData[79u].w;
    r0.w = mad(GlobalsData[78u].w, r1.x, r0.w);
    r0.w = mad(GlobalsData[80u].w, r1.z, r0.w);
    r0.w += GlobalsData[81u].w;
    r0.w = min(r0.w, UnityPerMaterialData[29u].z);
    r0.xyz = mad(r0.xyz, r0.www, v0.xyz);
    r1.xyz = r0.yyy * UnityPerDrawData[1u].xyz;
    r0.xyw = mad(UnityPerDrawData[0u].xyz, r0.xxx, r1.xyz);
    r0.xyz = mad(UnityPerDrawData[2u].xyz, r0.zzz, r0.xyw);
    r0.xyz = r0.xyz + UnityPerDrawData[3u].xyz;
    r1 = r0.yyyy * GlobalsData[79u];
    r1 = mad(GlobalsData[78u], r0.xxxx, r1);
    r1 = mad(GlobalsData[80u], r0.zzzz, r1);
    o1 = float4(r0.x, r0.y, r0.z, o1.w);
    gl_Position = r1 + GlobalsData[81u];
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
    uint2 _413 = asuint(r0.xy);
    bool2 _418 = bool2(_413.x != 0u, _413.y != 0u);
    r0.xy = float2(_418.x ? 1.0f.x : (-1.0f).x, _418.y ? 1.0f.x : (-1.0f).x);
    o3.w = r0.y * r0.x;
    o4 = float4(v3.x, v3.y, o4.z, o4.w);
    o4 = float4(o4.x, o4.y, v4.x, v4.y);
    o5 = float4(v5.x, v5.y, o5.z, o5.w);
    o5 = float4(o5.x, o5.y, v6.x, v6.y);
    o6 = 0.0f.xxxx;
    o7 = 0.0f.xxxx;
    StageOutput stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.o1 = o1;
    stage_output.o2 = o2;
    stage_output.o3 = o3;
    stage_output.o4 = o4;
    stage_output.o5 = o5;
    stage_output.o6 = o6;
    stage_output.o7 = o7;
    return stage_output;
}
