import Materials.Hair.Bindings;
import Materials.Hair.Surface;
import Materials.Hair.Palette;
import Surface.MaterialColor;
import Surface.SurfaceNormals;
import Lighting.Reflectance;

// The painted stripe follows both the view in tangent space and the projected view in camera space.
float3 samplePaintedStripe(float2 uv, HairSurface s)
{
    float3 tangentView = float3(dot(s.basis.tangent, s.toCamera), dot(s.basis.bitangent, s.toCamera), dot(s.basis.normal, s.toCamera));
    tangentView = safeUnit(tangentView);
    float3 cameraView = safeUnit(viewX.xyz * s.toCamera.x + viewY.xyz * s.toCamera.y + viewZ.xyz * s.toCamera.z);
    cameraView = normalize(cameraView);
    float2 stretch = float2(2.5, 1.5) - 1.2 * _LightLength;
    float2 location = float2(uv.x, mad(uv.y, stretch.x, stretch.y * -0.56));
    location += float2(tangentView.x * _hilightmove2 * -0.01,
                       stretch.x * mad(tangentView.y * _hilightmove, -0.1, _hilightmove3));
    location.y += (dot(s.basis.normal.xy, s.key.xz) * 0.4 - 0.2) * cameraView.y / (cameraView.z + 0.42) * 2.5;
    return paintedHighlight.Sample(paintedHighlightSampler, location).rgb;
}

public float3 wetHair(float3 pigment, HairSurface s, HairInput input, float keyVisibility)
{
    float2 uv = input.uv1Uv0.zw;
    float2 regions = saturate((input.positionOS.zy + float2(0.8, 1)) * float2(1.8181818, 1.1428572) - 1);
    float amount = wetMask.Sample(wetMaskSampler, materialUV(uv, _Sampler302397_g100057_ST)).r;
    // The four material sliders cap the contributions from the front/back and top/bottom regions.
    float frontTop = min(min(regions.x, regions.y), amount * _nureftop);
    float frontBottom = min(max(regions.x - regions.y, 0), amount * _nurefbot);
    float backTop = min(max(regions.y - regions.x, 0), amount * _nurebtop);
    float backBottom = min(1 - max(regions.x, regions.y), amount * _nurebbot);
    float wetness = saturate(frontTop + frontBottom + backTop + backBottom);

    float4 texel = wetNormalMap.Sample(wetNormalMapSampler, materialUV(uv, _Sampler345397_g100057_ST));
    float3 wetNormal = lerp(float3(0, 0, 1), unpackScaledNormal(texel, _NureNormalPower), wetness);
    float3 worldNormal = s.basis.toWorld(normalize(wetNormal));
    float4 cube = environmentCube.SampleLevel(environmentCubeSampler, reflect(-s.view, worldNormal), 4.05);
    float3 reflection = saturate(decodeProbe(cube, cubeDecode) * 0.3);

    float remaining = 1 - wetness * _AseIntensity;
    float strength = max(_AseIntensity * 0.3, 0);
    float3 environment = saturate(lerp(pigment, reflection * pigment, 0.5));
    float3 color = lerp(remaining * pigment, environment, strength);
    float3 keyChroma = mainLightColor.rgb / (peakChannel(mainLightColor.rgb) + 1e-7);
    float3 key = keyVisibility * keyChroma;
    float3 halfVector = normalize(normalize(mainLightDirection.xyz) + s.view);
    float3 normal = normalize(worldNormal);
    float specular = wetSpecular(normal, halfVector, strength);
    float3 direct = (strength * specular) * key;
    direct += (max(dot(normal, s.key), 0) * key + 2 * ambientColor.rgb) * pigment * 0.2;
    return tintSaturation(saturate(color + strength * direct), 0.8);
}

public struct HairStripe
{
    public float primary, intensity;
    public float3 tint, pigment;
};

public HairStripe paintStrands(float3 pigment, HairMasks masks, HairSurface s, HairInput input,
                        float keyVisibility, float keyLuma, float stripeGain)
{
    float3 stripe = stripeGain * samplePaintedStripe(input.uv1Uv0.xy, s);
    float secondaryGain = min(sqrt(saturationOf(_Highlight_color02.rgb)) * 0.8 + 0.4, 2);
    float secondaryWeight = secondaryGain * _Highlight_color02.a;
    float3 secondary = saturate(secondaryGain * (_Highlight_color02.a * _Highlight_color02.rgb));
    float secondaryEnergy = dot(_Highlight_color02.rgb, float3(secondaryWeight));

    HairStripe result;
    result.primary = saturate(sumChannels(_Highlight_color01.rgb)) * (clamp(_Highlight_color01.a, 0, 0.9) * stripe.r);
    result.tint = lerp(secondary, _Highlight_color01.rgb, result.primary);
    float secondaryStripe = saturate(secondaryEnergy * (stripe.g * _Highlight_color02.a) * 0.5);
    float silhouette = grazingRim(normalize(s.basis.normal), s.view, _Intensity2);
    float facing = saturate(1 + (dot(s.basis.normal.xy, s.key.xz) + 1) * 0.25 - saturate(silhouette * _Intensity1));
    float unmasked = 1 - masks.detail.r;
    float stripeShadow = facing * (stripe.b - unmasked * max(result.primary, secondaryStripe));
    float shadow = min(min(keyVisibility, keyLuma), 0.3) * (secondaryEnergy * (stripeShadow * _Highlight_color02.a));
    pigment = lerp(pigment, _Shadow_color.rgb, saturate(unmasked * shadow));
    result.intensity = facing * (unmasked * max(result.primary, secondaryStripe * _HairHigh2Multiply));
    result.pigment = lerp(pigment, tintSaturation(pigment, 2) + saturate(result.tint * 3), result.intensity);
    return result;
}

public float hairRim(HairSurface s, HairInput input, float3 rimLight, float faceFacing, float fresnel)
{
    float3 localLift = input.mainLightOS.xyz * float3(0, 0.3, 0);
    float3 tiltedView = s.view + localLift + rimLight * float3(0.2, -0.2, -0.2);
    float broad = grazingRim(s.shadingNormal, tiltedView, 3.75);
    broad = max(saturate((broad - 0.1) * 3.3333333), min(broad, 1)) * 0.75;

    float3 viewOffset = abs(s.toCamera) - input.normalOS;
    float exponent = clamp((saturate(viewOffset.y / length(viewOffset)) - 0.25) * 4 + 1, 1, 3) * 8;
    float3 flatNormal = normalize(s.shadingNormal * float3(1, 0.1, 1));
    float flat = 32 * grazingRim(flatNormal, s.view, exponent);
    float narrow = min(32 * pow(fresnel, exponent), 1) * saturate((flat - 0.3) * 1.4285715);
    float3 edgeView = s.view + clamp(rimLight * float3(0.1, -0.1, -0.1), -0.1, 0.1) + localLift;
    narrow *= min(256 * grazingRim(s.shadingNormal, edgeView, 15), 1);
    return lerp(broad, narrow, saturate(faceFacing));
}
