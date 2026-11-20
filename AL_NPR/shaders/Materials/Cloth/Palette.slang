import Materials.Cloth.Bindings;
import Materials.Cloth.LightGather;
import Materials.Cloth.LightingFrame;
import Materials.Cloth.Pigment;
import Surface.MaterialColor;
import Lighting.ToonPalette;

/// Material colors and angular blend weights shared by the base, rim, and additive lighting stages.
public struct ClothPalette
{
    /// Pigment-derived overlay tint with the wet layer's warm shift.
    public float3 tint;
    /// Exposed shadow RGB after the authored shadow color and lamp ramp.
    public float3 shadow;
    /// Palette fill tint from the key and per-draw ambient probe.
    public float3 ambient;
    /// Wet pigment tint modulated by ambient light for the rim blend.
    public float3 rimLight;
    /// Strength of the palette tint applied directly to the shaded base pigment.
    public float baseMix;
    /// Strength of the additive ambient probe fill under the material shadow.
    public float ambientWeight;
    /// Lamp ramp blend between soft and hard overlays, floored to one half.
    public float ramp;
    /// Signed cosine between the mapped normal and the palette ramp direction.
    public float lightFacing;
    /// One minus the cosine between the mapped normal and view direction.
    public float viewGrazing;
    /// Fresnel and view-space normal weight that fades the pigment overlay toward white.
    public float highlight;
    /// World-space palette direction used by the cloth rim and transmission.
    public float3 rimDirection;
    /// Per-channel key light boost for the additive lighting stage.
    public float3 hdrBoost;
    /// Adjusted detail green controlling the shadow tint and additional-light weight.
    public float specMask;
};

/// Combines pigment, key light, ambient probe, and the authored lamp ramp into cloth shading weights.
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
