import Materials.Face.Bindings;
import Materials.Face.Material;
import Materials.Face.Makeup;
import Materials.Face.Surface;
import Materials.Skin.Frame;
import Materials.Skin.Lighting;
import Materials.Skin.FluidBindings;
import Materials.Skin.FluidLayer;
import Surface.SurfaceNormals;
import Materials.Skin.SurfaceMath;
import Surface.MaterialColor;

public struct FaceSurface
{
    public TangentFrame basis;
    public FaceMakeup makeup;
    public FaceDetail detail;
    public float3 eyeOffset;
    public float3 view;
    public float3 bumpWorld;
    public float3 normal;
    public float3 pigment;
    public float lineCoverage;
    public float detailShade;
}

float3 wetFaceReflection(StageInput input, TangentFrame basis, FaceDetail detail, float3 view, float sweatHeight)
{
    float sweat = sweatHeight * _AseIntensity;
    float3 sweatNormal = sweatNormalWS(input.positionWS.xyz, basis.normal, sweatHeight, 0.2);
    float3 normal = basis.toWorld(lerp(detail.liquidNormalTS, basis.toTangent(sweatNormal), sweat));
    float coverage = max(detail.liquid, min(sweat, _AseIntensity));
    float wetness = max(_NureIntensity, _AseIntensity);
    return wetSkinReflection(unity_SpecCube0, samplerunity_SpecCube0, specCubeHDR, reflect(-view, normal),
                             input.positionOS.xy, wetness, coverage);
}

public FaceSurface sampleFaceSurface(StageInput input)
{
    FaceSurface s;
    float2 uv = input.uv0Uv1.xy;
    s.basis = TangentFrame(input.normalWS, input.tangentWS);
    s.eyeOffset = _WorldSpaceCameraPos - input.positionWS.xyz;
    s.view = faceViewDirection(input.positionWS.xyz);
    s.makeup = sampleFaceMakeup(input);
    s.detail = sampleFaceDetail(uv);
    FluidLayer fluid = skinFluidMap<LinearFluidFilter>().sampleLayer(uv);
    float3 combined = combineNormalSlopes(s.detail.liquidNormalTS, fluid.normalTS);
    s.bumpWorld = s.basis.toWorld(normalize(combined));
    s.normal = normalize(s.bumpWorld);

    float sweat = sweatHeight(uv, _TimeParameters.x, _SweatNoise);
    float3 reflected = wetFaceReflection(input, s.basis, s.detail, s.view, sweat);
    float3 liquidTint = saturate(lerp(s.makeup.pigment, float3(0.957614, 0.9262637, 0.8728591), s.detail.liquid));
    float3 wet = lerp(s.makeup.pigment, liquidTint, s.detail.liquid);
    wet = mad(max(_AseIntensity * 0.3, _NureIntensity), mad(wet, saturate(mad(-_AseIntensity, sweat, 1)), -wet), wet);
    float3 fluidNormal = s.basis.toWorld(fluid.normalTS);
    float3 viewSpaceEye = mad(unity_MatrixV2.xyz, s.eyeOffset.z, mad(unity_MatrixV0.xyz, s.eyeOffset.x, unity_MatrixV1.xyz * s.eyeOffset.y));
    float3 light = skinKeyDirection();
    light = normalize(light * rsqrt(max(dot(light, light), 1.1754944e-38)));
    s.pigment = skinFluidPigment().apply(saturate(reflected + wet), fluid.paint, max(1 - dot(fluidNormal, light), 0.0001),
        dot(fluidNormal, normalize(viewSpaceEye)));

    float4 lines = _Lip_line_texture.Sample(sampler_Lip_line_texture, mad(input.uv2Uv3.zw, _Lip_line_texture_ST.xy, _Lip_line_texture_ST.zw));
    s.lineCoverage = max(lines.b, s.makeup.spot.b);
    float feature = max(s.detail.mask.g, max(max(lines.r, max(s.makeup.spot.g * _sppower, s.makeup.nose.g)), 0));
    float contrast = clamp(mad(mad(s.detail.mask.b, -_mdGPower, _mdGPower), -0.5, 1), 0.5, 1);
    s.detailShade = max(max(min(feature / contrast, 1) * lerp(_mdGIntensity, 0.5, s.detail.mask.b), lines.r), 0);
    return s;
}

public float faceGloss(StageInput input, FaceSurface s)
{
    float parallax = normalize(s.basis.toTangent(s.eyeOffset)).x;
    float2 uv = float2(mad(parallax, -0.0475, input.uv2Uv3.x), input.uv2Uv3.y);
    uv = mad(uv, mad(_NoseGlossScale, 0.4, 0.8), mad(_NoseGlossScale, -0.2, 0.1));
    uv.y += mad(_NoseGlossScale, 0.12, -0.06);
    float gloss = _Nose_texture.Sample(sampler_Nose_texture, uv).a;
    float edge = saturate((gloss - 0.499) * 1.996008);
    gloss = (_NoseGlossIntensity * _NoseGlossIntensity) * min((edge * edge) * mad(edge, -2, 3), 1);
    return max(gloss * 0.75, max(s.makeup.lipHighlight, s.makeup.cheekHighlight));
}
