import Materials.Face.Bindings;
import Materials.Face.Material;

// The cheek artwork uses different travel and pivot settings for its red
// pigment channel and blue highlight channel. Both rotate about UV (0.5, 0.5).
float2 cheekUV(float2 uv, float4 placement, float size, float2 translation,
               float rotation, float2 travel, float2 pivot)
{
    float scale = mad(mad(size, 0.2, placement.w) - 0.1, -2, 2);
    float2 center = mad(translation, travel, placement.xy);
    float2 p = mad(scale + scale, center + uv + pivot, -scale + 0.5) - 0.5;
    float angle = ((placement.z - rotation) + 0.5) * 6.2831855;
    float sine, cosine;
    sincos(angle, sine, cosine);
    return float2(dot(p, float2(cosine, sine)), dot(p, float2(-sine, cosine))) + 0.5;
}

public struct FaceMakeup
{
    public float3 pigment;
    public float3 basePigment;
    public float4 nose;
    public float4 spot;
    public float lipHighlight;
    public float cheekHighlight;
}

public FaceMakeup sampleFaceMakeup(StageInput input)
{
    float2 uv = input.uv0Uv1.xy;
#if SKIN_PREPASS
    float2 noseUV = input.uv3Uv2.zw;
    float2 lipUV = input.uv3Uv2.xy;
#else
    float2 noseUV = input.uv2Uv3.xy;
    float2 lipUV = input.uv2Uv3.zw;
#endif
    noseUV = mad(noseUV, mad(_NoseScale, 0.4, 0.8), mad(_NoseScale, -0.2, 0.1));
    noseUV.y += mad(_NoseScale, 0.08, -0.04);
    float4 nose = _Nose_texture.Sample(sampler_Nose_texture, noseUV);
    float4 lip = _Lip_texture.Sample(sampler_Lip_texture, mad(lipUV, _Lip_texture_ST.xy, _Lip_texture_ST.zw));
    float2 cheek = cheekUV(input.uv0Uv1.zw, _Cheek_position, _Cheek_size,
        float2(_Cheek_position_x, _Cheek_position_y), _Cheek_rotation, float2(0.37, -0.23), float2(-0.15, 0.08));
    float2 highlight = cheekUV(input.uv0Uv1.zw, _CheekHighlight_position, _CheekHighlight_size,
        float2(_CheekHighlight_position_x, _CheekHighlight_position_y), _CheekHighlight_rotation,
        float2(0.4, -0.27), float2(-0.2, 0.12));

    FaceMakeup makeup;
    makeup.nose = nose;
    makeup.spot = _spmap.Sample(sampler_spmap, mad(uv, _spmap_ST.xy, _spmap_ST.zw));
    makeup.cheekHighlight = _Cheek_texture.Sample(sampler_Cheek_texture, highlight).b * _Cheek_highlight_color.a;
    makeup.lipHighlight = lip.b * _Lip_highlight_color.a;

    float4 base = _Create_jm_main_skin_head.Sample(sampler_Create_jm_main_skin_head,
        mad(uv, _Create_jm_main_skin_head_ST.xy, _Create_jm_main_skin_head_ST.zw));
    float3 pigment = lerp(float3(1), base.rgb, base.a);
    makeup.basePigment = pigment;
    pigment = lerp(pigment, _spcolor.rgb, makeup.spot.r * _sppower);
    float blush = _expressionmap.Sample(sampler_expressionmap, mad(uv, _expressionmap_ST.xy, _expressionmap_ST.zw)).r;
    float brightness = clamp(sqrt(dot(pigment, float3(0.2126729, 0.7151522, 0.072175))), 0.1, 1);
    pigment = mad((blush * _HohoakaIntensity) * _hohoakacolor.a, mad(_hohoakacolor.rgb, brightness, -pigment), pigment);
    pigment = lerp(pigment, _Cheek_color.rgb, _Cheek_texture.Sample(sampler_Cheek_texture, cheek).r * _Cheek_color.a);
    float3 highlightDelta = mad(-(1 - _Cheek_highlight_color.rgb), 1 - pigment, -pigment) + 1;
    pigment = saturate(mad(makeup.cheekHighlight, highlightDelta, pigment));
    pigment = lerp(pigment, _Lip_color.rgb, lip.r * _Lip_color.a);
    pigment = mad(_Lip_highlight_color.rgb, makeup.lipHighlight, pigment);
    makeup.pigment = lerp(pigment, _Nose_color.rgb, nose.r * _Nose_color.a);
    return makeup;
}
