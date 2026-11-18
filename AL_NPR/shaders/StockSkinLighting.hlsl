#ifndef AL_STOCK_SKIN_LIGHTING_INCLUDED
#define AL_STOCK_SKIN_LIGHTING_INCLUDED

// Reconstructed primitives from shipped AL/skin_body Forward+ blob 116 and
// AL/skin_head blob 117. This is an analysis include, not a complete material
// replacement. It omits texture composition, cluster traversal, shadow filtering,
// and final palette composition. Instruction numbers refer to the numbered
// body disassembly in artifacts/bench/rd-map-stock-warm-shaders/18223-ps.txt.
// Register names below are mapped by operations and Unity buffer layout.

// Body 538-548. Packed constant/linear terms followed by quadratic terms.
// The caller chooses the shading normal; AL also evaluates this with modified
// and scaled normals in other parts of its custom lighting expression.
float3 ALStockAmbient(float3 n, float4 sh[7])
{
    float4 linearTerms = float4(n, 1.0);
    float4 quadratic = n.yzzx * n.xyzz;
    float3 result = float3(dot(sh[0], linearTerms), dot(sh[1], linearTerms), dot(sh[2], linearTerms));
    result += float3(dot(sh[3], quadratic), dot(sh[4], quadratic), dot(sh[5], quadratic));
    return result + sh[6].rgb * (n.x * n.x - n.y * n.y);
}

// Body 914-921 and corresponding head sample/decode sequence.
float3 ALStockDecodeReflection(float4 encoded, float4 decode)
{
    float alpha = max(0.0, decode.w * (encoded.a - 1.0) + 1.0);
    return encoded.rgb * (decode.x * pow(alpha, decode.y));
}

// Body 910-925. The upstream gloss mask is material-specific and is not
// reconstructed here. The shader weights the reflection before desaturating it.
float ALStockReflectionMip(float perceptualRoughness)
{
    return perceptualRoughness * (1.7 - 0.7 * perceptualRoughness) * 6.0;
}

float3 ALStockReflectionColor(float3 decoded, float materialWeight)
{
    float3 weighted = decoded * materialWeight;
    float luminance = dot(weighted, float3(0.299, 0.587, 0.114));
    return lerp(weighted, luminance.xxx, 0.75);
}

// A common RGB scale preserves the tint of the light and compresses only
// the bright end.
float3 ALSkinExtraLightShoulder(float3 lightSum, float knee, float strength)
{
    float peak = max(lightSum.r, max(lightSum.g, lightSum.b));
    return lightSum / (1.0 + strength * max(peak - knee, 0.0));
}

// Bound each light before applying shadow, then bound the late mixed sum.
// These describe the runtime bundle's edits to the otherwise stock program.
float3 ALSkinBoundedLight(float3 color, float attenuation, float shadow)
{
    return ALSkinExtraLightShoulder(color * attenuation, 0.10, 7.0) * shadow;
}

float4 ALSkinNeutralKey(float4 key)
{
    float luminance = dot(key.rgb, float3(0.212673, 0.715152, 0.072175));
    return float4(luminance.xxx, key.a);
}

// Body 1352, 1660, 2433, 2715, 2949, 3232. cb4[10].x and the
// light-mask slot cb1[index + 1280].x hold uint bits in float registers.
// All six gates must agree if editing bytecode. Lights removed by engine
// culling or absent from the Forward+ cluster cannot be recovered at this gate.
bool ALStockLightMatches(float packedRendererMask, float packedLightMask)
{
    return (asuint(packedRendererMask) & asuint(packedLightMask)) != 0;
}

// Body 1350-1357 and 1658-1665. shadowBypass is r25.w in this variant;
// its original material/global semantic has not yet been resolved.
float3 ALStockAdditionalDiffuse(float3 accumulated, float3 normal, float3 lightDirection,
    float3 lightColor, float distanceAndSpotAttenuation, float filteredShadow,
    float shadowBypass, bool layerMatches)
{
    float shadow = filteredShadow + shadowBypass * (1.0 - filteredShadow);
    float3 contribution = lightColor * (distanceAndSpotAttenuation * shadow);
    contribution *= saturate(dot(normal, lightDirection));
    return layerMatches ? accumulated + contribution : accumulated;
}

// Body 3230-3238. A second response evaluates a wrapped dot product instead
// of Lambert's saturated dot product. Keep the normal passed by the original
// expression; its sign and shaping belong to the upstream material logic.
float3 ALStockAdditionalWrapped(float3 accumulated, float3 normal, float3 lightDirection,
    float3 lightColor, float distanceAndSpotAttenuation, float filteredShadow,
    float shadowBypass, bool layerMatches)
{
    float shadow = filteredShadow + shadowBypass * (1.0 - filteredShadow);
    float response = dot(normal, lightDirection) * 0.5 + 0.5;
    float3 contribution = lightColor * (distanceAndSpotAttenuation * shadow) * response;
    return layerMatches ? accumulated + contribution : accumulated;
}

// Body 748-761. This primitive retains the observed brightness-dependent
// view/light blend and narrow band. facingLightDirection is the normalized
// key direction with the front/back-face sign already applied by 744-747.
// The blend is deliberately not normalized again in the shipped instructions.
float ALStockKeyBand(float3 shadingNormal, float3 viewDirection,
    float3 facingLightDirection, float3 keyColor)
{
    float luminance = dot(keyColor, float3(0.212673, 0.715152, 0.072175));
    float level = saturate(luminance);
    float brightnessResponse = saturate(1.0 - 0.1 * (max(log2(luminance), level) - 1.0));
    float blend = min(2.0 * level, 1.0) * brightnessResponse;
    float3 direction = lerp(viewDirection, facingLightDirection, blend);
    return saturate((dot(shadingNormal, direction) - 0.05) * 5.0);
}

#endif
