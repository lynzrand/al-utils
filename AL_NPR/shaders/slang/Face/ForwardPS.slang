import Coverage;
import Face.Bindings;
import Face.Material;
import Face.Surface;
import Face.ForwardLighting;
import Face.ForwardSurface;
import Skin.Frame;
import Skin.Lighting;

[shader("fragment")]
float4 main(StageInput input) : SV_Target0
{
    float threshold = ditherThreshold(input.positionCS.xy, _ScaledScreenParams.xy, _ScaleBiasRt.xy, _ProjectionParams.x);
    float opacity = passesDither(_Dither, threshold) ? 1 : 0;
    clipCoverage(opacity, 0.5, _AlphaToMaskAvailable != 0);

    FaceSurface surface = sampleFaceSurface(input);
    FaceKey key = faceKey(input, surface);
    SkinLights lights = evaluateSkinLights(input, surface.normal, surface.normal);
    FaceRim rim = faceRim(input, surface, key);
    float gloss = faceGloss(input, surface);
    FacePalette palette = facePalette(surface, key, rim, lights, gloss);
    float3 lit = mad(rim.secondary, palette.chromaMask, palette.color) + faceSubsurface(surface, key);
    float3 bounded = clamp(lit * 0.98, 0, 0.98);
    float3 color = mad(saturate(mad(surface.pigment, 7, 0.3)), palette.bounce,
                       mad(max(gloss, rim.outer), mad(lit, 0.98, -bounded), bounded));
    color = applySkinFill(color, surface.pigment, palette.ambient, lights);
    color = lerp(color, _Nose_line_color.rgb, surface.makeup.nose.b * _Nose_line_color.a);
    float3 line = faceLineTint(surface.view, surface.basis.normal, surface.detail.secondary.b, surface.makeup.pigment);
    return float4(lerp(color, line, surface.lineCoverage), _AlphaToMaskAvailable != 0 ? opacity : 1);
}
