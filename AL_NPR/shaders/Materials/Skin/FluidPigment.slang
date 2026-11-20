import Surface.MaterialColor;

/// Artist controls for the shadow tint, highlight and transmission of painted fluid.
public struct FluidPigment
{
    /// Blend from the fluid paint RGB at zero to the underlying skin RGB at one.
    public float transmittance;
    /// Adds brightness to the fluid highlight in proportion to pigment value.
    public float highlightPower;
    /// Saturation added to the HSV tint of the fluid's shaded band.
    public float shadowSaturation;
    /// Adjusts the start and end of the fluid's facing-dependent shadow band.
    public float shadowSize;
    /// Multiplier for the fluid's colored shadow relative to its transmitted pigment.
    public float shadowPower;
    /// Threshold in light-facing space that controls the width of the fluid highlight.
    public float highlightSize;
    /// Coefficient multiplying paint alpha in the exponential attenuation of the fluid color.
    public float colorScatter;
    /// Lower limit on color throughput as scattering increases with paint alpha.
    public float minColorScale;
    /// Scales paint alpha before blending the shaded fluid onto the underlying skin.
    public float scale;

    /// The painted fluid layer carries a colored shadow, a bright grazing edge
    /// and an independently sized highlight. Its alpha controls both scattering
    /// within the layer and how much of the underlying skin shows through.
    ///
    /// Shades paint RGBA over substrate RGB using a light-facing falloff and the view/normal dot product.
    public float3 apply(float3 substrate, float4 paint, float facingAway, float viewFacing)
    {
        float3 transmitted = lerp(paint.rgb, substrate, transmittance);
        float3 hsv = rgbToHSV(transmitted);
        float3 highlight = mad(highlightPower, hsv.z + 0.3, transmitted);
        float3 shadowTint = hsvToRGB(float3(hsv.x, hsv.y + shadowSaturation, hsv.z - 0.3));
        float shadowStart = mad(shadowSize, -0.2, 0.2);
        float nearEdge = smoothstep(shadowStart, 0.5, facingAway);
        float farEdge = smoothstep(0.4, 0.4 + mad(shadowSize, 0.2, 0.20000002), facingAway);
        float shadow = saturate(max(nearEdge - farEdge, (facingAway - 0.34) * 1.1363636));
        float3 color = mad(shadow, mad(transmitted, shadowTint, -transmitted) * shadowPower, transmitted);
        float highlightEdge = saturate((facingAway - highlightSize) * (1 / -highlightSize));
        color = lerp(color, highlight, min(highlightEdge * highlightEdge * mad(highlightEdge, -2, 3), 1));
        float fresnel = smoothstep(0.6, 1, facingAway);
        color = mad(max(mad(-max(1 - viewFacing, 0.0001), 50, 1), 0), highlight, mad(fresnel, 0.14, color));
        float attenuation = mad(exp2(-max(paint.a * colorScatter, 0)), 1 - minColorScale, minColorScale);
        return tintSaturation(saturate(mad(saturate(paint.a * scale), mad(attenuation, color, -substrate), substrate)), 0.8);
    }
}
