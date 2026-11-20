// The bundle builder binds these TEXCOORD inputs to live registers in each
// Unity keyword variant. Keep register packing here and shading in the modules.
import Lighting.SceneLighting;
import Materials.Hair.HairLighting;
import Lighting.ShadowFiltering;

/// Read world-space unit normal from TEXCOORD0 and direction toward the light from TEXCOORD1. Output its
/// scalar band cosine.
float BandFacing(float3 normal : TEXCOORD0, float3 light : TEXCOORD1) : SV_Target
{
    return bandFacing(normal, light);
}

/// Convert attenuation- and facing-weighted RGB in TEXCOORD0 to a single light's RGB toon-band contribution.
float3 PerLightBand(float3 incident : TEXCOORD0) : SV_Target
{
    return perLightBand(incident);
}

/// TEXCOORD0 packs evaluated ambient SH RGB and scalar direct-band weight in A. Output the skin fill
/// multiplier.
float SkinFill(float4 lighting : TEXCOORD0) : SV_Target
{
    return skinFill(lighting.rgb, lighting.a);
}

/// TEXCOORD0 packs evaluated ambient SH RGB and scalar direct-band weight in A. Output the cloth fill
/// multiplier.
float FabricFill(float4 lighting : TEXCOORD0) : SV_Target
{
    return fabricFill(lighting.rgb, lighting.a);
}

/// Shadow depth atlas placeholder remapped by the bundle builder to the variant's bound atlas.
Texture2D<float4> shadowAtlas : register(t0);
/// Comparison sampler paired with the original shadow atlas.
SamplerComparisonState shadowCompare : register(s0);

/// TEXCOORD0 holds shadow atlas UV in XY and receiver depth in Z. Output tent-filtered visibility.
float FaceShadow(float3 uvz : TEXCOORD0) : SV_Target
{
    return faceVisibility(shadowAtlas, shadowCompare, uvz);
}

/// TEXCOORD0 packs RGB incident light for banding and shadow visibility in A. Output the visible RGB band.
float3 FaceBand(float4 light : TEXCOORD0) : SV_Target
{
    return visibleFaceBand(light.rgb, light.a);
}

/// Painted strand texture. The release highlight entry samples its red channel.
Texture2D<float4> highlight : register(t1);
/// Sampler paired with the painted strand texture for the explicit-gradient lookup.
SamplerState highlightSampler : register(s3);

/// TEXCOORD0–3 carry world-space normal, tangent, light, and view. The painted variant reads U from
/// TEXCOORD4.x and UV gradients from TEXCOORD5/6. Output scalar highlight strength.
float HairReflection(float3 normal : TEXCOORD0, float3 tangent : TEXCOORD1,
                     float3 light : TEXCOORD2, float3 view : TEXCOORD3,
                     float2 uv : TEXCOORD4, float2 dx : TEXCOORD5, float2 dy : TEXCOORD6) : SV_Target
{
#if defined(HAIR_PAINTED)
    return paintedReflection(highlight, highlightSampler, normal, tangent, light, view, uv.x, dx, dy);
#elif defined(HAIR_RIBBON)
    return ribbonReflection(normal, tangent, light, view);
#else
    return glossReflection(normal, light, view);
#endif
}

/// Return the reciprocal compression divisor for incident RGB in TEXCOORD0.
float HairDiffuseGain(float3 incident : TEXCOORD0) : SV_Target
{
    return rcp(directLightCompression(incident));
}

/// TEXCOORD0 packs accumulated reflection RGB and detail mask A. TEXCOORD1 holds highlight RGB and strength A.
/// Output the final reflection RGB.
float3 HairFinish(float4 reflection : TEXCOORD0, float4 tint : TEXCOORD1) : SV_Target
{
    return finishHairReflection(reflection.rgb, reflection.a, tint);
}
