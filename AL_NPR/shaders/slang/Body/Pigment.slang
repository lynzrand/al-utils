import Body.Material;

public float3 bodyPigment(float4 base, float4 nipple, float4 underHair, float3 detail)
{
    float3 defaultSkin = float3(0.8900055, 0.6118345, 0.5382356);
    float3 pigment = lerp(defaultSkin, base.rgb, base.a);
    float brightness = sqrt(dot(pigment, float3(0.2126729, 0.7151522, 0.072175)));
    float3 nippleTint = lerp(_Nip_color_01.rgb, _Nip_color_02.rgb, nipple.r * _Nip_color_02.a);
    pigment = lerp(pigment, nippleTint, nipple.a * _Nip_color_01.a);
    pigment = mad(underHair.a * _Under_hair_color.a, mad(underHair.rgb, _Under_hair_color.rgb, -pigment), pigment);
    pigment = lerp(pigment, _hohoakacolor.rgb, detail.b * _SiriakaIntensity);
    float3 detailTint = saturate(mad(brightness, 0.5, -0.3) + _Detail_color_02.rgb);
    return lerp(pigment, detailTint, detail.r * _Detail_color_02.a);
}
