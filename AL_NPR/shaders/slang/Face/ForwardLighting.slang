import ToonPalette;

struct FaceKey
{
    float3 color;
    float3 direction;
    float3 diffuseDirection;
    float3 rampDirection;
    float3 rimDirection;
    PaletteLight palette;
    float visibility;
    float toonVisibility;
    float facing;
    float rampFacing;
    float diffuseWeight;
    float2 wrap;
}

FaceKey faceKey(StageInput input, FaceSurface s)
{
    FaceKey key;
    key.color = skinKeyColor();
    float3 direction = skinKeyDirection();
    key.direction = direction * rsqrt(max(dot(direction, direction), 1.1754944e-38));
    float3 signedLight = input.frontFacing ? normalize(key.direction) : -normalize(key.direction);
    PaletteDirections directions = PaletteDirections(key.color, s.view, signedLight);
    key.diffuseDirection = directions.diffuse;
    key.rampDirection = directions.ramp;
    key.rimDirection = directions.rim;
    key.palette = PaletteLight(key.color);
    key.visibility = skinMainVisibility(input.positionWS.xyz);
    float shadow = saturate((key.visibility - 0.05) * 1.5384616);
    key.toonVisibility = lerp(0.7, min(shadow * shadow * mad(shadow, -2, 3), 1), key.palette.presence);
    key.facing = dot(s.normal, key.diffuseDirection);
    key.rampFacing = dot(key.rampDirection, s.normal);
    key.diffuseWeight = key.toonVisibility * saturate((key.facing - 0.05) * 5);
    key.wrap = saturate((key.rampFacing + float2(0.8, 1)) * float2(0.625, 0.5));
    return key;
}

struct FaceRim
{
    float outer;
    float secondary;
}

FaceRim faceRim(StageInput input, FaceSurface s, FaceKey k)
{
    float3 offset = abs(s.eyeOffset) - input.normalOS;
    float falloff = clamp(mad(saturate(offset.y / length(offset)) - 0.25, 4, 1), 1, 3) * 8;
    float edge = 1 - dot(s.normal, s.view);
    float silhouette = min(pow(max(edge, 0.0001), falloff) * 32, 1);
    float3 horizontal = normalize(s.normal * float3(1, 0.1, 1));
    silhouette *= saturate(mad(grazingRim(horizontal, s.view, falloff), 32, -0.3) * 1.4285715);
    float3 up = input.mainLightOS.xyz * float3(0, 0.3, 0);
    float3 sharpDirection = s.view + clamp(k.rimDirection * float3(0.1, -0.1, -0.1), -0.1, 0.1) + up;
    float3 broadDirection = mad(k.rimDirection, float3(0.2, -0.2, -0.2), up + s.view);
    float detail = 1 - s.detail.secondary.b;
    float broad = grazingRim(s.normal, broadDirection, 3.75);
    float broadMask = max(saturate(mad(detail, broad, -0.1) * 3.3333333), saturate(broad * detail)) * 0.75;
    float sharpMask = saturate(grazingRim(s.normal, sharpDirection, 15) * (256 * detail));
    float rim = saturate(mad(saturate(k.facing), mad(silhouette, sharpMask, -broadMask), broadMask));
    float mask = 1 - max(max(s.detail.mask.g, s.detail.secondary.b) * _RimMaskIntensity, s.detail.mask.b);
    float front = input.frontFacing ? 1 : 0;
    FaceRim result;
    result.outer = saturate(mask * (saturate((s.normal.y + 1.5) / 3) * (front * rim *
        mad(saturate((k.facing + 0.2) * 2.5), 0.5, 0.5) * _TestRim)));
    float grazing = saturate(detail * 0.3 * (edge * edge * edge));
    result.secondary = saturate(k.visibility * k.color.r) * (mask * (front * grazing *
        saturate(mad(dot(s.pigment, luminance601), 0.7, 0.3))) * min(_TestRimSub, _TestRim));
    return result;
}

