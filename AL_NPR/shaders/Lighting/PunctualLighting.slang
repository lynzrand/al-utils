/// Forward+ binds 256 entries of each light property at the offsets below.
/// A position with w = 0 supplies a direction, while w = 1 supplies a point.
public cbuffer AdditionalLights : register(b1)
{
    /// XYZ contains a world-space position for W = 1 or a direction toward a distant light for W = 0.
    public float4 lightPositions[256] : packoffset(c0);
    /// RGB radiance supplied by Unity for each additional light.
    public float4 lightColors[256] : packoffset(c256);
    /// X scales distance squared for the range fade. Z scales and W biases the spot cone's cosine. Y is unused
    /// here.
    public float4 lightAttenuations[256] : packoffset(c512);
    /// XYZ is the per-light world-space cone axis for the dot product with the direction toward the light.
    public float4 lightSpotDirections[256] : packoffset(c768);
    /// X stores the rendering-layer mask as raw uint bits. The caller intersects it with the material's layer.
    public float4 lightLayerMasks[256] : packoffset(c1280);
};

/// Additional light evaluated at the receiver before applying shadow visibility.
public struct PunctualLight
{
    /// World-space vector toward the light, normalized using the lower-bounded squared distance.
    public float3 direction;
    /// Inverse distance squared multiplied by the squared range fade and squared spot-cone fade.
    public float attenuation;
    /// RGB light radiance before distance attenuation, shadowing, and material response.
    public float3 color;
}

/// Resolve a Unity additional-light index into world-space direction, attenuated intensity factor, and source
/// RGB.
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
