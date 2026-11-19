cbuffer Globals : register(b0)
{
    // c78 .x unity_MatrixVP
    float4 GlobalsData[82];
};

cbuffer UnityPerDraw : register(b1)
{
    float4 UnityPerDrawData[4];
};

struct StageInput
{
    float4 v0 : POSITION0;
    float3 unused1 : NORMAL0;
    float4 unused2 : TANGENT0;
};

struct StageOutput
{
    float4 gl_Position : SV_POSITION;
};

[shader("vertex")]
StageOutput main(StageInput stage_input)
{
    float4 gl_Position = 0;
    float4 v0 = 0;
    float4 r0 = 0;
    float4 r1 = 0;
    v0 = stage_input.v0;
    r0.xyz = v0.yyy * UnityPerDrawData[1u].xyz;
    r0.xyz = mad(UnityPerDrawData[0u].xyz, v0.xxx, r0.xyz);
    r0.xyz = mad(UnityPerDrawData[2u].xyz, v0.zzz, r0.xyz);
    r0.xyz = r0.xyz + UnityPerDrawData[3u].xyz;
    r1 = r0.yyyy * GlobalsData[79u];
    r1 = mad(GlobalsData[78u], r0.xxxx, r1);
    r0 = mad(GlobalsData[80u], r0.zzzz, r1);
    gl_Position = r0 + GlobalsData[81u];
    StageOutput stage_output;
    stage_output.gl_Position = gl_Position;
    return stage_output;
}
