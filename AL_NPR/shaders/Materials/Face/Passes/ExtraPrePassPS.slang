import Surface.Coverage;
import Materials.Face.Bindings;
import Materials.Face.Material;
import Materials.Face.Makeup;
import Materials.Face.Surface;
import Materials.Skin.FluidLayer;
import Materials.Skin.FluidBindings;
import Materials.Skin.Frame;
import Surface.SurfaceNormals;
import Surface.MaterialColor;

[shader("fragment")]
float4 main(StageInput input) : SV_Target0
{
    float2 uv = input.uv0Uv1.xy;
    FaceDetail detail = sampleFaceDetail(uv);
    float threshold = ditherThreshold(input.positionCS.xy, _ScaledScreenParams.xy, _ScaleBiasRt.xy, _ProjectionParams.x);
    float coverage = passesDither(_Dither, threshold) && (1 - detail.mask.r) * _Line_width >= 0.05 ? 1 : 0;
    clipCoverage(coverage, 0.5, _AlphaToMaskAvailable != 0);

    TangentFrame basis = TangentFrame(input.normalWS, input.tangentWS);
    float3 fluidNormal = skinFluidMap<LinearFluidFilter>().sampleLayer(uv).normalTS;
    float3 liquidNormal = detail.liquidNormalTS;
    float3 combined = combineNormalSlopes(liquidNormal, fluidNormal);
    float3 normal = normalize(basis.toWorld(normalize(combined)));
    float3 probeColor = tintSaturation(probe.evaluate(normal), 2);
    float3 lightColor = saturate(max(probeColor, mad(_MainLightColor.rgb, 0.7, 0.3)));
    lightColor *= input.frontFacing ? 1 : 0.75;
    float3 light = _MainLightPosition.xyz * rsqrt(max(dot(_MainLightPosition.xyz, _MainLightPosition.xyz), 1.1754944e-38));
    float facing = saturate((dot(basis.normal, light) - 0.3) * 1.4285715);
    float3 highlight = saturate(facing * (lightColor * lightData.z));
    float3 line = faceLineTint(faceViewDirection(input.positionWS.xyz), basis.normal, detail.secondary.b,
                               sampleFaceMakeup(input).pigment);
    float3 color = mad(highlight, 1 - saturate(detail.mask.r * 3.3333333), line);
    return float4(lerp(color, unity_FogColor.rgb, saturate(unity_FogParams.x)),
                  _AlphaToMaskAvailable != 0 ? coverage : 1);
}
