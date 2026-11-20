float colorOpacity(float2 positionCS, float4 uv, ClothPigment pigment, float wetness)
{
    float detail = pigment.detail.b;
    float fade = max(mad(distance(_WorldSpaceCameraPos.xyz, objectOrigin.xyz), -0.09090909, 1), 0);
    Fabric fabric = { pigment.base.rgb, pigment.sheer };
    float opacity = garmentOpacity(fabric, pigment.base.a, uv.xy, detail, fade, wetness);
    float threshold = ditherThreshold(positionCS, _ScaledScreenParams.xy, _ScaleBiasRt.xy, _ProjectionParams.x);
#ifdef CLOTH_PREPASS
    opacity = maskedClothOpacity(opacity, uv, threshold, false);
    opacity = (opacity * _alpha2) * ceil((1 - detail) * (_LineWidthS * _Line_width));
#else
    opacity = maskedClothOpacity(opacity, uv, threshold, true);
#endif
    float cutoff = clothCutoff(detail);
    clipCoverage(opacity, cutoff, mipAndAlpha.z != 0);
    return Fabric.targetAlpha(opacity, mipAndAlpha.z != 0);
}
