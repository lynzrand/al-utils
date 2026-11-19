import Coverage;

cbuffer Globals : register(b0)
{
    // c3 .x _ScaledScreenParams
    // c4 .z _AlphaToMaskAvailable
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
    // c1 .x _ColorMask_ST
    // c3 .x _Main_color_02
    // c4 .x _liquidmask_ST
    // c5 .x _Detail_mask_01_ST
    // c6 .x _LiquidTiling
    // c9 .x _Main_color_01
    // c13 .x _Cloth_alpha_ST
    // c14 .x _Main_color_03
    // c15 .x _Main_color_04
    // c20 .x _sukeONOFF, .y _sukebbot, .z _sukebtop
    // c21 .w _alpha_b
    // c22 .x _AlphaMaskuv, .y _alpha_a, .w _alpha
    // c23 .x _AlphaDither, .y _Dither
    // c24 .y _AlphaLine
    // c25 .w _sukefbot
    // c27 .y _sukeftop, .w _SukeScale
    // c28 .w _Mip
    // c29 .x _Main_color_switchtest, .y _liquidbbot, .z _liquidbtop, .w _liquidfbot
    // c30 .x _liquidftop
    // c31 .w _LineWidthS
    // c32 .x _Line_width
    // c33 .y _SukeOffset
    // c34 .w _AlphaClipForce
    // c39 .z _AlphaClip
    float4 UnityPerMaterialData[40];
};