float3 faceSubsurface(FaceSurface s, FaceKey k)
{
    float3 key = max(k.color, 0);
    float3 transmission = mad(log2(min(key, 3)), 0.30103, min(key, 1));
    float3 bent = mad(s.normal, s.detail.secondary.b + 1, k.direction);
    bent *= rsqrt(max(dot(bent, bent), 1.1754944e-38));
    float back = saturate(dot(-bent, s.view) * 1.3333334);
    float wrap = k.visibility * saturate((dot(k.rimDirection, s.normal) + 1) * 0.25);
    float3 tint = saturate(tintSaturation(saturate(transmission * mad(s.pigment, 0.95, 0.05)), 2));
    return saturate((saturate(dot(transmission, luminance709) * 2) * (wrap * (back * (transmission * tint)))) * _TestSSS);
}

float3 skinShadowPigment(FaceSurface s)
{
    float3 hsv = rgbToHSV(s.makeup.basePigment);
    float brightness = sqrt(hsv.z);
    hsv.y = min(sqrt(hsv.y), 1) * min(brightness * 10, 1);
    hsv.z = min(mad(brightness, 0.5, 0.5), 1);
    float3 tint = lerp(hsvToRGB(hsv), _Shade_color.rgb, _UseShadowColor);
    return saturate(lerp(tint, float3(0.9049558, 0.8495964, 0.6682819), s.detail.liquid));
}

float3 faceMatcap(FaceSurface s, FaceRim rim, float chromaMask, float shadeMask, float3 shadowPigment)
{
    float edge = grazingRim(s.normal, s.view + float3(0, 0.2, 0), 1.5);
    float3 shadow = lerp(_Shadow_color.rgb, dot(_Shadow_color.rgb, luminance601),
                         mad(saturate(edge * (_Shadow_color.a * 0.5)), -0.8, 0.4));
    float shade = saturate(edge * (1 - s.detail.secondary.b) * 0.5) * saturate(mad(_Shadow_color.a, 0.25, 0.75));
    float weight = min(mad(dot(s.pigment, luminance709), -0.5, 1), 1) * saturate(mad(rim.outer - 0.25, -2, 1));
    float3 matcap = lerp(float3(1), lerp(float3(1), saturate(shadow), shade), weight);
    matcap = mad(matcap, _TestMatcapShade, 1 - _TestMatcapShade);
    float grazing = 1 - dot(s.bumpWorld, s.view);
    float square = grazing * grazing;
    float3 normal = lerp(s.bumpWorld, s.normal, s.detail.secondary.b);
    float viewY = mad(unity_MatrixV2.y, normal.z, mad(unity_MatrixV0.y, normal.x, unity_MatrixV1.y * normal.y));
    float tint = saturate(mad(grazing * (square * square), 0.05, (viewY + 1) * 0.15) + 0.3);
    float3 overlay = lerp(_Shadow_color.rgb, float3(1), tint);
    float3 base = s.pigment * matcap;
    float3 detail = select(0.5 < overlay, mad(overlay, 2, base) - 1, mad(overlay - 0.5, 2, base));
    float occlusion = (chromaMask * (saturate(mad(peakChannel(s.pigment), 0.8, 0.2)) * _TestOC)) * 0.3352197;
    float3 occluded = saturate(mad(occlusion, mad(-matcap, s.pigment, detail), base));
    float3 hsv = rgbToHSV(occluded * lerp(float3(1), shadowPigment, shadeMask * _BaseColorMix));
    hsv.y = min(saturationOf(occluded) + 0.1, max(hsv.y, 0));
    return hsvToRGB(hsv);
}
struct FacePalette
{
    float3 color;
    float3 ambient;
    float3 bounce;
    float chromaMask;
}

