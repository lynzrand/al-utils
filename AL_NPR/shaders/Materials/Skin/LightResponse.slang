import Lighting.PunctualLighting;
import Lighting.Reflectance;
import Lighting.SceneLighting;

// Accumulate each visible light, finish the sum, then let the face or body
// use that result for its artist ramp, colored bounce and ambient fill.
public interface ISkinLightResponse
{
    [mutating] void addPunctual(PunctualLight light, float visibility, float3 normal, float3 bandNormal);
    [mutating] void finishAccumulation();
    property diffuse : float3 { get; }
    float paletteWeight(float surfaceWeight);
    float3 bounce();
    float3 applyFill(float3 color, float3 pigment, float3 ambient);
}

public struct StockSkinResponse<let collectIncident : bool> : ISkinLightResponse
{
    float3 surfaceDiffuse;
    float3 bandDiffuse;
    float3 wrapped;
    public float3 incident;

    public __init()
    {
        surfaceDiffuse = 0;
        bandDiffuse = 0;
        wrapped = 0;
        incident = 0;
    }

    [mutating]
    public void addPunctual(PunctualLight light, float visibility, float3 normal, float3 bandNormal)
    {
        if (collectIncident)
            incident = mad(light.color, light.attenuation, incident);
        float3 radiance = (light.attenuation * visibility) * light.color;
        DiffuseLobes band = DiffuseLobes(bandNormal, light.direction);
        bandDiffuse = mad(radiance, band.cosine, bandDiffuse);
        surfaceDiffuse = mad(radiance, DiffuseLobes(normal, light.direction).cosine, surfaceDiffuse);
        wrapped = mad(band.wrapped, radiance, wrapped);
    }

    [mutating] public void finishAccumulation() {}
    public property diffuse : float3 { get { return surfaceDiffuse; } }
    public float paletteWeight(float surfaceWeight) { return surfaceWeight; }
    public float3 bounce() { return lerp(bandDiffuse, wrapped, 0.5); }
    public float3 applyFill(float3 color, float3 pigment, float3 ambient) { return color; }
}

public struct ToonSkinResponse<let face : bool> : ISkinLightResponse
{
    float3 band;

    public __init() { band = 0; }

    [mutating]
    public void addPunctual(PunctualLight light, float visibility, float3 normal, float3 bandNormal)
    {
        float3 incident = light.attenuation * light.color;
        float gain = rcp(directLightCompression(incident));
        float facing = bandFacing(bandNormal, light.direction);
        if (face)
            band += visibleFaceBand((incident * gain) * facing, visibility);
        else
        {
            float3 radiance = (light.attenuation * visibility) * light.color;
            band += perLightBand((radiance * gain) * facing);
        }
    }

    [mutating]
    public void addDirectional(float3 direction, float3 color, float3 bandNormal)
    {
        float3 radiance = color * rcp(directLightCompression(color));
        band += perLightBand(radiance * bandFacing(bandNormal, direction));
    }

    [mutating]
    public void finishAccumulation() { band *= rcp(bandCompression(band)); }

    // The artist ramp samples the unlit column. The bands supply direct color.
    public property diffuse : float3 { get { return 0; } }
    public float paletteWeight(float surfaceWeight) { return bandWeight(band); }
    public float3 bounce() { return band; }
    public float3 applyFill(float3 color, float3 pigment, float3 ambient)
    {
        return mad(pigment, skinFill(ambient, bandWeight(band)), color);
    }
}
