import AmbientProbe;
import Coverage;
import ForwardPlus;
import MaterialNoise;
import PunctualLighting;
#ifndef CLOTH_PREPASS
import PunctualShadows;
#endif
#ifdef CLOTH_NPR
import MapLighting;
import SceneLighting;
#endif

#include "ColorBindings.slang"

struct ClothInput
{
    float4 positionCS : SV_Position;
    float4 positionWS : TEXCOORD0;
    float3 normalWS : TEXCOORD1;
    float4 tangentWS : TEXCOORD2;
    // These slots keep the input registers aligned with the game vertex signature.
    float4 unused3 : TEXCOORD3;
    float4 unused4 : TEXCOORD4;
    float4 uv : TEXCOORD5;
    float4 maskUV : TEXCOORD6;
    float4 positionOS : TEXCOORD7;
    float4 lightOS : TEXCOORD8;
    float3 normalOS : NORMAL0;
    bool frontFace : SV_IsFrontFace;
};

#define CLOTH_COLOR_PASS 1
#include "RegionMasks.slang"
#include "Surface.slang"
#include "Opacity.slang"
#include "LightGather.slang"
#include "LightingFrame.slang"
#include "Pigment.slang"
#include "ColorOpacity.slang"
#include "Palette.slang"
#include "Highlights.slang"
#include "ColorComposition.slang"

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