FacePalette facePalette(FaceSurface s, FaceKey k, FaceRim rim, SkinLights lights, float gloss)
{
    float chromaMask = pigmentContrast(s.pigment);
    float edge = max(1 - dot(s.normal, s.view), 0.0001);
    float shadeMask = max(s.detailShade, min(edge * edge * 0.5, 0.5));
    float shadowPower = saturate(mad(_Shadow_power, 0.4, 0.5));
    float shade = -3 * (lerp(_mdGShadeControle, 1, s.detail.mask.b) * (shadowPower * shadeMask));
    float ramp = max(min(min(shade, 0), (shadowPower * s.detail.mask.b) * -3), -1)
               + k.palette.rampCoordinate(k.rampFacing);
    float localLight = dot(lights.diffuse, luminance709);
    float rampSample = _Lamp.Sample(sampler_Lamp, float2(saturate(ramp + localLight))).b;
    float direct = skinPaletteWeight(saturate(mad(k.diffuseWeight, 1 - s.detail.secondary.g, localLight)), lights);
    float floorWeight = shadowFloor(k.color);
    float3 geometricNormal = normalize(s.basis.normal);
    float geometricBand = skinPaletteWeight(saturate((dot(geometricNormal, k.diffuseDirection) - 0.05) * 5), lights);
    float band = max(floorWeight, k.toonVisibility * geometricBand);
    float3 objectNormal = mad(worldToObject2.xyz, geometricNormal.z,
        mad(worldToObject0.xyz, geometricNormal.x, worldToObject1.xyz * geometricNormal.y));
    float3 worldNormal = mad(objectToWorld2.xyz, objectNormal.z,
        mad(objectToWorld0.xyz, objectNormal.x, objectToWorld1.xyz * objectNormal.y));
    float3 shadeNormal = lerp(s.normal, normalize(worldNormal), s.detail.secondary.b);
    float shadeLight = shadowTintWeight(shadeMask, dot(k.rampDirection, shadeNormal));
    float3 probeFill = saturate(probe.evaluate(s.normal * 0.5));
    float3 shadeColor = skinShadowPigment(s);
    float contour = max(1 - dot(normalize(s.normal + float3(0, -0.25, 0)), s.view), 0.0001);
    float3 contourColor = lerp(shadeColor, _Shadow_color.rgb, min(pow(contour, 1.8), 1) * floorWeight * _Shadow_color.a);
    float3 tint = k.palette.exposeShadow(lerp(shadowProbeTint(probeFill), contourColor, max(band * shadeLight, 0)));
    tint = lerp(tint, _Shade_color.rgb, _UseShadowColor);
    tint = lerp(tint, float3(1), max((1 - saturate(rampSample)) * direct, 1 - shadowPower));

    PaletteFill fill = PaletteFill(k.palette, k.color, probe.evaluate(s.basis.normal), k.rampFacing, direct);
    float3 matcap = faceMatcap(s, rim, chromaMask, shadeMask, shadeColor);
    FacePalette result;
    result.color = mad(tint * fill.tint, matcap, probeFill * fill.ambientWeight);
    result.ambient = probe.evaluate(s.normal);
    result.chromaMask = chromaMask;
    float3 glossLight = saturate(result.ambient + saturate(mad(k.diffuseWeight * k.color, 0.9, 0.1)));
    float glossWeight = max(rim.outer * 0.5, mad(dot(glossLight, luminance709), 0.7, 0.3) * gloss);
    float3 glossTint = mad(max(s.makeup.lipHighlight * _Lip_highlight_color.rgb,
                                s.makeup.cheekHighlight * _Cheek_highlight_color.rgb), 0.7, 0.3);
    float3 highlight = clamp(glossLight * (mad(saturationOf(glossTint), 2.2, 0.8) * glossTint), 0, 99);
    result.color = lerp(saturate(result.color), tintSaturation(highlight + saturate(result.color), 1.5),
                        saturate(mad(glossWeight, 3, chromaMask * rim.secondary)));
    float3 bounce = skinBounce(lights);
    result.bounce = mad(mad(max(1 - s.detailShade, 0), 0.25, 0.75) * bounce,
        mad(saturationOf(bounce), 0.75, 0.25), min(k.palette.logBoost, 1) * 0.1 * (k.diffuseWeight * k.wrap.y));
    return result;
}
