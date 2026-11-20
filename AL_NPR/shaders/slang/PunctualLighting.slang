// Forward+ binds 256 entries of each light property at the offsets below.
// A position with w = 0 supplies a direction, while w = 1 supplies a point.
public cbuffer AdditionalLights : register(b1)
{
    public float4 lightPositions[256] : packoffset(c0);
    public float4 lightColors[256] : packoffset(c256);
    public float4 lightAttenuations[256] : packoffset(c512);
    public float4 lightSpotDirections[256] : packoffset(c768);
    public float4 lightLayerMasks[256] : packoffset(c1280);
};

public struct PunctualLight
{
    public float3 direction;
    public float attenuation;
    public float3 color;
}

public PunctualLight getPunctualLight(uint index, float3 positionWS)
{
    float4 position = lightPositions[index];
    float3 toLight = mad(-positionWS, position.w, position.xyz);
    float distanceSquared = max(dot(toLight, toLight), 0.00006103515625);
    float3 direction = toLight * rsqrt(distanceSquared);

    float4 falloff = lightAttenuations[index];
    float radius = distanceSquared * falloff.x;
    float fade = max(mad(-radius, radius, 1), 0);
    float spot = saturate(mad(dot(lightSpotDirections[index].xyz, direction), falloff.z, falloff.w));

    PunctualLight light;
    light.direction = direction;
    light.attenuation = (fade * fade * rcp(distanceSquared)) * (spot * spot);
    light.color = lightColors[index].rgb;
    return light;
}
