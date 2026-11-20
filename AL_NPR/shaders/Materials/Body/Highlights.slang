import Materials.Body.Bindings;
import Materials.Body.Material;
import Materials.Body.Surface;
import Materials.Skin.Lighting;
import Materials.Skin.Frame;
import Surface.MaterialColor;
import Lighting.Reflectance;
import Lighting.ToonPalette;

/// Key-light state for the body palette, specular lobes and subsurface tint.
public struct BodyKey
{
    /// Visibility of the main light at the surface, from zero in shadow to one in light.
    public float visibility;
    /// Shadow visibility reshaped into the palette band, with a fallback as key presence fades.
    public float bandVisibility;
    /// Direct palette band evaluated from the body shading normal and the selected light response.
    public float band;
    /// Direct palette band evaluated from the geometric normal, used for shadow tint and highlights.
    public float surfaceBand;
    /// View-conditioned key direction for diffuse shading of the outward or inward triangle face.
    public float3 faceLight;
    /// View-conditioned direction used by the body's artist ramp.
    public float3 rampLight;
    /// View-conditioned direction that biases the main and secondary rim lobes.
    public float3 rimLight;
    /// Key-light exposure, presence and ramp controls derived from RGB.
    public PaletteLight palette;
};

/// Builds palette directions and direct weights from the facing sign, main visibility and the gathered skin
/// response.
public BodyKey prepareBodyKey(BodySurface s, bool front, float visibility, SkinLights lights)
{
    BodyKey k;
    float3 color = skinKeyColor();
    k.palette = PaletteLight(color);
    k.visibility = visibility;
    k.bandVisibility = lerp(0.7, smoothstep(0.05, 0.7, visibility), k.palette.presence);
    PaletteDirections directions = PaletteDirections(color, s.view, normalize(s.key) * (front ? 1 : -1));
    k.faceLight = directions.diffuse;
    k.rimLight = directions.rim;
    k.rampLight = directions.ramp;
    k.band = k.bandVisibility * lights.paletteWeight(saturate((dot(s.artisticNormal, k.faceLight) - 0.05) * 5));
    k.surfaceBand = k.bandVisibility * lights.paletteWeight(saturate((dot(normalize(s.basis.normal), k.faceLight) - 0.05) * 5));
    return k;
}

/// Local crease and occlusion masks assembled from general and chest-specific detail.
public struct BodyShade
{
    /// Local weight from chest and fine detail creases, used to suppress the rim.
    public float creases;
    /// Combined general and chest-specific crease darkening for the palette and bounce.
    public float occlusion;
};

/// Combines chest creases, UV0 detail and bust-specific contrast into separate rim and palette masks.
public BodyShade sampleBodyShade(BodySurface s, float2 uv)
{
    float chest = s.detail.g * min(mad(max(s.bustMask * 0.75, _Shadow_color.a), 0.7, 0.3), 1);
    float bustShadow = saturate(s.bustMask * chest * _Bust_shadowonoff * saturate((_Bust_size - 0.4) * 2))
                     / clamp(1 - _mdGBustPower * 0.5, 0.5, 1);
    float2 detailUV = mad(uv, _Detail_mask_02_ST.xy, _Detail_mask_02_ST.zw);
    float fine = _Detail_mask_02.Sample(sampler_Detail_mask_02, detailUV).g * _SkinIntensity;
    BodyShade shade;
    shade.creases = max(chest * (1 - s.bustMask), fine * saturate(mad(_Shadow_color.a, 0.7, 0.3)));
    float power = clamp(1 - ((1 - s.detail.b) * _mdGPower) * 0.5, 0.5, 1);
    float creases = saturate(shade.creases / power) * lerp(_mdGIntensity, 0.5, s.detail.b);
    shade.occlusion = max(min(bustShadow, 1) * _mdGBustIntensity, max(creases, 0));
    return shade;
}

/// Maps a view/normal dot product to the two lookup weights used for the red and green painted shine lobes.
float2 shineLobes(float3 view, float3 normal)
{
    float facing = dot(normalize(view), normal);
    float2 base = (_shine_scale - 1) * float2(1.5, 0.5);
    return mad((facing - float2(0.95, 0.7)) * (float2(1, 0.59) - base), float2(20, 3.3333333), base);
}

