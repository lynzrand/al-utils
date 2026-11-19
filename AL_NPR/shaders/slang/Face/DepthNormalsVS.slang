cbuffer Globals : register(b0)
{
    // c78 .x unity_MatrixVP
    float4 GlobalsData[82];
};

cbuffer UnityPerDraw : register(b1)
{
    float4 UnityPerDrawData[7];
};

struct StageInput
{
    float4 v0 : POSITION0;
    float3 v1 : NORMAL0;
    float4 unused2 : TANGENT0;
};

struct StageOutput
{
    float4 gl_Position : SV_POSITION;
    float3 o1 : TEXCOORD0;
};

[shader("vertex")]
StageOutput main(StageInput stage_input)
{
    float4 gl_Position = 0;
    float4 v0 = 0;
    float3 v1 = 0;
    float3 o1 = 0;
    float4 r0 = 0;
    float4 r1 = 0;
    v0 = stage_input.v0;
    v1 = stage_input.v1;
    r0.xyz = v0.yyy * UnityPerDrawData[1u].xyz;
    r0.xyz = mad(UnityPerDrawData[0u].xyz, v0.xxx, r0.xyz);
    r0.xyz = mad(UnityPerDrawData[2u].xyz, v0.zzz, r0.xyz);
    r0.xyz = r0.xyz + UnityPerDrawData[3u].xyz;
    r1 = r0.yyyy * GlobalsData[79u];
    r1 = mad(GlobalsData[78u], r0.xxxx, r1);
    r0 = mad(GlobalsData[80u], r0.zzzz, r1);
    gl_Position = r0 + GlobalsData[81u];
    r0.x = dot(v1, UnityPerDrawData[4u].xyz);
    r0.y = dot(v1, UnityPerDrawData[5u].xyz);
    r0.z = dot(v1, UnityPerDrawData[6u].xyz);
    r0.w = dot(r0.xyz, r0.xyz);
    r0.w = max(r0.w, 1.1754944e-38f);
    r0.w = rsqrt(r0.w);
    o1 = r0.www * r0.xyz;
    StageOutput stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.o1 = o1;
    return stage_output;
}
