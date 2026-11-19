import Coverage;

cbuffer Globals : register(b0)
{
    // c3 .x _ScaledScreenParams
    // c21 .x _WorldSpaceCameraPos
    // c22 .x _ProjectionParams
    // c27 .x _ScaleBiasRt
    float4 GlobalsData[28];
};

cbuffer UnityPerDraw : register(b1)
{
    float4 UnityPerDrawData[4];
};

cbuffer UnityPerMaterial : register(b2)
{
    // c8 .x _liquidmask_ST
    // c10 .x _LiquidTiling
    // c15 .x _Cloth_alpha_ST
    // c21 .z _AlphaMaskuv, .w _alpha_a
    // c22 .y _alpha, .z _AlphaDither, .w _Dither
    // c23 .w _AlphaLine
    // c28 .z _Mip
    // c29 .x _liquidbbot, .y _liquidbtop, .z _liquidfbot, .w _liquidftop
    // c31 .z _LineWidthS, .w _Line_width
    // c34 .x _alpha_b
    // c38 .y _AlphaClipForce, .z _AlphaClip
    float4 UnityPerMaterialData[39];
};

SamplerState sampler_Create_main_texture : register(s0);
SamplerState sampler_Detail_mask_01 : register(s1);
SamplerState sampler_Liquid : register(s2);
SamplerState sampler_liquidmask : register(s3);
SamplerState sampler_Cloth_alpha_bot : register(s4);
SamplerState sampler_Cloth_alpha : register(s5);
Texture2D<float4> _Create_main_texture : register(t0);
Texture2D<float4> _Detail_mask_01 : register(t1);
Texture2D<float4> _Liquid : register(t2);
Texture2D<float4> _liquidmask : register(t3);
Texture2D<float4> _Cloth_alpha_bot : register(t4);
Texture2D<float4> _Cloth_alpha : register(t5);

struct StageInput
{
    float4 gl_FragCoord : SV_POSITION;
    float3 v1 : TEXCOORD0;
    float4 v2 : TEXCOORD1;
};

struct StageOutput
{
    float4 o0 : SV_Target0;
};

