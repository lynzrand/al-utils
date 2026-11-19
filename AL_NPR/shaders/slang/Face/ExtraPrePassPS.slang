import Coverage;

cbuffer Globals : register(b0)
{
    // c3 .x _ScaledScreenParams
    // c4 .z _AlphaToMaskAvailable
    // c5 .x _MainLightPosition
    // c6 .x _MainLightColor
    // c21 .x _WorldSpaceCameraPos
    // c22 .x _ProjectionParams
    // c25 .x unity_OrthoParams
    // c27 .x _ScaleBiasRt
    // c60 .x unity_FogParams
    // c61 .x unity_FogColor
    // c66 .x unity_MatrixV
    float4 GlobalsData[69];
};

cbuffer UnityPerDraw : register(b1)
{
    float4 UnityPerDrawData[32];
};

cbuffer UnityPerMaterial : register(b2)
{
    // c2 .x _LiquidTiling
    // c3 .x _FluidTex_TexelSize
    // c4 .x _FluidTex_ST
    // c5 .x _Nose_color
    // c6 .x _Lip_highlight_color
    // c7 .x _Lip_texture_ST
    // c8 .x _Lip_color
    // c9 .x _CheekHighlight_position
    // c10 .x _Cheek_position
    // c11 .x _Cheek_color
    // c13 .x _Detail_mask_02_ST
    // c14 .x _expressionmap_ST
    // c15 .x _Cheek_highlight_color
    // c16 .x _Create_jm_main_skin_head_ST
    // c17 .x _spcolor
    // c18 .x _Shadow_color
    // c19 .x _spmap_ST
    // c20 .x _hohoakacolor
    // c21 .x _Detail_mask_01_ST
    // c22 .x _Line_color
    // c28 .w _Fluid_Noise_Amount
    // c29 .w _sppower
    // c30 .x _HohoakaIntensity, .y _Cheek_size, .z _Cheek_position_x, .w _Cheek_position_y
    // c31 .x _Cheek_rotation, .y _CheekHighlight_size, .z _CheekHighlight_position_x, .w _CheekHighlight_position_y
    // c32 .x _CheekHighlight_rotation, .y _NoseScale, .z _Line_power, .w _Fluid_Noise_Scale
    // c33 .y _FluidNormalScale, .z _liquidface, .w _Dither
    // c34 .w _Line_width
    float4 UnityPerMaterialData[35];
};

SamplerState sampler_Detail_mask_01 : register(s0);
SamplerState sampler_Detail_mask_02 : register(s1);
SamplerState sampler_Create_jm_main_skin_head : register(s2);
SamplerState sampler_spmap : register(s3);
SamplerState sampler_expressionmap : register(s4);
SamplerState sampler_Cheek_texture : register(s5);
SamplerState sampler_Lip_texture : register(s6);
SamplerState sampler_Nose_texture : register(s7);
SamplerState sampler_FluidTex : register(s8);
SamplerState sampler_LiquidBump : register(s9);
SamplerState sampler_Texture2 : register(s10);
Texture2D<float4> _Detail_mask_02 : register(t0);
Texture2D<float4> _Create_jm_main_skin_head : register(t1);
Texture2D<float4> _spmap : register(t2);
Texture2D<float4> _expressionmap : register(t3);
Texture2D<float4> _Cheek_texture : register(t4);
Texture2D<float4> _Lip_texture : register(t5);
Texture2D<float4> _Nose_texture : register(t6);
Texture2D<float4> _FluidTex : register(t7);
Texture2D<float4> _Texture2 : register(t8);
Texture2D<float4> _Detail_mask_01 : register(t9);
Texture2D<float4> _LiquidBump : register(t10);

struct StageInput
{
    float4 gl_FragCoord : SV_POSITION;
    float4 v1 : TEXCOORD0;
    float3 v2 : TEXCOORD1;
    float4 v3 : TEXCOORD2;
    float4 v4 : TEXCOORD3;
    float4 v5 : TEXCOORD4;
    float4 unused6 : TEXCOORD5;
    float4 unused7 : TEXCOORD6;
    bool gl_FrontFacing : SV_IsFrontFace;
};

