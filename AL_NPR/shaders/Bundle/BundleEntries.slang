// The bundle builder binds these TEXCOORD inputs to live registers in each
// Unity keyword variant. Keep register packing here and shading in the modules.
import Lighting.SceneLighting;
import Materials.Hair.HairLighting;
import Lighting.ShadowFiltering;

float BandFacing(float3 normal : TEXCOORD0, float3 light : TEXCOORD1) : SV_Target
{
    return bandFacing(normal, light);
}

float3 PerLightBand(float3 incident : TEXCOORD0) : SV_Target
{
    return perLightBand(incident);
}

float SkinFill(float4 lighting : TEXCOORD0) : SV_Target
{
    return skinFill(lighting.rgb, lighting.a);
}

float FabricFill(float4 lighting : TEXCOORD0) : SV_Target
{
    return fabricFill(lighting.rgb, lighting.a);
}

Texture2D<float4> shadowAtlas : register(t0);
SamplerComparisonState shadowCompare : register(s0);

float FaceShadow(float3 uvz : TEXCOORD0) : SV_Target
{
    return faceVisibility(shadowAtlas, shadowCompare, uvz);
}

float3 FaceBand(float4 light : TEXCOORD0) : SV_Target
{
    return visibleFaceBand(light.rgb, light.a);
}

Texture2D<float4> highlight : register(t1);
SamplerState highlightSampler : register(s3);

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

float HairDiffuseGain(float3 incident : TEXCOORD0) : SV_Target
{
    return rcp(directLightCompression(incident));
}

float3 HairFinish(float4 reflection : TEXCOORD0, float4 tint : TEXCOORD1) : SV_Target
{
    return finishHairReflection(reflection.rgb, reflection.a, tint);
}