[shader("fragment")]
StageOutput main(StageInput stage_input)
{
    float4 gl_FragCoord = 0;
    float3 v1 = 0;
    float4 v2 = 0;
    float4 o0 = 0;
    float4 r0 = 0;
    float4 r1 = 0;
    float4 r2 = 0;
    float4 r3 = 0;
    float4 v0 = 0;
    gl_FragCoord = stage_input.gl_FragCoord;
    gl_FragCoord.w = 1.0 / gl_FragCoord.w;
    v1 = stage_input.v1;
    v2 = stage_input.v2;
    float4 _86 = gl_FragCoord;
    _86.w = 1.0f / _86.w;
    v0 = _86;
    r0.xyz = GlobalsData[21u].xyz + (-UnityPerDrawData[3u].xyzx).xyz;
    r0.x = dot(r0.xyz, r0.xyz);
    r0.x = sqrt(r0.x);
    r0.x = mad(r0.x, -0.09090909f, 1.0f);
    r0.x = max(r0.x, 0.0f);
    r0.y = _Detail_mask_01.Sample(sampler_Detail_mask_01, v2.xy).z;
    r0.z = (-r0.yyyy).z + 1.0f;
    r0.y = asfloat((r0.y >= 0.7f) ? 4294967295u : 0u);
    r0.y = asfloat(asuint(r0.y) & 1065353216u);
    r0.y *= UnityPerMaterialData[38u].y;
    r0.z *= UnityPerMaterialData[31u].w;
    r0.z *= UnityPerMaterialData[31u].z;
    r0.x = r0.z * r0.x;
    r0.z = clamp((r0.zzzz * 4.0f.xxxx).z, 0.0f, 1.0f);
    r0.z *= UnityPerMaterialData[23u].w;
    r0.w = max(r0.x, 0.0f);
    r0.x = clamp((r0.xxxx + r0.xxxx).x, 0.0f, 1.0f);
    r0.w = min(r0.w, 0.6f);
    r1.xy = mad(r0.ww, 0.0007f.xx, v2.xy);
    r1.x = _Create_main_texture.SampleBias(sampler_Create_main_texture, r1.xy, UnityPerMaterialData[28u].z).w;
    r2.x = r0.w * 0.0007f;
    r1.yz = mad((-r0.wwww).yz, 0.0007f.xx, v2.xy);
    r0.w = _Create_main_texture.SampleBias(sampler_Create_main_texture, r1.yz, UnityPerMaterialData[28u].z).w;
    r2.zw = (-r2.xxxx).zw;
    r2.y = 0.0f;
    r3 = r2.xzwy + v2.xyxy;
    r1.y = _Create_main_texture.SampleBias(sampler_Create_main_texture, r3.xy, UnityPerMaterialData[28u].z).w;
    r1.z = _Create_main_texture.SampleBias(sampler_Create_main_texture, r3.zw, UnityPerMaterialData[28u].z).w;
    r1.x = max(r1.y, r1.x);
    r3 = r2.xyyx + v2.xyxy;
    r2 = mad(r2.yxxx, float4(1.0f, -1.0f, -1.0f, 1.0f), v2.xyxy);
    r1.y = _Create_main_texture.SampleBias(sampler_Create_main_texture, r3.xy, UnityPerMaterialData[28u].z).w;
    r1.w = _Create_main_texture.SampleBias(sampler_Create_main_texture, r3.zw, UnityPerMaterialData[28u].z).w;
    r1.y = max(r1.w, r1.y);
    r1.x = max(r1.x, r1.y);
    r1.y = _Create_main_texture.SampleBias(sampler_Create_main_texture, r2.xy, UnityPerMaterialData[28u].z).w;
    r1.w = _Create_main_texture.SampleBias(sampler_Create_main_texture, r2.zw, UnityPerMaterialData[28u].z).w;
    r0.w = max(r0.w, r1.w);
    r1.y = max(r1.y, r1.z);
    r0.w = max(r0.w, r1.y);
    r0.w = max(r0.w, r1.x);
    r1.x = _Create_main_texture.SampleLevel(sampler_Create_main_texture, v2.xy, UnityPerMaterialData[28u].z).w;
    r0.w = max(r0.w, r1.x);
    r0.w += (-0.3f);
    r0.w = clamp((r0.wwww * 2.5f.xxxx).w, 0.0f, 1.0f);
    r0.w = (-r1.xxxx).w + r0.w;
    r0.x = mad(r0.x, r0.w, r1.x);
    r0.w = _Create_main_texture.SampleBias(sampler_Create_main_texture, v2.xy, UnityPerMaterialData[28u].z).w;
    r0.x = (-r0.wwww).x + r0.x;
    r0.x = mad(r0.z, r0.x, r0.w);
    r0.z = r0.w + (-0.3f);
    r0.z = clamp((r0.zzzz * 1.4285715f.xxxx).z, 0.0f, 1.0f);
    r0.w = mad(r0.z, -2.0f, 3.0f);
    r0.z *= r0.z;
    r0.z *= r0.w;
    r1.xy = mad(UnityPerMaterialData[10u].zw, v2.xy, UnityPerMaterialData[10u].xy);
    r1.xy = _Liquid.Sample(sampler_Liquid, r1.xy).xy;
    r1.xy = r1.yx + (-0.1f).xx;
    r1.xy = clamp((r1.xyxx + r1.xyxx).xy, 0.0f.xx, 1.0f.xx);
    r1.zw = mad(r1.xy, (-2.0f).xx, 3.0f.xx);
    r1.xy = r1.xy * r1.xy;
    r1.xy = r1.xy * r1.zw;
    r2 = clamp(UnityPerMaterialData[29u].wzyx + (-1.0f).xxxx, 0.0f.xxxx, 1.0f.xxxx);
    r2 = r1.xxxx * r2;
    r1 = r1.yyyy * UnityPerMaterialData[29u].wzyx;
    r1 = max(r1, r2);
    r2.xy = mad(v2.xy, UnityPerMaterialData[8u].xy, UnityPerMaterialData[8u].zw);
    r2.xyz = _liquidmask.Sample(sampler_liquidmask, r2.xy).xyz;
    r3.xy = clamp(((-r2.yxyy) + r2.xyxx).xy, 0.0f.xx, 1.0f.xx);
    r1.xy = min(r1.xy, r3.xy);
    r0.w = r1.y + r1.x;
    r1.x = min(r1.z, r2.z);
    r1.y = r2.y * r2.x;
    r1.y = min(r1.y, r1.w);
    r0.w += r1.x;
    r0.w = clamp((r1.yyyy + r0.wwww).w, 0.0f, 1.0f);
    r0.w += (-0.01f);
    r0.w = clamp((r0.wwww * 1.4492754f.xxxx).w, 0.0f, 1.0f);
    r1.x = mad(r0.w, -2.0f, 3.0f);
    r0.w *= r0.w;
    r0.w *= r1.x;
    r0.zw = min(r0.zw, 1.0f.xx);
    r0.z *= r0.w;
    r0.x = max(r0.z, r0.x);
    r0.z = r0.x * 1.00001f;
    r0.z = min(r0.z, 1.0f);
    r1.xy = 1.0f.xx / GlobalsData[3u].xy;
    r1.xy = r1.xy * v0.xy;
    r0.w = mad(r1.y, GlobalsData[27u].x, GlobalsData[27u].y);
    r1.z = (-r0.wwww).z + 1.0f;
    r1.xy = r1.xz * GlobalsData[3u].xy;
    r0.w = mad((-r1.zzzz).w, GlobalsData[3u].y, GlobalsData[3u].y);
    r1.z = asfloat((GlobalsData[22u].x < 0.0f) ? 4294967295u : 0u);
    r0.w = (asuint(r1.z) != 0u) ? r0.w : r1.y;
    r1.x *= 0.25f;
    r0.w *= 0.25f;
    r1.y = asfloat((r0.w >= (-r0.wwww).y) ? 4294967295u : 0u);
    r0.w = frac(abs(r0.wwww).w);
    r0.w = (asuint(r1.y) != 0u) ? r0.w : (-r0.wwww).w;
    r0.w *= 4.0f;
    float _831 = max(r0.w, 0.0f);
    r0.w = asfloat((_831 >= 4.2949673e+09f) ? 4294967295u : uint(_831));
    r0.w = asfloat(asint(r0.w) << (2 & int(31u)));
    r1.y = asfloat((r1.x >= (-r1.xxxx).y) ? 4294967295u : 0u);
    r1.x = frac(abs(r1.xxxx).x);
    r1.x = (asuint(r1.y) != 0u) ? r1.x : (-r1.xxxx).x;
    r1.x *= 4.0f;
    float _880 = max(r1.x, 0.0f);
    r1.x = asfloat((_880 >= 4.2949673e+09f) ? 4294967295u : uint(_880));
    r0.w = asfloat(asint(r0.w) + asint(r1.x));
    r0.w = asfloat(min(asuint(r0.w), 15u));
    r0.w = 0.0625f * coveragePattern[asint(r0.w)];
    r0.z = asfloat((r0.z >= r0.w) ? 4294967295u : 0u);
    r0.z = asfloat(asuint(r0.z) & 1065353216u);
    r0.z = (-r0.xxxx).z + r0.z;
    r0.z = mad(UnityPerMaterialData[22u].z, r0.z, r0.x);
    r0.x = min(r0.z, r0.x);
    r0.x *= UnityPerMaterialData[22u].y;
    r0.z = clamp((UnityPerMaterialData[22u].wwww * 1.00001f.xxxx).z, 0.0f, 1.0f);
    r0.z = asfloat((r0.z >= r0.w) ? 4294967295u : 0u);
    r0.z = asfloat(asuint(r0.z) & 1065353216u);
    r0.x = min(r0.x, r0.z);
    r0.z = r0.x + (-0.009f);
    r0.z = ceil(r0.z);
    r0.x = min(r0.z, r0.x);
    r1 = mad(v2, UnityPerMaterialData[15u].xyxy, UnityPerMaterialData[15u].zwzw);
    r0.zw = (-r1.xxxy).zw + r1.zw;
    r0.zw = mad(UnityPerMaterialData[21u].zz, r0.zw, r1.xy);
    r1.xyz = _Cloth_alpha.Sample(sampler_Cloth_alpha, r0.zw).xyz;
    r2.xyz = _Cloth_alpha_bot.Sample(sampler_Cloth_alpha_bot, r0.zw).xyz;
    r2.xyz = (-r2.yzxy).xyz + float3(2.0f, 1.0f, 1.0f);
    r1.xyz = (-r1.yxzy).xyz + float3(2.0f, 1.0f, 1.0f);
    r0.z = round(UnityPerMaterialData[21u].w);
    r0.w = max(r1.x, r0.z);
    r1.xy = min(r1.yz, r2.yz);
    r0.z = max(r0.z, r1.x);
    r0.w = clamp((r0.wwww + (-1.0f).xxxx).w, 0.0f, 1.0f);
    r0.z = min(r0.w, r0.z);
    r0.w = round(UnityPerMaterialData[34u].x);
    r1.x = max(r2.x, r0.w);
    r0.w = max(r1.y, r0.w);
    r1.x = clamp((r1.xxxx + (-1.0f).xxxx).x, 0.0f, 1.0f);
    r0.w = min(r0.w, r1.x);
    r0.z = min(r0.w, r0.z);
    r0.z = round(r0.z);
    r0.w = max(UnityPerMaterialData[38u].z, 0.011f);
    r0.w = min(r0.w, 1.0f);
    r1.x = (-r0.wwww).x + 0.999f;
    r0.y = mad(r0.y, r1.x, r0.w);
    r0.x = mad(r0.x, r0.z, (-r0.yyyy).x);
    r0.x = asfloat((r0.x < 0.0f) ? 4294967295u : 0u);
    if (asuint(r0.x) != 0u) discard;
    r0.x = dot(v1, v1);
    r0.x = rsqrt(r0.x);
    o0.xyz = r0.xxx * v1;
    o0.w = 0.0f;
    StageOutput stage_output;
    stage_output.o0 = o0;
    return stage_output;
}
