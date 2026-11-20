// The painted stripe follows both the view in tangent space and the projected view in camera space.
float3 samplePaintedStripe(float2 uv, HairSurface s)
{
    float3 tangentView = float3(dot(s.tangent, s.toCamera), dot(s.bitangent, s.toCamera), dot(s.normal, s.toCamera));
    tangentView = safeUnit(tangentView);
    float3 cameraView = safeUnit(viewX.xyz * s.toCamera.x + viewY.xyz * s.toCamera.y + viewZ.xyz * s.toCamera.z);
    cameraView = normalize(cameraView);
    float2 stretch = float2(2.5, 1.5) - 1.2 * _LightLength;
    float2 location = float2(uv.x, mad(uv.y, stretch.x, stretch.y * -0.56));
    location += float2(tangentView.x * _hilightmove2 * -0.01,
                       stretch.x * mad(tangentView.y * _hilightmove, -0.1, _hilightmove3));
    location.y += (dot(s.normal.xy, s.key.xz) * 0.4 - 0.2) * cameraView.y / (cameraView.z + 0.42) * 2.5;
    float3 stripe = paintedHighlight.Sample(paintedHighlightSampler, location).rgb;
#ifdef HAIR_NPR
    stripe *= 0.26;
#endif
    return stripe;
}

float3 wetHair(float3 pigment, HairSurface s, HairInput input, float keyVisibility)
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
    float3 wetNormal = lerp(float3(0, 0, 1), unpackHairNormal(texel, _NureNormalPower), wetness);
    float3 worldNormal = s.toWorld(normalize(wetNormal));
    float4 cube = environmentCube.SampleLevel(environmentCubeSampler, reflect(-s.view, worldNormal), 4.05);
    float decode = pow(max(mad(cubeDecode.w, cube.a - 1, 1), 0), cubeDecode.y) * cubeDecode.x;
    float3 reflection = saturate((cube.rgb * decode) * 0.3);

    float remaining = 1 - wetness * _AseIntensity;
    float strength = max(_AseIntensity * 0.3, 0);
    float3 environment = saturate(lerp(pigment, reflection * pigment, 0.5));
    float3 color = lerp(remaining * pigment, environment, strength);
    float3 keyChroma = mainLightColor.rgb / (maxChannel(mainLightColor.rgb) + 1e-7);
    float3 key = keyVisibility * keyChroma;
    float3 halfVector = normalize(normalize(mainLightDirection.xyz) + s.view);
    float3 normal = normalize(worldNormal);
    float specular = pow(max(dot(halfVector, normal), 0), exp2(strength * 7.5 + 1));
    float3 direct = (strength * specular) * key;
    direct += (max(dot(normal, s.key), 0) * key + 2 * ambientColor.rgb) * pigment * 0.2;
    return adjustSaturation(saturate(color + strength * direct), 0.8);
}

struct HairStripe
{
    float primary, intensity;
    float3 tint, pigment;
};

HairStripe paintStrands(float3 pigment, HairMasks masks, HairSurface s, HairInput input,
                        float keyVisibility, float keyLuma)
{
    float3 stripe = samplePaintedStripe(input.uv1Uv0.xy, s);
    float secondaryGain = min(sqrt(colorSaturation(_Highlight_color02.rgb)) * 0.8 + 0.4, 2);
    float secondaryWeight = secondaryGain * _Highlight_color02.a;
    float3 secondary = saturate(secondaryGain * (_Highlight_color02.a * _Highlight_color02.rgb));
    float secondaryEnergy = dot(_Highlight_color02.rgb, float3(secondaryWeight));

    HairStripe result;
    result.primary = saturate(sumChannels(_Highlight_color01.rgb)) * (clamp(_Highlight_color01.a, 0, 0.9) * stripe.r);
    result.tint = lerp(secondary, _Highlight_color01.rgb, result.primary);
    float secondaryStripe = saturate(secondaryEnergy * (stripe.g * _Highlight_color02.a) * 0.5);
    float silhouette = pow(max(1 - dot(normalize(s.normal), s.view), 0.0001), _Intensity2);
    float facing = saturate(1 + (dot(s.normal.xy, s.key.xz) + 1) * 0.25 - saturate(silhouette * _Intensity1));
    float unmasked = 1 - masks.detail.r;
    float stripeShadow = facing * (stripe.b - unmasked * max(result.primary, secondaryStripe));
    float shadow = min(min(keyVisibility, keyLuma), 0.3) * (secondaryEnergy * (stripeShadow * _Highlight_color02.a));
    pigment = lerp(pigment, _Shadow_color.rgb, saturate(unmasked * shadow));
    result.intensity = facing * (unmasked * max(result.primary, secondaryStripe * _HairHigh2Multiply));
    result.pigment = lerp(pigment, adjustSaturation(pigment, 2) + saturate(result.tint * 3), result.intensity);
    return result;
}

float hairRim(HairSurface s, HairInput input, float3 rimLight, float faceFacing, float fresnel)
{
    float3 localLift = input.mainLightOS.xyz * float3(0, 0.3, 0);
    float3 tiltedView = s.view + localLift + rimLight * float3(0.2, -0.2, -0.2);
    float broad = pow(max(1 - dot(s.shadingNormal, tiltedView), 0.0001), 3.75);
    broad = max(saturate((broad - 0.1) * 3.3333333), min(broad, 1)) * 0.75;

    float3 viewOffset = abs(s.toCamera) - input.normalOS;
    float exponent = clamp((saturate(viewOffset.y / length(viewOffset)) - 0.25) * 4 + 1, 1, 3) * 8;
    float3 flatNormal = normalize(s.shadingNormal * float3(1, 0.1, 1));
    float flat = 32 * pow(max(1 - dot(flatNormal, s.view), 0.0001), exponent);
    float narrow = min(32 * pow(fresnel, exponent), 1) * saturate((flat - 0.3) * 1.4285715);
    float3 edgeView = s.view + clamp(rimLight * float3(0.1, -0.1, -0.1), -0.1, 0.1) + localLift;
    narrow *= min(256 * pow(max(1 - dot(s.shadingNormal, edgeView), 0.0001), 15), 1);
    return lerp(broad, narrow, saturate(faceFacing));
}
