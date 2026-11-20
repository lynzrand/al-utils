import Surface.MaterialColor;

public struct FluidPigment
{
    public float transmittance;
    public float highlightPower;
    public float shadowSaturation;
    public float shadowSize;
    public float shadowPower;
    public float highlightSize;
    public float colorScatter;
    public float minColorScale;
    public float scale;

    // The painted fluid layer carries a colored shadow, a bright grazing edge
    // and an independently sized highlight. Its alpha controls both scattering
    // within the layer and how much of the underlying skin shows through.
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