SamplerState sampler_Create_main_texture : register(s0);
SamplerState sampler_Detail_mask_01 : register(s1);
SamplerState sampler_ColorMask : register(s2);
SamplerState sampler_liquidmask : register(s3);
SamplerState sampler_Liquid : register(s4);
SamplerState sampler_Cloth_alpha_bot : register(s5);
SamplerState sampler_Cloth_alpha : register(s6);
Texture2D<float4> _Create_main_texture : register(t0);
Texture2D<float4> _Detail_mask_01 : register(t1);
Texture2D<float4> _ColorMask : register(t2);
Texture2D<float4> _liquidmask : register(t3);
Texture2D<float4> _Liquid : register(t4);
Texture2D<float4> _Cloth_alpha_bot : register(t5);
Texture2D<float4> _Cloth_alpha : register(t6);

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
    float4 r2 = 0;
    float4 r3 = 0;
    float4 r4 = 0;
    float4 v0 = 0;
    gl_FragCoord = stage_input.gl_FragCoord;
    gl_FragCoord.w = 1.0 / gl_FragCoord.w;
    v1 = stage_input.v1;
    float4 _89 = gl_FragCoord;
    _89.w = 1.0f / _89.w;
    v0 = _89;
    r0.xyz = GlobalsData[21u].xyz + (-UnityPerDrawData[3u].xyzx).xyz;
    r0.x = dot(r0.xyz, r0.xyz);
    r0.x = sqrt(r0.x);
    r0.x = mad(r0.x, -0.09090909f, 1.0f);
    r0.x = max(r0.x, 0.0f);
    r0.y = _Detail_mask_01.Sample(sampler_Detail_mask_01, v1.xy).z;
    r0.z = (-r0.yyyy).z + 1.0f;
    r0.y = asfloat((r0.y >= 0.7f) ? 4294967295u : 0u);
    r0.y = asfloat(asuint(r0.y) & 1065353216u);
    r0.y *= UnityPerMaterialData[34u].w;
    r0.z *= UnityPerMaterialData[32u].x;
    r0.z *= UnityPerMaterialData[31u].w;
    r0.x = r0.z * r0.x;
    r0.z = clamp((r0.zzzz * 4.0f.xxxx).z, 0.0f, 1.0f);
    r0.z *= UnityPerMaterialData[24u].y;
    r0.w = max(r0.x, 0.0f);
    r0.x = clamp((r0.xxxx + r0.xxxx).x, 0.0f, 1.0f);
    r0.w = min(r0.w, 0.6f);
    r1.xy = mad(r0.ww, 0.0007f.xx, v1.xy);
    r1.x = _Create_main_texture.SampleBias(sampler_Create_main_texture, r1.xy, UnityPerMaterialData[28u].w).w;
    r2.x = r0.w * 0.0007f;
    r1.yz = mad((-r0.wwww).yz, 0.0007f.xx, v1.xy);
    r0.w = _Create_main_texture.SampleBias(sampler_Create_main_texture, r1.yz, UnityPerMaterialData[28u].w).w;
    r2.zw = (-r2.xxxx).zw;
    r2.y = 0.0f;
    r3 = r2.xzwy + v1.xyxy;
    r1.y = _Create_main_texture.SampleBias(sampler_Create_main_texture, r3.xy, UnityPerMaterialData[28u].w).w;
    r1.z = _Create_main_texture.SampleBias(sampler_Create_main_texture, r3.zw, UnityPerMaterialData[28u].w).w;
    r1.x = max(r1.y, r1.x);
    r3 = r2.xyyx + v1.xyxy;
    r2 = mad(r2.yxxx, float4(1.0f, -1.0f, -1.0f, 1.0f), v1.xyxy);
    r1.y = _Create_main_texture.SampleBias(sampler_Create_main_texture, r3.xy, UnityPerMaterialData[28u].w).w;
    r1.w = _Create_main_texture.SampleBias(sampler_Create_main_texture, r3.zw, UnityPerMaterialData[28u].w).w;
    r1.y = max(r1.w, r1.y);
    r1.x = max(r1.x, r1.y);
    r1.y = _Create_main_texture.SampleBias(sampler_Create_main_texture, r2.xy, UnityPerMaterialData[28u].w).w;
    r1.w = _Create_main_texture.SampleBias(sampler_Create_main_texture, r2.zw, UnityPerMaterialData[28u].w).w;
    r0.w = max(r0.w, r1.w);
    r1.y = max(r1.y, r1.z);
    r0.w = max(r0.w, r1.y);
    r0.w = max(r0.w, r1.x);
    r1.x = _Create_main_texture.SampleLevel(sampler_Create_main_texture, v1.xy, UnityPerMaterialData[28u].w).w;
    r0.w = max(r0.w, r1.x);
    r0.w += (-0.3f);
    r0.w = clamp((r0.wwww * 2.5f.xxxx).w, 0.0f, 1.0f);
    r0.w = (-r1.xxxx).w + r0.w;
    r0.x = mad(r0.x, r0.w, r1.x);
    r1 = _Create_main_texture.SampleBias(sampler_Create_main_texture, v1.xy, UnityPerMaterialData[28u].w);
    r0.x += (-r1.wwww).x;
    r0.x = mad(r0.z, r0.x, r1.w);
    r2.xyz = UnityPerMaterialData[9u].xyz + (-UnityPerMaterialData[15u].xyzx).xyz;
    r0.zw = mad(v1.xy, UnityPerMaterialData[1u].xy, UnityPerMaterialData[1u].zw);
    r3.xyz = _ColorMask.Sample(sampler_ColorMask, r0.zw).xyz;
    r2.xyz = mad(r3.xxx, r2.xyz, UnityPerMaterialData[15u].xyz);
    r4.xyz = (-r2.xyzx).xyz + UnityPerMaterialData[3u].xyz;
    r2.xyz = mad(r3.yyy, r4.xyz, r2.xyz);
    r3.xyw = (-r2.xyxz).xyw + UnityPerMaterialData[14u].xyz;
    r2.xyz = mad(r3.zzz, r3.xyw, r2.xyz);
    r2.xyz = r1.xyz * r2.xyz;
    r0.z = asfloat((0.0f != UnityPerMaterialData[29u].x) ? 4294967295u : 0u);
    uint3 _577 = asuint(r0.zzz);
    bool3 _584 = bool3(_577.x != 0u, _577.y != 0u, _577.z != 0u);
    r1.xyz = float3(_584.x ? r2.x : r1.x, _584.y ? r2.y : r1.y, _584.z ? r2.z : r1.z);
    r0.z = r1.w + (-0.3f);
    r0.z = clamp((r0.zzzz * 1.4285715f.xxxx).z, 0.0f, 1.0f);
    r0.w = dot(r1.xyz, float3(0.299f, 0.587f, 0.114f));
    r0.w = clamp(mad(r0.wwww, 0.6f.xxxx, 0.4f.xxxx).w, 0.0f, 1.0f);
    r1.xy = mad(v1.xy, UnityPerMaterialData[5u].xy, UnityPerMaterialData[5u].zw);
    r1.x = _Detail_mask_01.Sample(sampler_Detail_mask_01, r1.xy).x;
    r1.x = clamp(mad(r1.xxxx, UnityPerMaterialData[27u].wwww, UnityPerMaterialData[33u].yyyy).x, 0.0f, 1.0f);
    r1.y = r1.x * UnityPerMaterialData[27u].y;
    r1.zw = mad(v1.xy, UnityPerMaterialData[4u].xy, UnityPerMaterialData[4u].zw);
    r2.xyz = _liquidmask.Sample(sampler_liquidmask, r1.zw).xyz;
    r3.xyz = max(r2.zzy, r2.yxx);
    r3.xyz = clamp((r2.xyzx + (-r3.xyzx)).xyz, 0.0f.xxx, 1.0f.xxx);
    r1.z = r1.x * UnityPerMaterialData[25u].w;
    r1.xw = r1.xx * UnityPerMaterialData[20u].zy;
    r1.yz = min(r1.yz, r3.xy);
    r1.y = r1.z + r1.y;
    r1.z = min(r2.y, r2.x);
    r3.w = clamp(((-r2.zzzz) + r1.zzzz).w, 0.0f, 1.0f);
    r1.xz = min(r1.xw, r3.zw);
    r1.x += r1.y;
    r1.x = clamp((r1.zzzz + r1.xxxx).x, 0.0f, 1.0f);
    r1.x = sqrt(r1.x);
    r0.w *= r1.x;
    r0.x = clamp(mad(-UnityPerMaterialData[20u].xxxx, r0.wwww, r0.xxxx).x, 0.0f, 1.0f);
    r0.w = mad(r0.z, -2.0f, 3.0f);
    r0.z *= r0.z;
    r0.z *= r0.w;
    r0.w = clamp((UnityPerMaterialData[30u].xxxx + (-1.0f).xxxx).w, 0.0f, 1.0f);
    r1.xy = mad(UnityPerMaterialData[6u].zw, v1.xy, UnityPerMaterialData[6u].xy);
    r1.xy = _Liquid.Sample(sampler_Liquid, r1.xy).xy;
    r1.xy = r1.yx + (-0.1f).xx;
    r1.xy = clamp((r1.xyxx + r1.xyxx).xy, 0.0f.xx, 1.0f.xx);
    r1.zw = mad(r1.xy, (-2.0f).xx, 3.0f.xx);
    r1.xy = r1.xy * r1.xy;
    r1.xy = r1.xy * r1.zw;
    r0.w *= r1.x;
    r1.z = r1.y * UnityPerMaterialData[30u].x;
    r0.w = max(r0.w, r1.z);
    r1.zw = clamp(((-r2.yyyx) + r2.xxxy).zw, 0.0f.xx, 1.0f.xx);
    r0.w = min(r0.w, r1.z);
    r3.xyz = clamp((UnityPerMaterialData[29u].wzyw + float4(-1.0f, -1.0f, -1.0f, 0.0f)).xyz, 0.0f.xxx, 1.0f.xxx);
    r3.xyz = r1.xxx * r3.xyz;
    r1.xyz = r1.yyy * UnityPerMaterialData[29u].wzy;
    r1.xyz = max(r1.xyz, r3.xyz);
    r1.x = min(r1.w, r1.x);
    r0.w += r1.x;
    r1.x = min(r2.z, r1.y);
    r1.y = r2.y * r2.x;
    r1.y = min(r1.y, r1.z);
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
    float _1147 = max(r0.w, 0.0f);
    r0.w = asfloat((_1147 >= 4.2949673e+09f) ? 4294967295u : uint(_1147));
    r0.w = asfloat(asint(r0.w) << (2 & int(31u)));
    r1.y = asfloat((r1.x >= (-r1.xxxx).y) ? 4294967295u : 0u);
    r1.x = frac(abs(r1.xxxx).x);
    r1.x = (asuint(r1.y) != 0u) ? r1.x : (-r1.xxxx).x;
    r1.x *= 4.0f;
    float _1196 = max(r1.x, 0.0f);
    r1.x = asfloat((_1196 >= 4.2949673e+09f) ? 4294967295u : uint(_1196));
    r0.w = asfloat(asint(r0.w) + asint(r1.x));
    r0.w = asfloat(min(asuint(r0.w), 15u));
    r0.w = 0.0625f * coveragePattern[asint(r0.w)];
    r0.z = asfloat((r0.z >= r0.w) ? 4294967295u : 0u);
    r0.z = asfloat(asuint(r0.z) & 1065353216u);
    r0.z = (-r0.xxxx).z + r0.z;
    r0.z = mad(UnityPerMaterialData[23u].x, r0.z, r0.x);
    r0.x = min(r0.z, r0.x);
    r0.x *= UnityPerMaterialData[22u].w;
    r0.z = clamp((UnityPerMaterialData[23u].yyyy * 1.00001f.xxxx).z, 0.0f, 1.0f);
    r0.z = asfloat((r0.z >= r0.w) ? 4294967295u : 0u);
    r0.z = asfloat(asuint(r0.z) & 1065353216u);
    r0.x = min(r0.x, r0.z);
    r0.z = r0.x + (-0.009f);
    r0.z = ceil(r0.z);
    r0.x = min(r0.z, r0.x);
    r1 = mad(v1, UnityPerMaterialData[13u].xyxy, UnityPerMaterialData[13u].zwzw);
    r0.zw = (-r1.xxxy).zw + r1.zw;
    r0.zw = mad(UnityPerMaterialData[22u].xx, r0.zw, r1.xy);
    r1.xyz = _Cloth_alpha.Sample(sampler_Cloth_alpha, r0.zw).xyz;
    r2.xyz = _Cloth_alpha_bot.Sample(sampler_Cloth_alpha_bot, r0.zw).xyz;
    r2.xyz = (-r2.yzxy).xyz + float3(2.0f, 1.0f, 1.0f);
    r1.xyz = (-r1.yxzy).xyz + float3(2.0f, 1.0f, 1.0f);
    r0.z = round(UnityPerMaterialData[22u].y);
    r0.w = max(r1.x, r0.z);
    r1.xy = min(r1.yz, r2.yz);
    r0.z = max(r0.z, r1.x);
    r0.w = clamp((r0.wwww + (-1.0f).xxxx).w, 0.0f, 1.0f);
    r0.z = min(r0.w, r0.z);
    r0.w = round(UnityPerMaterialData[21u].w);
    r1.x = max(r2.x, r0.w);
    r0.w = max(r1.y, r0.w);
    r1.x = clamp((r1.xxxx + (-1.0f).xxxx).x, 0.0f, 1.0f);
    r0.w = min(r0.w, r1.x);
    r0.z = min(r0.w, r0.z);
    r0.z = round(r0.z);
    r0.w = max(UnityPerMaterialData[39u].z, 0.011f);
    r0.w = min(r0.w, 1.0f);
    r1.x = (-r0.wwww).x + 0.999f;
    r0.y = mad(r0.y, r1.x, r0.w);
    r0.w = mad(r0.x, r0.z, (-r0.yyyy).w);
    r0.x = r0.z * r0.x;
    r0.y = asfloat((0.0f >= r0.y) ? 4294967295u : 0u);
    r0.z = ddx_coarse(r0.x);
    r0.x = ddy_coarse(r0.x);
    r0.x = abs(r0.xxxx).x + abs(r0.zzzz).x;
    r0.z = mad((-r0.xxxx).z, 0.5f, r0.w);
    r0.x = max(r0.x, 0.0001f);
    r0.x = r0.z / r0.x;
    r0.x = clamp((r0.xxxx + 1.0f.xxxx).x, 0.0f, 1.0f);
    r0.x += (-0.0001f);
    r0.x = (asuint(r0.y) != 0u) ? 0.9999f : r0.x;
    r0.y = asfloat(~asuint(r0.y));
    r0.z = asfloat((GlobalsData[4u].z != 0.0f) ? 4294967295u : 0u);
    r0.y = asfloat(asuint(r0.y) & asuint(r0.z));
    r0.x = (asuint(r0.y) != 0u) ? r0.x : r0.w;
    r0.x = asfloat((r0.x < 0.0f) ? 4294967295u : 0u);
    if (asuint(r0.x) != 0u) discard;
    o0 = 0.0f.xxxx;
    StageOutput stage_output;
    stage_output.o0 = o0;
    return stage_output;
}
