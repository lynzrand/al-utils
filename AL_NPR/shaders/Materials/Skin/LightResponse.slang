import Lighting.PunctualLighting;
import Lighting.Reflectance;
import Lighting.SceneLighting;

/// Accumulate each visible light, finish the sum, then let the face or body
/// use that result for its artist ramp, colored bounce and ambient fill.
///
/// Compile-time accumulation and palette contract used by both skin materials.
public interface ISkinLightResponse
{
    /// Accumulates one attenuated light with shadow visibility. normal and bandNormal are world-space surface
    /// normals.
    [mutating] void addPunctual(PunctualLight light, float visibility, float3 normal, float3 bandNormal);
    /// Finalizes the accumulated response before its palette, bounce and fill terms are read.
    [mutating] void finishAccumulation();
    /// Direct cosine-weighted RGB for ramp lookup. The toon response supplies zero to retain the unlit ramp
    /// sample.
    property diffuse : float3 { get; }
    /// Returns the direct weight for the artist palette, using surfaceWeight in stock and the compressed band
    /// in NPR.
    float paletteWeight(float surfaceWeight);
    /// Returns the colored diffuse contribution applied to pigment after the ramp.
    float3 bounce();
    /// Returns the shaded RGB with the selected response's pigment-weighted ambient fill.
    float3 applyFill(float3 color, float3 pigment, float3 ambient);
}

/// Accumulates Unity lights as cosine and wrapped diffuse terms. Outline passes can also collect incident
/// light.
public struct StockSkinResponse<let collectIncident : bool> : ISkinLightResponse
{
    /// RGB cosine-weighted radiance about the material shading normal, used by the artist ramp.
    float3 surfaceDiffuse;
    /// RGB cosine-weighted radiance about the normal chosen for band evaluation.
    float3 bandDiffuse;
    /// RGB half-Lambert radiance about the band normal. Averaged with bandDiffuse for bounce.
    float3 wrapped;
    /// Attenuated incident RGB collected for the body outline before multiplying by surface facing.
    public float3 incident;

    /// Starts the per-pixel light accumulation with zero radiance.
    public __init()
    {
        surfaceDiffuse = 0;
        bandDiffuse = 0;
        wrapped = 0;
        incident = 0;
    }

    /// Accumulates cosine and wrapped diffuse about the two supplied normals. Outlines also collect pre-
    /// facing incident RGB.
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

    /// Stock diffuse and wrapped sums are ready for the palette immediately after accumulation.
    [mutating] public void finishAccumulation() {}
    /// Cosine-weighted RGB about the surface normal, added to the artist ramp coordinate.
    public property diffuse : float3 { get { return surfaceDiffuse; } }
    /// Retains the palette weight computed from the key, surface facing and local diffuse.
    public float paletteWeight(float surfaceWeight) { return surfaceWeight; }
    /// Returns the mean of cosine-weighted and wrapped RGB about the band normal.
    public float3 bounce() { return lerp(bandDiffuse, wrapped, 0.5); }
    /// Returns the stock lit color unchanged.
    public float3 applyFill(float3 color, float3 pigment, float3 ambient) { return color; }
}

/// Accumulates authored map lights and punctual lights in per-light toon bands.
public struct ToonSkinResponse<let face : bool> : ISkinLightResponse
{
    /// Sum of the per-light RGB bands. finishAccumulation compresses the completed sum before palette and
    /// fill reads.
    float3 band;

    /// Starts the per-pixel light accumulation with zero radiance.
    public __init() { band = 0; }

    /// Compresses incident radiance and evaluates the bent-normal band. Face visibility is applied after
    /// the band and body visibility before it.
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

    /// Adds the band of one authored directional using its normalized world direction and RGB radiance.
    [mutating]
    public void addDirectional(float3 direction, float3 color, float3 bandNormal)
    {
        float3 radiance = color * rcp(directLightCompression(color));
        band += perLightBand(radiance * bandFacing(bandNormal, direction));
    }

    /// Compresses the accumulated RGB band once after every light has contributed.
    [mutating]
    public void finishAccumulation() { band *= rcp(bandCompression(band)); }

    /// Zero keeps the artist ramp at its unlit column while the bands supply direct color.
    public property diffuse : float3 { get { return 0; } }
    /// Derives the palette weight from the luminance of the compressed RGB band.
    public float paletteWeight(float surfaceWeight) { return bandWeight(band); }
    /// Returns the compressed per-light RGB band to tint the pigment.
    public float3 bounce() { return band; }
    /// Adds pigment tinted by the diffuse probe and the finalized band weight.
    public float3 applyFill(float3 color, float3 pigment, float3 ambient)
    {
        return mad(pigment, skinFill(ambient, bandWeight(band)), color);
    }
}
