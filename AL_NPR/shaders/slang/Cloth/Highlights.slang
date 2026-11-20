struct ClothRim
{
    float amount, mask, verticalFade, logViewGrazing;
    float viewRim;
};

ClothRim clothRim(ClothInput input, ClothFrame frame, ClothKey key, ClothPalette palette, ClothPigment pigment)
{
    ClothRim rim;
    float3 view = frame.view, normal = frame.normal;
    float3 lightOffset = float3(0, input.lightOS.y * 0.3, 0);
    float3 rimView = view + lightOffset + palette.rimDirection * float3(0.2, -0.2, -0.2);
    float wide = grazingRim(normal, rimView, 3.75);
    wide = max(min(wide, 1), saturate((wide - 0.1) * 3.3333333)) * 0.75;
    float3 rimAxis = abs(frame.cameraDelta) - input.normalOS;
    float power = clamp(mad(saturate(rimAxis.y / length(rimAxis)) - 0.25, 4, 1), 1, 3) * 8;
    float3 flatNormal = normalize(normal * float3(1, 0.1, 1));
    float stripe = grazingRim(flatNormal, view, power);
    stripe = saturate(mad(stripe, 32, -0.3) * 1.4285715);
    float grazing = max(palette.viewGrazing, 0.0001);
    rim.logViewGrazing = log2(grazing);
    stripe *= min(exp2(power * rim.logViewGrazing) * 32, 1);
    float3 narrowView = view + clamp(palette.rimDirection * float3(0.1, -0.1, -0.1), -0.1, 0.1) + lightOffset;
    float narrow = min(grazingRim(normal, narrowView, 15) * 256, 1);
    float directFacing = saturate(dot(normal, key.directions.diffuse));
    rim.amount = saturate(lerp(wide, stripe * narrow, directFacing));
    rim.verticalFade = saturate((normal.y + 1.5) / 3);
    rim.mask = 1 - max(max(1 - saturate((pigment.detail.a - 0.1) * 1.1111112), pigment.detail.g) * _RimMaskIntensity, 0);
    rim.amount *= mad(key.bands.y, 0.5, 0.5) * float(input.frontFace) * _TestRim;
    rim.amount = saturate(rim.mask * (rim.verticalFade * rim.amount) * 0.5);
    rim.viewRim = min(grazingRim(normal, view + float3(0, 0.2, 0), 1.2), 1);
    return rim;
}

float3 fluidPigment(ClothFrame frame, ClothKey key, ClothSurface surface, ClothPigment p)
{
    float3 fluid = lerp(surface.fluid.rgb, p.wet, _FluidTransmittance);
    float3 hsv = rgbToHSV(fluid);
    float value = hsv.z;
    hsv.y += _FluidShadowSaturation;
    hsv.z -= 0.3;
    float3 shadowDelta = mad(fluid, hsvToRGB(hsv), -fluid) * _FluidShadowPower;

    float3 fluidNormal = frame.basis.toWorld(surface.fluidNormalTS);
    float edge = max(1 - dot(fluidNormal, normalize(key.direction)), 0.0001);
    float start = mad(_FluidShadowSize, -0.2, 0.2);
    float width = mad(_FluidShadowSize, 0.2, 0.20000002);
    float band = smoothstep(start, 0.5, edge) - smoothstep(0, width, edge - 0.4);
    band = saturate(max(band, (edge - 0.34) * 1.1363636));
    float3 shaded = mad(band, shadowDelta, fluid);
    float3 highlight = mad(_FluidHighlightPower, value + 0.3, fluid);
    float3 color = lerp(shaded, highlight, min(smoothstep(_FluidHighlightSize, 0, edge), 1));
    color = mad(smoothstep(0.6, 1, edge), 0.14, color);
    float cameraFacing = max(1 - dot(fluidNormal, normalize(viewAxes(frame.cameraDelta))), 0.0001);
    color = mad(max(mad(-cameraFacing, 50, 1), 0), highlight, color);
    float scatter = mad(exp2(-max(surface.fluid.a * _FluidColorScatter, 0)), 1 - _FluidMinColorScale, _FluidMinColorScale);
    color = lerp(p.wet, scatter * color, saturate(surface.fluid.a * _FluidScale));
    float3 normal = normalize(frame.basis.toWorld(surface.wetNormalTS));
    float highlightWet = pow(max(dot(key.viewHalf, normal), 0), 512);
    color = mad(highlightWet * key.litColor, p.wetBlend, color);
    color = saturate(color * mad(p.base.a, clamp(dot(color.gb, float2(-0.3, 0.3)), -1, 0), 1));
    return tintSaturation(color, 0.8);
}
