import Materials.Cloth.Bindings;
import Materials.Cloth.ColorComposition;
import Materials.Cloth.ColorOpacity;
import Materials.Cloth.Highlights;
import Materials.Cloth.LightGather;
import Materials.Cloth.LightingFrame;
import Materials.Cloth.Palette;
import Materials.Cloth.Pigment;
import Materials.Cloth.Surface;
import Surface.MaterialColor;

[shader("fragment")]
float4 main(ClothInput input) : SV_Target0
{
    ClothSurface surface = sampleClothSurface(input.uv.xy);
    ClothFrame frame = clothFrame(input, surface.normalTS);
    float2 screenUV = input.positionCS.xy * (1 / _ScaledScreenParams.xy);
    screenUV.y = 1 - mad(screenUV.y, _ScaleBiasRt.x, _ScaleBiasRt.y);
    ClothLights lights = gatherClothLights(frame.positionWS, frame.normal, screenUV);
    ClothKey key = clothKey(frame, lights, input.frontFace);
    ClothPigment pigment = clothPigment(input, frame, surface, key);
    ClothPalette palette = clothPalette(frame, key, pigment, lights);
    ClothRim rim = clothRim(input, frame, key, palette, pigment);
    float3 fluid = fluidPigment(frame, key, surface, pigment);
    float contrast;
    float3 base = shadeClothPigment(frame, key, palette, rim, fluid, contrast);
    float3 color = addClothHighlights(base, contrast, fluid, dot(pigment.specular, luminance709),
                                     frame, key, palette, rim, input.frontFace);
    color = addClothLights(color, fluid, frame, key, palette, lights);
    color = clothLineColor(color, pigment, key, lights, frame, input.frontFace);
    float alpha = colorOpacity(input.positionCS.xy, float4(input.uv.xy, input.maskUV.xy), pigment, surface.wetness);
    return float4(color, alpha);
}
