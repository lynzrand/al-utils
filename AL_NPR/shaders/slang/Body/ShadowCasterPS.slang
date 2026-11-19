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
    // c14 .x _Cloth_alpha_ST
    // c22 .x _Dither, .y _alpha_a, .z _AlphaMaskuv
    // c28 .x _alpha_b
    float4 UnityPerMaterialData[29];
};

SamplerState sampler_Cloth_alpha_bot : register(s0);
SamplerState sampler_Cloth_alpha : register(s1);
Texture2D<float4> _Cloth_alpha_bot : register(t0);
Texture2D<float4> _Cloth_alpha : register(t1);

struct StageInput
{
    float4 gl_FragCoord : SV_POSITION;
    float4 v1 : TEXCOORD0;
};

struct StageOutput
{
    float4 o0 : SV_Target0;
};

[shader("fragment")]
StageOutput main(StageInput stage_input)
{
    float4 gl_FragCoord = 0;
    float4 v1 = 0;
    float4 o0 = 0;
    float4 r0 = 0;
    float4 r1 = 0;
    float4 v0 = 0;
    gl_FragCoord = stage_input.gl_FragCoord;
    gl_FragCoord.w = 1.0 / gl_FragCoord.w;
    v1 = stage_input.v1;
    float4 _71 = gl_FragCoord;
    _71.w = 1.0f / _71.w;
    v0 = _71;
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
    float _200 = max(r0.y, 0.0f);
    r0.y = asfloat((_200 >= 4.2949673e+09f) ? 4294967295u : uint(_200));
    r0.y = asfloat(asint(r0.y) << (2 & int(31u)));
    r0.z = asfloat((r0.x >= (-r0.xxxx).z) ? 4294967295u : 0u);
    r0.x = frac(abs(r0.xxxx).x);
    r0.x = (asuint(r0.z) != 0u) ? r0.x : (-r0.xxxx).x;
    r0.x *= 4.0f;
    float _250 = max(r0.x, 0.0f);
    r0.x = asfloat((_250 >= 4.2949673e+09f) ? 4294967295u : uint(_250));
    r0.x = asfloat(asint(r0.x) + asint(r0.y));
    r0.x = asfloat(min(asuint(r0.x), 15u));
    r0.x = 0.0625f * coveragePattern[asint(r0.x)];
    r0.y = clamp((UnityPerMaterialData[22u].xxxx * 1.00001f.xxxx).y, 0.0f, 1.0f);
    r0.x = asfloat((r0.y >= r0.x) ? 4294967295u : 0u);
    r0.x = asfloat(asuint(r0.x) & 1065353216u);
    r1 = mad(v1, UnityPerMaterialData[14u].xyxy, UnityPerMaterialData[14u].zwzw);
    r0.yz = (-r1.xxyx).yz + r1.zw;
    r0.yz = mad(UnityPerMaterialData[22u].zz, r0.yz, r1.xy);
    r1.xyz = _Cloth_alpha.Sample(sampler_Cloth_alpha, r0.yz).xyz;
    r0.yzw = _Cloth_alpha_bot.Sample(sampler_Cloth_alpha_bot, r0.yz).xyz;
    r0.yzw = (-r0.zzwy).yzw + float3(2.0f, 1.0f, 1.0f);
    r1.xyz = (-r1.yxzy).xyz + float3(2.0f, 1.0f, 1.0f);
    r1.w = round(UnityPerMaterialData[22u].y);
    r1.x = max(r1.x, r1.w);
    r0.zw = min(r0.zw, r1.yz);
    r0.z = max(r0.z, r1.w);
    r1.x = clamp((r1.xxxx + (-1.0f).xxxx).x, 0.0f, 1.0f);
    r0.z = min(r0.z, r1.x);
    r1.x = round(UnityPerMaterialData[28u].x);
    r0.yw = max(r0.yw, r1.xx);
    r0.y = clamp((r0.yyyy + (-1.0f).xxxx).y, 0.0f, 1.0f);
    r0.y = min(r0.y, r0.w);
    r0.y = min(r0.y, r0.z);
    r0.y = round(r0.y);
    r0.z = r0.y * r0.x;
    r0.x = mad(r0.x, r0.y, -0.5f);
    r0.y = ddx_coarse(r0.z);
    r0.z = ddy_coarse(r0.z);
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
