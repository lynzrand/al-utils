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
    // c39 .y _ShadowClip
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
    float4 v0 = 0;
    gl_FragCoord = stage_input.gl_FragCoord;
    gl_FragCoord.w = 1.0 / gl_FragCoord.w;
    v1 = stage_input.v1;
    float4 _88 = gl_FragCoord;
    _88.w = 1.0f / _88.w;
    v0 = _88;
    r0.xyz = GlobalsData[21u].xyz + (-UnityPerDrawData[3u].xyzx).xyz;
    r0.x = dot(r0.xyz, r0.xyz);
    r0.x = sqrt(r0.x);
    r0.x = mad(r0.x, -0.09090909f, 1.0f);
    r0.x = max(r0.x, 0.0f);
    r0.y = _Detail_mask_01.Sample(sampler_Detail_mask_01, v1.xy).z;
    r0.y = (-r0.yyyy).y + 1.0f;
    r0.y *= UnityPerMaterialData[32u].x;
    r0.y *= UnityPerMaterialData[31u].w;
    r0.x = r0.y * r0.x;
    r0.y = clamp((r0.yyyy * 4.0f.xxxx).y, 0.0f, 1.0f);
    r0.y *= UnityPerMaterialData[24u].y;
    r0.z = max(r0.x, 0.0f);
    r0.x = clamp((r0.xxxx + r0.xxxx).x, 0.0f, 1.0f);
    r0.z = min(r0.z, 0.6f);
    r1.xy = mad(r0.zz, 0.0007f.xx, v1.xy);
    r0.w = _Create_main_texture.SampleBias(sampler_Create_main_texture, r1.xy, UnityPerMaterialData[28u].w).w;
    r1.x = r0.z * 0.0007f;
    r2.xy = mad((-r0.zzzz).xy, 0.0007f.xx, v1.xy);
    r0.z = _Create_main_texture.SampleBias(sampler_Create_main_texture, r2.xy, UnityPerMaterialData[28u].w).w;
    r1.zw = (-r1.xxxx).zw;
    r1.y = 0.0f;
    r2 = r1.xzwy + v1.xyxy;
    r1.z = _Create_main_texture.SampleBias(sampler_Create_main_texture, r2.xy, UnityPerMaterialData[28u].w).w;
    r1.w = _Create_main_texture.SampleBias(sampler_Create_main_texture, r2.zw, UnityPerMaterialData[28u].w).w;
    r0.w = max(r0.w, r1.z);
    r2 = r1.xyyx + v1.xyxy;
    r3 = mad(r1.yxxx, float4(1.0f, -1.0f, -1.0f, 1.0f), v1.xyxy);
    r1.x = _Create_main_texture.SampleBias(sampler_Create_main_texture, r2.xy, UnityPerMaterialData[28u].w).w;
    r1.y = _Create_main_texture.SampleBias(sampler_Create_main_texture, r2.zw, UnityPerMaterialData[28u].w).w;
    r1.x = max(r1.y, r1.x);
    r0.w = max(r0.w, r1.x);
    r1.x = _Create_main_texture.SampleBias(sampler_Create_main_texture, r3.xy, UnityPerMaterialData[28u].w).w;
    r1.y = _Create_main_texture.SampleBias(sampler_Create_main_texture, r3.zw, UnityPerMaterialData[28u].w).w;
    r0.z = max(r0.z, r1.y);
    r1.x = max(r1.x, r1.w);
    r0.z = max(r0.z, r1.x);
    r0.z = max(r0.z, r0.w);
    r0.w = _Create_main_texture.SampleLevel(sampler_Create_main_texture, v1.xy, UnityPerMaterialData[28u].w).w;
    r0.z = max(r0.w, r0.z);
    r0.z += (-0.3f);
    r0.z = clamp((r0.zzzz * 2.5f.xxxx).z, 0.0f, 1.0f);
    r0.z = (-r0.wwww).z + r0.z;
    r0.x = mad(r0.x, r0.z, r0.w);
    r1 = _Create_main_texture.SampleBias(sampler_Create_main_texture, v1.xy, UnityPerMaterialData[28u].w);
    r0.x += (-r1.wwww).x;
    r0.x = mad(r0.y, r0.x, r1.w);
    r0.yzw = UnityPerMaterialData[9u].xyz + (-UnityPerMaterialData[15u].xxyz).yzw;
    r2.xy = mad(v1.xy, UnityPerMaterialData[1u].xy, UnityPerMaterialData[1u].zw);
    r2.xyz = _ColorMask.Sample(sampler_ColorMask, r2.xy).xyz;
    r0.yzw = mad(r2.xxx, r0.yzw, UnityPerMaterialData[15u].xyz);
    r3.xyz = (-r0.yzwy).xyz + UnityPerMaterialData[3u].xyz;
    r0.yzw = mad(r2.yyy, r3.xyz, r0.yzw);
    r2.xyw = (-r0.yzyw).xyw + UnityPerMaterialData[14u].xyz;
    r0.yzw = mad(r2.zzz, r2.xyw, r0.yzw);
    r0.yzw = r1.xyz * r0.yzw;
    r2.x = asfloat((0.0f != UnityPerMaterialData[29u].x) ? 4294967295u : 0u);
    uint3 _554 = asuint(r2.xxx);
    bool3 _561 = bool3(_554.x != 0u, _554.y != 0u, _554.z != 0u);
    r0.yzw = float3(_561.x ? r0.y : r1.x, _561.y ? r0.z : r1.y, _561.z ? r0.w : r1.z);
    r1.x = r1.w + (-0.3f);
    r1.x = clamp((r1.xxxx * 1.4285715f.xxxx).x, 0.0f, 1.0f);
    r0.y = dot(r0.yzw, float3(0.299f, 0.587f, 0.114f));
    r0.y = clamp(mad(r0.yyyy, 0.6f.xxxx, 0.4f.xxxx).y, 0.0f, 1.0f);
    r0.zw = mad(v1.xy, UnityPerMaterialData[5u].xy, UnityPerMaterialData[5u].zw);
    r0.z = _Detail_mask_01.Sample(sampler_Detail_mask_01, r0.zw).x;
    r0.z = clamp(mad(r0.zzzz, UnityPerMaterialData[27u].wwww, UnityPerMaterialData[33u].yyyy).z, 0.0f, 1.0f);
    r0.w = r0.z * UnityPerMaterialData[27u].y;
    r1.yz = mad(v1.xy, UnityPerMaterialData[4u].xy, UnityPerMaterialData[4u].zw);
    r1.yzw = _liquidmask.Sample(sampler_liquidmask, r1.yz).xyz;
    r2.xyz = max(r1.wwz, r1.zyy);
    r2.xyz = clamp((r1.yzwy + (-r2.xyzx)).xyz, 0.0f.xxx, 1.0f.xxx);
    r0.w = min(r0.w, r2.x);
    r2.x = r0.z * UnityPerMaterialData[25u].w;
    r3.xy = r0.zz * UnityPerMaterialData[20u].zy;
    r0.z = min(r2.y, r2.x);
    r0.z += r0.w;
    r0.w = min(r1.z, r1.y);
    r2.w = clamp(((-r1.wwww) + r0.wwww).w, 0.0f, 1.0f);
    r2.xy = min(r2.zw, r3.xy);
    r0.z += r2.x;
    r0.z = clamp((r2.yyyy + r0.zzzz).z, 0.0f, 1.0f);
    r0.z = sqrt(r0.z);
    r0.y = r0.z * r0.y;
    r0.x = clamp(mad(-UnityPerMaterialData[20u].xxxx, r0.yyyy, r0.xxxx).x, 0.0f, 1.0f);
    r0.y = mad(r1.x, -2.0f, 3.0f);
    r0.z = r1.x * r1.x;
    r0.y = r0.z * r0.y;
    r0.z = clamp((UnityPerMaterialData[30u].xxxx + (-1.0f).xxxx).z, 0.0f, 1.0f);
    r2.xy = mad(UnityPerMaterialData[6u].zw, v1.xy, UnityPerMaterialData[6u].xy);
    r2.xy = _Liquid.Sample(sampler_Liquid, r2.xy).xy;
    r2.xy = r2.yx + (-0.1f).xx;
    r2.xy = clamp((r2.xyxx + r2.xyxx).xy, 0.0f.xx, 1.0f.xx);
    r2.zw = mad(r2.xy, (-2.0f).xx, 3.0f.xx);
    r2.xy = r2.xy * r2.xy;
    r2.xy = r2.xy * r2.zw;
    r0.z *= r2.x;
    r0.w = r2.y * UnityPerMaterialData[30u].x;
    r0.z = max(r0.w, r0.z);
    r2.zw = clamp(((-r1.zzzy) + r1.yyyz).zw, 0.0f.xx, 1.0f.xx);
    r0.z = min(r0.z, r2.z);
    r3.xyz = clamp((UnityPerMaterialData[29u].wzyw + float4(-1.0f, -1.0f, -1.0f, 0.0f)).xyz, 0.0f.xxx, 1.0f.xxx);
    r3.xyz = r2.xxx * r3.xyz;
    r2.xyz = r2.yyy * UnityPerMaterialData[29u].wzy;
    r2.xyz = max(r2.xyz, r3.xyz);
    r0.w = min(r2.w, r2.x);
    r0.z = r0.w + r0.z;
    r0.w = min(r1.w, r2.y);
    r1.x = r1.z * r1.y;
    r1.x = min(r1.x, r2.z);
    r0.z = r0.w + r0.z;
    r0.z = clamp((r1.xxxx + r0.zzzz).z, 0.0f, 1.0f);
    r0.z += (-0.01f);
    r0.z = clamp((r0.zzzz * 1.4492754f.xxxx).z, 0.0f, 1.0f);
    r0.w = mad(r0.z, -2.0f, 3.0f);
    r0.z *= r0.z;
    r0.z *= r0.w;
    r0.yz = min(r0.yz, 1.0f.xx);
    r0.y *= r0.z;
    r0.x = max(r0.y, r0.x);
    r0.y = r0.x * 1.00001f;
    r0.y = min(r0.y, 1.0f);
    r0.zw = 1.0f.xx / GlobalsData[3u].xy;
    r1.xy = r0.zw * v0.xy;
    r0.z = mad(r1.y, GlobalsData[27u].x, GlobalsData[27u].y);
    r1.z = (-r0.zzzz).z + 1.0f;
    r0.zw = r1.xz * GlobalsData[3u].xy;
    r1.x = mad((-r1.zzzz).x, GlobalsData[3u].y, GlobalsData[3u].y);
    r1.y = asfloat((GlobalsData[22u].x < 0.0f) ? 4294967295u : 0u);
    r0.w = (asuint(r1.y) != 0u) ? r1.x : r0.w;
    r0.zw = r0.zw * 0.25f.xx;
    r1.x = asfloat((r0.w >= (-r0.wwww).x) ? 4294967295u : 0u);
    r0.w = frac(abs(r0.wwww).w);
    r0.w = (asuint(r1.x) != 0u) ? r0.w : (-r0.wwww).w;
    r0.w *= 4.0f;
    float _1127 = max(r0.w, 0.0f);
    r0.w = asfloat((_1127 >= 4.2949673e+09f) ? 4294967295u : uint(_1127));
    r0.w = asfloat(asint(r0.w) << (2 & int(31u)));
    r1.x = asfloat((r0.z >= (-r0.zzzz).x) ? 4294967295u : 0u);
    r0.z = frac(abs(r0.zzzz).z);
    r0.z = (asuint(r1.x) != 0u) ? r0.z : (-r0.zzzz).z;
    r0.z *= 4.0f;
    float _1176 = max(r0.z, 0.0f);
    r0.z = asfloat((_1176 >= 4.2949673e+09f) ? 4294967295u : uint(_1176));
    r0.z = asfloat(asint(r0.z) + asint(r0.w));
    r0.z = asfloat(min(asuint(r0.z), 15u));
    r0.z = 0.0625f * coveragePattern[asint(r0.z)];
    r0.y = asfloat((r0.y >= r0.z) ? 4294967295u : 0u);
    r0.y = asfloat(asuint(r0.y) & 1065353216u);
    r0.y = (-r0.xxxx).y + r0.y;
    r0.y = mad(UnityPerMaterialData[23u].x, r0.y, r0.x);
    r0.x = min(r0.y, r0.x);
    r0.x *= UnityPerMaterialData[22u].w;
    r0.y = clamp((UnityPerMaterialData[23u].yyyy * 1.00001f.xxxx).y, 0.0f, 1.0f);
    r0.y = asfloat((r0.y >= r0.z) ? 4294967295u : 0u);
    r0.y = asfloat(asuint(r0.y) & 1065353216u);
    r0.x = min(r0.x, r0.y);
    r0.y = r0.x + (-0.009f);
    r0.y = ceil(r0.y);
    r0.x = min(r0.y, r0.x);
    r1 = mad(v1, UnityPerMaterialData[13u].xyxy, UnityPerMaterialData[13u].zwzw);
    r0.yz = (-r1.xxyx).yz + r1.zw;
    r0.yz = mad(UnityPerMaterialData[22u].xx, r0.yz, r1.xy);
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
    r1.x = round(UnityPerMaterialData[21u].w);
    r0.yw = max(r0.yw, r1.xx);
    r0.y = clamp((r0.yyyy + (-1.0f).xxxx).y, 0.0f, 1.0f);
    r0.y = min(r0.y, r0.w);
    r0.y = min(r0.y, r0.z);
    r0.y = round(r0.y);
    r0.z = r0.y * r0.x;
    r0.x = mad(r0.x, r0.y, (-UnityPerMaterialData[39u].yyyy).x);
    r0.y = ddx_coarse(r0.z);
    r0.z = ddy_coarse(r0.z);
    r0.y = abs(r0.zzzz).y + abs(r0.yyyy).y;
    r0.z = mad((-r0.yyyy).z, 0.5f, r0.x);
    r0.y = max(r0.y, 0.0001f);
    r0.y = r0.z / r0.y;
    r0.y = clamp((r0.yyyy + 1.0f.xxxx).y, 0.0f, 1.0f);
    r0.y += (-0.0001f);
    r0.z = asfloat((0.0f >= UnityPerMaterialData[39u].y) ? 4294967295u : 0u);
    r0.y = (asuint(r0.z) != 0u) ? 0.9999f : r0.y;
    r0.z = asfloat(~asuint(r0.z));
    r0.w = asfloat((GlobalsData[4u].z != 0.0f) ? 4294967295u : 0u);
    r0.z = asfloat(asuint(r0.z) & asuint(r0.w));
    r0.x = (asuint(r0.z) != 0u) ? r0.y : r0.x;
    r0.x = asfloat((r0.x < 0.0f) ? 4294967295u : 0u);
    if (asuint(r0.x) != 0u) discard;
    o0 = 0.0f.xxxx;
    StageOutput stage_output;
    stage_output.o0 = o0;
    return stage_output;
}