/// Samples two scales of the shine artwork in view-projected UV, then blends chest and general highlights.
public float paintedShine(BodySurface s, BodyKey k)
{
    float2 uv = mad(k.faceLight.xy, 0.1, toView(s.dryNormal).xy) / mad(_shine_scale, 0.4, 0.6);
    float2 center = shineLobes(s.view + float3(0.1, 0, 0), s.dryNormal);
    float2 upper = shineLobes(s.view + float3(0, 0.8, 0), s.dryNormal);
    float2 maskCenter = float2(_shine_texture.Sample(sampler_shine_texture, uv * 1.33 + 0.5).r,
                               _shine_texture.Sample(sampler_shine_texture, uv * 0.6 + 0.5).g);
    float2 maskUpper = float2(_shine_texture.Sample(sampler_shine_texture, uv * 1.33 + float2(0.5, -0.3)).r,
                              _shine_texture.Sample(sampler_shine_texture, uv * 0.6 + float2(0.5, 0.18)).g);
    float2 power = _shine_power * float2(0.9, 0.55);
    float2 lobes = lerp(saturate(maskCenter * center * power), saturate(maskUpper * upper * power), s.bustMask);
    float facing = clamp(dot(s.basis.normal, k.faceLight) * k.surfaceBand, 0.5, 2);
    float mask = 1 - s.regions.r;
    return saturate(mask) * ((mask * facing) * (lobes.r + lobes.g)) * _Highlight_color.a * 1.2;
}

/// Silhouette and transmission terms evaluated before final body pigment composition.
public struct BodyRim
{
    /// Main silhouette weight for the HDR highlight and matcap blends.
    public float main;
    /// Secondary grazing weight modulated by key visibility and skin luminance.
    public float secondary;
    /// RGB backscatter tint weighted by facing, visibility and the material subsurface gain.
    public float3 transmission;
};

/// Evaluates two masked grazing lobes and a backlit tint from view, light, regional masks and front-face
/// orientation.
public BodyRim bodyRim(BodySurface s, BodyKey k, BodyShade shade, StageInput input)
{
    float3 normal = normalize(s.artisticNormal);
    float3 slope = abs(s.cameraOffset) - input.normalOS;
    float exponent = clamp(mad(saturate(slope.y / length(slope)) - 0.25, 4, 1), 1, 3) * 8;
    float edge = min(grazingRim(s.artisticNormal, s.view, exponent) * 32, 1)
               * saturate((grazingRim(normalize(s.artisticNormal * float3(1, 0.1, 1)), s.view, exponent) * 32 - 0.3) * 1.4285715);
    float3 bias = k.rimLight * float3(0.1, -0.1, -0.1);
    float3 rimView = s.view + input.mainLightOS.xyz * float3(0, 0.3, 0);
    float bust = saturate(1 - s.flatten);
    float broad = bust * grazingRim(normal, rimView + bias * 2, 3.75);
    broad = max(saturate((broad - 0.1) * 3.3333333), min(broad, 1)) * 0.75;
    float narrow = edge * min(grazingRim(normal, rimView + clamp(bias, -0.1, 0.1), 15) * (bust * 256), 1);
    float facing = dot(s.unitNormal, k.faceLight);
    float rim = saturate(lerp(broad, narrow, saturate(facing))) * mad(saturate((facing + 0.2) * 2.5), 0.5, 0.5);
    float region = max(s.hairAlpha, max(s.nippleMask, max(s.detail.b, shade.creases)));
    float mask = (1 - max(region * _RimMaskIntensity, s.detail.b)) * float(input.frontFacing);
    BodyRim result;
    result.main = saturate(mask * saturate((s.unitNormal.y + 1.5) / 3) * rim * _TestRim);
    float grazingView = 1 - dot(s.artisticNormal, s.view);
    float rimLight = saturate(grazingView * grazingView * grazingView * (bust * 0.3))
                   * saturate(mad(dot(s.pigment, luminance601), 0.7, 0.3));
    result.secondary = saturate(k.visibility * skinKeyColor().r) * bust * mask * rimLight * min(_TestRimSub, _TestRim);
    float3 key = skinKeyColor();
    float3 tint = log2(clamp(key, 0, 3)) * 0.30103 + saturate(key);
    float3 scattered = saturate(tint * mad(s.paintedPigment, 0.95, 0.05));
    float back = saturate(dot(-unitDirection(s.unitNormal + s.key), s.view) * 1.3333334);
    float wrap = k.visibility * saturate((dot(k.rimLight, s.unitNormal) + 1) * 0.25);
    result.transmission = saturate(wrap * (back * (tint * saturate(tintSaturation(scattered, 2))))
                                 * saturate(dot(tint, luminance709) * 2) * _TestSSS);
    return result;
}
