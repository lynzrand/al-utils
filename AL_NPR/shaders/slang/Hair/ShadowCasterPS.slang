import Coverage;

cbuffer Globals : register(b0)
{
    // c3 .x _ScaledScreenParams
    // c4 .z _AlphaToMaskAvailable
    // c22 .x _ProjectionParams
    // c27 .x _ScaleBiasRt
    float4 GlobalsData[28];
};

cbuffer UnityPerMaterial : register(b1)
{
    // c21 .x _Dither, .y _TipAlpha
    float4 UnityPerMaterialData[22];
};

struct StageInput
{
    float4 gl_FragCoord : SV_POSITION;
};

struct StageOutput
{
    float4 o0 : SV_Target0;
};

[shader("fragment")]
StageOutput main(StageInput stage_input)
{
    float4 gl_FragCoord = 0;
    float4 o0 = 0;
    float4 r0 = 0;
    float4 v0 = 0;
    gl_FragCoord = stage_input.gl_FragCoord;
    gl_FragCoord.w = 1.0 / gl_FragCoord.w;
    float4 _62 = gl_FragCoord;
    _62.w = 1.0f / _62.w;
    v0 = _62;
    r0.xy = 1.0f.xx / GlobalsData[3u].xy;
    r0.xy = r0.xy * v0.xy;
    r0.y = mad(r0.y, GlobalsData[27u].x, GlobalsData[27u].y);
    r0.z = (-r0.yyyy).z + 1.0f;
    r0.xy = r0.xz * GlobalsData[3u].xy;
    r0.z = mad((-r0.zzzz).z, GlobalsData[3u].y, GlobalsData[3u].y);
    r0.w = asfloat((GlobalsData[22u].x < 0.0f) ? 4294967295u : 0u);
    r0.y = (asuint(r0.w) != 0u) ? r0.z : r0.y;
    r0.xy = r0.xy * 0.25f.xx;
    r0.z = asfloat((r0.y >= (-r0.yyyy).z) ? 4294967295u : 0u);
    r0.y = frac(abs(r0.yyyy).y);
    r0.y = (asuint(r0.z) != 0u) ? r0.y : (-r0.yyyy).y;
    r0.y *= 4.0f;
    float _189 = max(r0.y, 0.0f);
    r0.y = asfloat((_189 >= 4.2949673e+09f) ? 4294967295u : uint(_189));
    r0.y = asfloat(asint(r0.y) << (2 & int(31u)));
    r0.z = asfloat((r0.x >= (-r0.xxxx).z) ? 4294967295u : 0u);
    r0.x = frac(abs(r0.xxxx).x);
    r0.x = (asuint(r0.z) != 0u) ? r0.x : (-r0.xxxx).x;
    r0.x *= 4.0f;
    float _239 = max(r0.x, 0.0f);
    r0.x = asfloat((_239 >= 4.2949673e+09f) ? 4294967295u : uint(_239));
    r0.x = asfloat(asint(r0.x) + asint(r0.y));
    r0.x = asfloat(min(asuint(r0.x), 15u));
    r0.x = 0.0625f * coveragePattern[asint(r0.x)];
    r0.y = clamp((UnityPerMaterialData[21u].xxxx * 1.00001f.xxxx).y, 0.0f, 1.0f);
    r0.x = asfloat((r0.y >= r0.x) ? 4294967295u : 0u);
    r0.x = asfloat(asuint(r0.x) & 1065353216u);
    r0.y = clamp(UnityPerMaterialData[21u].y, 0.0f, 1.0f);
    r0.y = max(r0.y, 0.01f);
    r0.x = min(r0.y, r0.x);
    r0.y = ddx_coarse(r0.x);
    r0.z = ddy_coarse(r0.x);
    r0.x += (-0.001f);
    r0.y = abs(r0.zzzz).y + abs(r0.yyyy).y;
    r0.z = mad((-r0.yyyy).z, 0.5f, r0.x);
    r0.y = max(r0.y, 0.0001f);
    r0.y = r0.z / r0.y;
    r0.y = clamp((r0.yyyy + 1.0f.xxxx).y, 0.0f, 1.0f);
    r0.y += (-0.0001f);
    r0.z = asfloat((GlobalsData[4u].z != 0.0f) ? 4294967295u : 0u);
    r0.x = (asuint(r0.z) != 0u) ? r0.y : r0.x;
    r0.x = asfloat((r0.x < 0.0f) ? 4294967295u : 0u);
    if (asuint(r0.x) != 0u) discard;
    o0 = 0.0f.xxxx;
    StageOutput stage_output;
    stage_output.o0 = o0;
    return stage_output;
}
