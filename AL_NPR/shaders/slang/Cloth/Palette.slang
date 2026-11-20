import Cloth.Bindings;
import Cloth.LightGather;
import Cloth.LightingFrame;
import Cloth.Pigment;
import MaterialColor;
import ToonPalette;

public struct ClothPalette
{
    public float3 tint, shadow, ambient, rimLight;
    public float baseMix, ambientWeight, ramp, lightFacing, viewGrazing, highlight;
    public float3 rimDirection, hdrBoost;
    public float specMask;
};

public ClothPalette clothPalette(ClothFrame frame, ClothKey key, ClothPigment p, ClothLights lights)
{
    ClothPalette palette;
    float facingView = dot(frame.normal, frame.view);
    palette.viewGrazing = 1 - facingView;
    palette.lightFacing = dot(key.directions.ramp, frame.normal);
    palette.rimDirection = key.directions.rim;
    palette.hdrBoost = min(key.palette.logBoost, 1);
    float3 probeHalf = saturate(probe.evaluate(0.5 * frame.normal));
    float3 ambientTint = shadowProbeTint(probeHalf);

    float peak = peakChannel(p.wetTint);
    float dyeWeight = max(min(sqrt(saturationOf(p.wetTint)), 1) * saturate(peak * 10), 1 - peak);
    palette.tint = lerp(float3(0.4508419, 0.60609, 1),
                        saturate(tintSaturation(saturate(p.wetTint), 2)), dyeWeight);
    palette.tint = saturate(lerp(palette.tint, float3(0.9049558, 0.8495964, 0.6682819), p.wetBlend));

    palette.specMask = max(saturate(p.detail.g / clamp(mad(_mdGPower, -0.5, 1), 0.5, 1)) * _mdGIntensity, 0);
    float edge = max(palette.viewGrazing, 0.0001);
    float shadowDetail = max(palette.specMask, min(edge * edge * 0.5, 0.5));
    palette.baseMix = shadowDetail * _BaseColorMix;
#ifdef CLOTH_NPR
    float vertexFacing = lights.band;
#else
    float vertexFacing = saturate((dot(normalize(frame.basis.normal), key.directions.diffuse) - 0.05) * 5);
#endif
    float mixWeight = shadowTintWeight(shadowDetail, palette.lightFacing);
    mixWeight *= max(key.shade * vertexFacing, shadowFloor(key.color));
    palette.shadow = key.palette.exposeShadow(lerp(ambientTint, palette.tint, max(mixWeight, 0)));
    palette.shadow = lerp(palette.shadow, _Shade_color.rgb, _UseShadowColor);

    float shadowPower = saturate(mad(_Shadow_power, 0.4, 0.5));
    float additional = dot(lights.diffuse, luminance709);
    float keyShade = saturate(mad(key.shade, key.bands.x, additional));
    float shift = clamp(((shadowDetail * shadowPower) * _mdGShadeControle) * -3, -1, 0);
    float rampUV = saturate(additional + (shift + key.palette.rampCoordinate(palette.lightFacing)));
    palette.ramp = keyShade * (1 - saturate(_Lamp.Sample(sampler_Lamp, rampUV.xx).b));
    palette.shadow = lerp(palette.shadow, 1, max(palette.ramp, 1 - shadowPower));
    palette.ramp = max(palette.ramp, 0.5);

    PaletteFill fill = PaletteFill(key.palette, key.color, probe.evaluate(frame.basis.normal), palette.lightFacing, keyShade);
    palette.ambient = fill.tint;
    palette.ambientWeight = fill.ambientWeight;

    float3 rimTint = lerp(dot(p.wet, luminance601), p.wet, 1.5);
    rimTint = mad(rimTint, 0.7, 0.3);
    palette.rimLight = clamp((mad(saturationOf(rimTint), 2.2, 0.8) * rimTint) * key.ambient, 0, 99);
    float fresnel = 1 - dot(frame.normalBeforeNormalize, frame.view);
    float f2 = fresnel * fresnel;
    palette.highlight = saturate(mad(fresnel * (f2 * f2), 0.05,
                       (viewAxes(frame.normalBeforeNormalize).y + 1) * 0.15) + 0.3);
    return palette;
}