struct StageOutput
{
    float4 o0 : SV_Target0;
};

[shader("fragment")]
StageOutput main(StageInput stage_input)
{
    float4 gl_FragCoord = 0;
    bool gl_FrontFacing = false;
    float4 v1 = 0;
    float3 v2 = 0;
    float4 v3 = 0;
    float4 v4 = 0;
    float4 v5 = 0;
    float4 o0 = 0;
    float4 r0 = 0;
    float4 r1 = 0;
    float4 r2 = 0;
    float4 r3 = 0;
    float4 r4 = 0;
    float4 r5 = 0;
    float4 r6 = 0;
    float4 r7 = 0;
    float4 v0 = 0;
    float4 v8 = 0;
    gl_FragCoord = stage_input.gl_FragCoord;
    gl_FragCoord.w = 1.0 / gl_FragCoord.w;
    gl_FrontFacing = stage_input.gl_FrontFacing;
    v1 = stage_input.v1;
    v2 = stage_input.v2;
    v3 = stage_input.v3;
    v4 = stage_input.v4;
    v5 = stage_input.v5;
    float4 _100 = gl_FragCoord;
    _100.w = 1.0f / _100.w;
    v0 = _100;
    v8.x = asfloat(gl_FrontFacing ? 4294967295u : 0u);
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
    float _242 = max(r0.y, 0.0f);
    r0.y = asfloat((_242 >= 4.2949673e+09f) ? 4294967295u : uint(_242));
    r0.y = asfloat(asint(r0.y) << (2 & int(31u)));
    r0.z = asfloat((r0.x >= (-r0.xxxx).z) ? 4294967295u : 0u);
    r0.x = frac(abs(r0.xxxx).x);
    r0.x = (asuint(r0.z) != 0u) ? r0.x : (-r0.xxxx).x;
    r0.x *= 4.0f;
    float _292 = max(r0.x, 0.0f);
    r0.x = asfloat((_292 >= 4.2949673e+09f) ? 4294967295u : uint(_292));
    r0.x = asfloat(asint(r0.x) + asint(r0.y));
    r0.x = asfloat(min(asuint(r0.x), 15u));
    r0.x = 0.0625f * coveragePattern[asint(r0.x)];
    r0.y = clamp((UnityPerMaterialData[33u].wwww * 1.00001f.xxxx).y, 0.0f, 1.0f);
    r0.x = asfloat((r0.y >= r0.x) ? 4294967295u : 0u);
    r0.x = asfloat(asuint(r0.x) & 1065353216u);
    r0.yz = mad(v4.xy, UnityPerMaterialData[21u].xy, UnityPerMaterialData[21u].zw);
    r0.yz = _Detail_mask_01.Sample(sampler_Detail_mask_01, r0.yz).xy;
    r0.zw = (-r0.zzzy).zw + 1.0f.xx;
    r0.w *= UnityPerMaterialData[34u].w;
    r0.z = clamp(mad(r0.zzzz, 1.23f.xxxx, (-0.31f).xxxx).z, 0.0f, 1.0f);
    r0.w = asfloat((r0.w >= 0.05f) ? 4294967295u : 0u);
    r0.w = asfloat(asuint(r0.w) & 1065353216u);
    r0.x = min(r0.w, r0.x);
    r0.w = ddx_coarse(r0.x);
    r1.x = ddy_coarse(r0.x);
    r0.w = abs(r0.wwww).w + abs(r1.xxxx).w;
    r1.x = r0.x + (-0.5f);
    r1.y = mad((-r0.wwww).y, 0.5f, r1.x);
    r0.w = max(r0.w, 0.0001f);
    r0.w = r1.y / r0.w;
    r0.w = clamp((r0.wwww + 1.0f.xxxx).w, 0.0f, 1.0f);
    r0.w += (-0.0001f);
    r1.y = asfloat((GlobalsData[4u].z != 0.0f) ? 4294967295u : 0u);
    r0.w = (asuint(r1.y) != 0u) ? r0.w : r1.x;
    o0.w = (asuint(r1.y) != 0u) ? r0.x : 1.0f;
    r0.x = asfloat((r0.w < 0.0f) ? 4294967295u : 0u);
    if (asuint(r0.x) != 0u) discard;
    r0.xw = mad(v4.xy, UnityPerMaterialData[4u].xy, UnityPerMaterialData[4u].zw);
    r1 = r0.xwxw + float4(12.0f, 34.0f, 12.0f, 34.0f);
    r1 *= UnityPerMaterialData[32u].wwww;
    r2.xy = floor(r1.zw);
    r2.zw = r2.xy + 1.0f.xx;
    r2.z = dot(r2.zw, float2(12.9898f, 78.233f));
    r2.z = sin(r2.z);
    r2.z *= 43758.547f;
    r2.z = frac(r2.z);
    r3.xy = frac(r1.zw);
    r1 *= float4(0.5f, 0.5f, 0.25f, 0.25f);
    r3.zw = r3.xy * r3.xy;
    r3.xy = mad((-r3.xyxx).xy, 2.0f.xx, 3.0f.xx);
    r4.xy = r3.xy * r3.zw;
    r3.xy = mad((-r3.zwzz).xy, r3.xy, 1.0f.xx);
    r5 = r2.xyxy + float4(1.0f, 0.0f, 0.0f, 1.0f);
    r2.x = dot(r2.xy, float2(12.9898f, 78.233f));
    r2.x = sin(r2.x);
    r2.x *= 43758.547f;
    r2.y = dot(r5.zw, float2(12.9898f, 78.233f));
    r2.w = dot(r5.xy, float2(12.9898f, 78.233f));
    r2.yw = sin(r2.yw);
    r2.yw = r2.yw * 43758.547f.xx;
    r2.xyw = frac(r2.xyw);
    r2.zw = r2.zw * r4.xx;
    r2.x = mad(r3.x, r2.x, r2.w);
    r2.y = mad(r3.x, r2.y, r2.z);
    r2.y *= r4.y;
    r2.x = mad(r3.y, r2.x, r2.y);
    r3 = floor(r1);
    r1 = frac(r1);
    r4 = r3.xyxy + float4(1.0f, 0.0f, 0.0f, 1.0f);
    r2.y = dot(r4.zw, float2(12.9898f, 78.233f));
    r2.z = dot(r4.xy, float2(12.9898f, 78.233f));
    r2.yz = sin(r2.yz);
    r2.yz = r2.yz * 43758.547f.xx;
    r4 = r3 + float4(1.0f, 1.0f, 1.0f, 0.0f);
    r2.w = dot(r4.xy, float2(12.9898f, 78.233f));
    r4.x = dot(r4.zw, float2(12.9898f, 78.233f));
    r4.x = sin(r4.x);
    r4.x *= 43758.547f;
    r4.x = frac(r4.x);
    r2.w = sin(r2.w);
    r2.w *= 43758.547f;
    r2.yzw = frac(r2.yzw);
    r5 = r1 * r1;
    r1 = mad(-r1, 2.0f.xxxx, 3.0f.xxxx);
    r6 = r1 * r5;
    r1 = mad(-r5, r1, 1.0f.xxxx);
    r2.w *= r6.x;
    r2.y = mad(r1.x, r2.y, r2.w);
    r2.w = dot(r3.xy, float2(12.9898f, 78.233f));
    r2.w = sin(r2.w);
    r2.w *= 43758.547f;
    r2.w = frac(r2.w);
    r2.yz = r2.yz * r6.yx;
    r1.x = mad(r1.x, r2.w, r2.z);
    r1.x = mad(r1.y, r1.x, r2.y);
    r1.x *= 0.25f;
    r1.x = mad(r2.x, 0.125f, r1.x);
    r2 = r3.zwzw + float4(0.0f, 1.0f, 1.0f, 1.0f);
    r1.y = dot(r3.zw, float2(12.9898f, 78.233f));
    r1.y = sin(r1.y);
    r1.y *= 43758.547f;
    r1.y = frac(r1.y);
    r2.z = dot(r2.zw, float2(12.9898f, 78.233f));
    r2.x = dot(r2.xy, float2(12.9898f, 78.233f));
    r2.xy = sin(r2.xz);
    r2.xy = r2.xy * 43758.547f.xx;
    r2.xy = frac(r2.xy);
    r2.y *= r6.z;
    r2.x = mad(r1.z, r2.x, r2.y);
    r2.x *= r6.w;
    r2.y = r4.x * r6.z;
    r1.y = mad(r1.z, r1.y, r2.y);
    r1.y = mad(r1.w, r1.y, r2.x);
    r1.y = mad(r1.y, 0.5f, r1.x);
    r2 = r0.xwxw * UnityPerMaterialData[32u].wwww;
    r1.zw = floor(r2.zw);
    r3.xy = r1.zw + 1.0f.xx;
    r3.x = dot(r3.xy, float2(12.9898f, 78.233f));
    r3.x = sin(r3.x);
    r3.x *= 43758.547f;
    r3.x = frac(r3.x);
    r3.yz = frac(r2.zw);
    r2 *= float4(0.5f, 0.5f, 0.25f, 0.25f);
    r4.xy = r3.yz * r3.yz;
    r3.yz = mad((-r3.yyzy).yz, 2.0f.xx, 3.0f.xx);
    r4.zw = r3.yz * r4.xy;
    r3.yz = mad((-r4.xxyx).yz, r3.yz, 1.0f.xx);
    r5 = r1.zwzw + float4(1.0f, 0.0f, 0.0f, 1.0f);
    r1.z = dot(r1.zw, float2(12.9898f, 78.233f));
    r1.z = sin(r1.z);
    r1.z *= 43758.547f;
    r1.z = frac(r1.z);
    r1.w = dot(r5.zw, float2(12.9898f, 78.233f));
    r3.w = dot(r5.xy, float2(12.9898f, 78.233f));
    r3.w = sin(r3.w);
    r3.w *= 43758.547f;
    r3.w = frac(r3.w);
    r3.xw = r3.xw * r4.zz;
    r1.z = mad(r3.y, r1.z, r3.w);
    r1.w = sin(r1.w);
    r1.w *= 43758.547f;
    r1.w = frac(r1.w);
    r1.w = mad(r3.y, r1.w, r3.x);
    r1.w *= r4.w;
    r1.z = mad(r3.z, r1.z, r1.w);
    r3 = floor(r2);
    r2 = frac(r2);
    r4 = r3.xyxy + float4(1.0f, 0.0f, 0.0f, 1.0f);
    r1.w = dot(r4.zw, float2(12.9898f, 78.233f));
    r4.x = dot(r4.xy, float2(12.9898f, 78.233f));
    r4.x = sin(r4.x);
    r4.x *= 43758.547f;
    r1.w = sin(r1.w);
    r1.w *= 43758.547f;
    r1.w = frac(r1.w);
    r5 = r3 + float4(1.0f, 1.0f, 1.0f, 0.0f);
    r4.y = dot(r5.xy, float2(12.9898f, 78.233f));
    r4.z = dot(r5.zw, float2(12.9898f, 78.233f));
    r4.yz = sin(r4.yz);
    r4.yz = r4.yz * 43758.547f.xx;
    r4.xyz = frac(r4.xyz);
    r5 = r2 * r2;
    r2 = mad(-r2, 2.0f.xxxx, 3.0f.xxxx);
    r6 = r2 * r5;
    r2 = mad(-r5, r2, 1.0f.xxxx);
    r4.y *= r6.x;
    r1.w = mad(r2.x, r1.w, r4.y);
    r1.w *= r6.y;
    r3.x = dot(r3.xy, float2(12.9898f, 78.233f));
    r3.x = sin(r3.x);
    r3.x *= 43758.547f;
    r3.x = frac(r3.x);
    r3.y = r4.x * r6.x;
    r2.x = mad(r2.x, r3.x, r3.y);
    r1.w = mad(r2.y, r2.x, r1.w);
    r1.w *= 0.25f;
    r1.z = mad(r1.z, 0.125f, r1.w);
    r5 = r3.zwzw + float4(0.0f, 1.0f, 1.0f, 1.0f);
    r1.w = dot(r3.zw, float2(12.9898f, 78.233f));
    r1.w = sin(r1.w);
    r1.w *= 43758.547f;
    r1.w = frac(r1.w);
    r2.x = dot(r5.zw, float2(12.9898f, 78.233f));
    r2.y = dot(r5.xy, float2(12.9898f, 78.233f));
    r2.xy = sin(r2.xy);
    r2.xy = r2.xy * 43758.547f.xx;
    r2.xy = frac(r2.xy);
    r2.x *= r6.z;
    r2.x = mad(r2.z, r2.y, r2.x);
    r2.x *= r6.w;
    r2.y = r4.z * r6.z;
    r1.w = mad(r2.z, r1.w, r2.y);
    r1.w = mad(r2.w, r1.w, r2.x);
    r1.x = mad(r1.w, 0.5f, r1.z);
    r1.xy = r1.xy + (-0.5f).xx;
    r1.xy = r1.xy * UnityPerMaterialData[28u].ww;
    r0.xw = mad(r1.xy, UnityPerMaterialData[3u].xy, r0.xw);
    r1.x = 0.0f;
    r1.y = UnityPerMaterialData[3u].y;
    r1.xy = r0.xw + r1.xy;
    r1.x = _FluidTex.Sample(sampler_FluidTex, r1.xy).w;
    r1.y = _FluidTex.Sample(sampler_FluidTex, r0.xw).w;
    r2.y = (-r1.xxxx).y + r1.y;
    r3.z = UnityPerMaterialData[3u].x;
    r3 = float4(0.0f.x, r3.y, r3.z, 0.0f.x);
    r0.xw = r0.xw + r3.zw;
    r0.x = _FluidTex.Sample(sampler_FluidTex, r0.xw).w;
    r2.x = (-r0.xxxx).x + r1.y;
    r1.xy = r2.xy * UnityPerMaterialData[33u].yy;
    r1.z = 1.0f;
    r0.x = dot(r1.xyz, r1.xyz);
    r0.x = rsqrt(r0.x);
    r1.xyz = r0.xxx * r1.xyz;
    r0.xw = mad(v4.xy, UnityPerMaterialData[13u].xy, UnityPerMaterialData[13u].zw);
    r0.x = _Detail_mask_02.Sample(sampler_Detail_mask_02, r0.xw).z;
    r0.w = (-r0.xxxx).w + r0.y;
    r0.y = clamp((r0.yyyy * 3.3333333f.xxxx).y, 0.0f, 1.0f);
    r0.y = (-r0.yyyy).y + 1.0f;
    r0.z = clamp(((-r0.wwww) + r0.zzzz).z, 0.0f, 1.0f);
    r2.xy = mad(UnityPerMaterialData[2u].zw, v4.xy, UnityPerMaterialData[2u].xy);
    r2.zw = _Texture2.Sample(sampler_Texture2, r2.xy).xy;
    r4.xyz = _LiquidBump.Sample(sampler_LiquidBump, r2.xy).xyw;
    r2.xy = r2.wz + (-0.1f).xx;
    r2.xy = clamp((r2.xyxx + r2.xyxx).xy, 0.0f.xx, 1.0f.xx);
    r2.zw = mad(r2.xy, (-2.0f).xx, 3.0f.xx);
    r2.xy = r2.xy * r2.xy;
    r2.xy = r2.xy * r2.zw;
    r0.w = clamp((UnityPerMaterialData[33u].zzzz + (-1.0f).xxxx).w, 0.0f, 1.0f);
    r0.w *= r2.x;
    r1.w = r2.y * UnityPerMaterialData[33u].z;
    r0.w = max(r0.w, r1.w);
    r0.z = min(r0.z, r0.w);
    r0.z += r0.z;
    r0.w = min(r0.z, 1.0f);
    r4.x *= r4.z;
    r2.xy = mad(r4.xy, 2.0f.xx, (-1.0f).xx);
    r1.w = dot(r2.xy, r2.xy);
    r2.xy = r0.zz * r2.xy;
    r0.z = min(r1.w, 1.0f);
    r0.xz = (-r0.xxzx).xz + 1.0f.xx;
    r0.z = sqrt(r0.z);
    r0.z = max(r0.z, 1e-16f);
    r0.z += (-1.0f);
    r0.z = mad(r0.w, r0.z, 1.0f);
    r1.xyw = r0.zzz * r1.xyz;
    r1.xy = mad(r2.xy, r1.zz, r1.xy);
    r0.z = dot(r1.xyw, r1.xyw);
    r0.z = rsqrt(r0.z);
    r1.xyz = r0.zzz * r1.xyw;
    r2.xyz = v2.zxy * v3.yzx;
    r2.xyz = mad(v2.yzx, v3.zxy, (-r2.xyzx).xyz);
    r2.xyz = r2.xyz * v3.www;
    r0.z = dot(v2, v2);
    r0.z = sqrt(r0.z);
    r0.z = max(r0.z, 1.1754944e-38f);
    r0.z = 1.0f / r0.z;
    r2.xyz = r0.zzz * r2.xyz;
    r4.y = r2.x;
    r5.xyz = r0.zzz * v3.zxy;
    r6.xyz = r0.zzz * v2;
    r4.x = r5.y;
    r4.z = r6.x;
    r4.x = dot(r4.xyz, r1.xyz);
    r5.y = r2.z;
    r2.x = r5.z;
    r2.z = r6.y;
    r4.y = dot(r2.xyz, r1.xyz);
    r5.z = r6.z;
    r4.z = dot(r5.xyz, r1.xyz);
    r0.z = dot(r4.xyz, r4.xyz);
    r0.z = rsqrt(r0.z);
    r1.xyz = r0.zzz * r4.xyz;
    r0.z = r1.y * r1.y;
    r0.z = mad(r1.x, r1.x, (-r0.zzzz).z);
    r2 = r1.yzzx * r1.xyzz;
    r4.x = dot(UnityPerDrawData[28u], r2);
    r4.y = dot(UnityPerDrawData[29u], r2);
    r4.z = dot(UnityPerDrawData[30u], r2);
    r2.xyz = mad(UnityPerDrawData[31u].xyz, r0.zzz, r4.xyz);
    r1.w = 1.0f;
    r4.x = dot(UnityPerDrawData[25u], r1);
    r4.y = dot(UnityPerDrawData[26u], r1);
    r4.z = dot(UnityPerDrawData[27u], r1);
    r1.xyz = r2.xyz + r4.xyz;
    r0.z = dot(float3(0.2126729f, 0.7151522f, 0.072175f), r1.xyz);
    r1.xyz = (-r0.zzzz).xyz + r1.xyz;
    r1.xyz = mad(r1.xyz, 2.0f.xxx, r0.zzz);
    r2.xyz = mad(GlobalsData[6u].xyz, 0.7f.xxx, 0.3f.xxx);
    r1.xyz = clamp(max(r1.xyzx, r2.xyzx).xyz, 0.0f.xxx, 1.0f.xxx);
    r0.z = float(asuint(v8.x));
    r0.z = mad(r0.z, 0.25f, 0.75f);
    r0.z = min(r0.z, 1.0f);
    r1.xyz = r0.zzz * r1.xyz;
    r1.xyz = r1.xyz * UnityPerDrawData[11u].zzz;
    r0.z = dot(GlobalsData[5u].xyz, GlobalsData[5u].xyz);
    r0.z = max(r0.z, 1.1754944e-38f);
    r0.z = rsqrt(r0.z);
    r2.xyz = r0.zzz * GlobalsData[5u].xyz;
    r0.z = dot(r6.xyz, r2.xyz);
    r0.z += (-0.3f);
    r0.z = clamp((r0.zzzz * 1.4285715f.xxxx).z, 0.0f, 1.0f);
    r1.xyz = clamp((r0.zzzz * r1.xyzx).xyz, 0.0f.xxx, 1.0f.xxx);
    r0.z = dot(r6.xyz, r6.xyz);
    r0.z = rsqrt(r0.z);
    r2.xyz = r0.zzz * r6.xyz;
    r4.xyz = (-v1.xyzx).xyz + GlobalsData[21u].xyz;
    r0.z = dot(r4.xyz, r4.xyz);
    r0.z = rsqrt(r0.z);
    r4.xyz = r0.zzz * r4.xyz;
    r0.z = asfloat((GlobalsData[25u].w == 0.0f) ? 4294967295u : 0u);
    r5.x = (asuint(r0.z) != 0u) ? r4.x : GlobalsData[66u].z;
    r5.y = (asuint(r0.z) != 0u) ? r4.y : GlobalsData[67u].z;
    r5.z = (asuint(r0.z) != 0u) ? r4.z : GlobalsData[68u].z;
    r4.xyz = r5.xyz + float3(0.0f, 0.36f, -0.03f);
    r0.z = dot(r4.xyz, r4.xyz);
    r0.z = rsqrt(r0.z);
    r4.xyz = r0.zzz * r4.xyz;
    r0.z = dot(r4.xyz, r2.xyz);
    r0.z += 1.0f;
    r0.z = clamp(mad(r0.zzzz, (-0.75f).xxxx, 1.5f.xxxx).z, 0.0f, 1.0f);
    r0.z *= UnityPerMaterialData[18u].w;
    r0.x *= r0.z;
    r2.xyz = UnityPerMaterialData[18u].xyz + (-1.0f).xxx;
    r0.xzw = mad(r0.xxx, r2.xyz, 1.0f.xxx);
    r2.xyz = mad(UnityPerMaterialData[30u].yzw, float3(0.2f, 0.37f, -0.23f), UnityPerMaterialData[10u].wxy);
    r2.yz = r2.yz + v4.zw;
    r1.w = r2.x + (-0.1f);
    r1.w = mad(r1.w, -2.0f, 2.0f);
    r2.xy = r2.yz + float2(-0.15f, 0.08f);
    r2.z = r1.w + r1.w;
    r1.w = (-r1.wwww).w + 0.5f;
    r2.xy = mad(r2.zz, r2.xy, r1.ww);
    r2.xy = r2.xy + (-0.5f).xx;
    r1.w = UnityPerMaterialData[10u].z + (-UnityPerMaterialData[31u].xxxx).w;
    r1.w += 0.5f;
    r1.w *= 6.2831855f;
    r4.x = sin(r1.w);
    r5.x = cos(r1.w);
    r6.z = r4.x;
    r6.y = r5.x;
    r6.x = (-r4.xxxx).x;
    r4.y = dot(r2.xy, r6.xy);
    r4.x = dot(r2.xy, r6.yz);
    r2.xy = r4.xy + 0.5f.xx;
    r1.w = _Cheek_texture.Sample(sampler_Cheek_texture, r2.xy).x;
    r1.w *= UnityPerMaterialData[11u].w;
    r2.xy = mad(v4.xy, UnityPerMaterialData[19u].xy, UnityPerMaterialData[19u].zw);
    r2.x = _spmap.Sample(sampler_spmap, r2.xy).x;
    r2.x *= UnityPerMaterialData[29u].w;
    r2.yz = mad(v4.xy, UnityPerMaterialData[16u].xy, UnityPerMaterialData[16u].zw);
    r4 = _Create_jm_main_skin_head.Sample(sampler_Create_jm_main_skin_head, r2.yz);
    r2.yzw = r4.xyz + (-1.0f).xxx;
    r2.yzw = mad(r4.www, r2.yzw, 1.0f.xxx);
    r4.xyz = (-r2.yzwy).xyz + UnityPerMaterialData[17u].xyz;
    r2.xyz = mad(r2.xxx, r4.xyz, r2.yzw);
    r2.w = dot(r2.xyz, float3(0.2126729f, 0.7151522f, 0.072175f));
    r2.w = sqrt(r2.w);
    r2.w = max(r2.w, 0.1f);
    r2.w = min(r2.w, 1.0f);
    r4.xyz = mad(UnityPerMaterialData[20u].xyz, r2.www, (-r2.xyzx).xyz);
    r3.zw = mad(v4.xy, UnityPerMaterialData[14u].xy, UnityPerMaterialData[14u].zw);
    r2.w = _expressionmap.Sample(sampler_expressionmap, r3.zw).x;
    r2.w *= UnityPerMaterialData[30u].x;
    r2.w *= UnityPerMaterialData[20u].w;
    r2.xyz = mad(r2.www, r4.xyz, r2.xyz);
    r4.xyz = (-r2.xyzx).xyz + UnityPerMaterialData[11u].xyz;
    r2.xyz = mad(r1.www, r4.xyz, r2.xyz);
    r4.xyz = (-r2.xyzx).xyz + 1.0f.xxx;
    r5.xyz = (-UnityPerMaterialData[15u].xyzx).xyz + 1.0f.xxx;
    r4.xyz = mad((-r5.xyzx).xyz, r4.xyz, (-r2.xyzx).xyz);
    r4.xyz = r4.xyz + 1.0f.xxx;
    r5.xyz = mad(UnityPerMaterialData[31u].yzw, float3(0.2f, 0.4f, -0.27f), UnityPerMaterialData[9u].wxy);
    r3.zw = r5.yz + v4.zw;
    r1.w = r5.x + (-0.1f);
    r1.w = mad(r1.w, -2.0f, 2.0f);
    r3.zw = r3.zw + float2(-0.2f, 0.12f);
    r2.w = r1.w + r1.w;
    r1.w = (-r1.wwww).w + 0.5f;
    r3.zw = mad(r2.ww, r3.zw, r1.ww);
    r3.zw = r3.zw + (-0.5f).xx;
    r1.w = UnityPerMaterialData[9u].z + (-UnityPerMaterialData[32u].xxxx).w;
    r1.w += 0.5f;
    r1.w *= 6.2831855f;
    r5.x = sin(r1.w);
    r6.x = cos(r1.w);
    r7.z = r5.x;
    r7.y = r6.x;
    r7.x = (-r5.xxxx).x;
    r5.y = dot(r3.zw, r7.xy);
    r5.x = dot(r3.zw, r7.yz);
    r3.zw = r5.xy + 0.5f.xx;
    r1.w = _Cheek_texture.Sample(sampler_Cheek_texture, r3.zw).z;
    r1.w *= UnityPerMaterialData[15u].w;
    r2.xyz = clamp(mad(r1.wwww, r4.xyzx, r2.xyzx).xyz, 0.0f.xxx, 1.0f.xxx);
    r4.xyz = (-r2.xyzx).xyz + UnityPerMaterialData[8u].xyz;
    r3.zw = mad(v5.xy, UnityPerMaterialData[7u].xy, UnityPerMaterialData[7u].zw);
    r3.zw = _Lip_texture.Sample(sampler_Lip_texture, r3.zw).xz;
    r1.w = r3.z * UnityPerMaterialData[8u].w;
    r2.w = r3.w * UnityPerMaterialData[6u].w;
    r2.xyz = mad(r1.www, r4.xyz, r2.xyz);
    r2.xyz = mad(UnityPerMaterialData[6u].xyz, r2.www, r2.xyz);
    r4.xyz = (-r2.xyzx).xyz + UnityPerMaterialData[5u].xyz;
    r3.y = mad(UnityPerMaterialData[32u].y, 0.08f, -0.04f);
    r5.xyz = mad(UnityPerMaterialData[32u].yyz, float3(0.4f, -0.2f, 0.8f), float3(0.8f, 0.1f, 0.2f));
    r3.zw = mad(v5.zw, r5.xx, r5.yy);
    r3.xy = r3.xy + r3.zw;
    r1.w = _Nose_texture.Sample(sampler_Nose_texture, r3.xy).x;
    r1.w *= UnityPerMaterialData[5u].w;
    r2.xyz = mad(r1.www, r4.xyz, r2.xyz);
    r3.xyz = r0.xzw * r2.xyz;
    r0.xzw = mad((-r0.xxzw).xzw, r2.xyz, UnityPerMaterialData[22u].xyz);
    r0.xzw = mad(r5.zzz, r0.xzw, r3.xyz);
    r0.xyz = mad(r1.xyz, r0.yyy, r0.xzw);
    r1.xyz = (-r0.xyzx).xyz + GlobalsData[61u].xyz;
    r0.w = clamp(GlobalsData[60u].x, 0.0f, 1.0f);
    o0.xyz = mad(r0.www, r1.xyz, r0.xyz);
    StageOutput stage_output;
    stage_output.o0 = o0;
    return stage_output;
}
