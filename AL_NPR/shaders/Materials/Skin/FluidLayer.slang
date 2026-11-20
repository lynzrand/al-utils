import Materials.Skin.FluidMask;
import Surface.MaterialNoise;

/// RGBA pigment and tangent-space normal from a center paint sample and two neighboring alpha samples.
public struct FluidLayer
{
    /// Sampled fluid pigment RGB with paint alpha used for opacity, height and scattering.
    public float4 paint;
    /// Unit tangent-space normal from the alpha differences to the right and upper texels.
    public float3 normalTS;
}

/// Compile-time texture sampling contract for fluid pigment and its neighboring height taps.
public interface IFluidFilter
{
    /// Reads pigment RGB and height/coverage A together at a normalized paint UV.
    static float4 samplePaint(Texture2D<float4> paint, SamplerState paintSampler, float2 uv);
}

/// Reads the paint with Unity's texture sampler at the original UV.
public struct LinearFluidFilter : IFluidFilter
{
    /// Reads pigment RGB and height/coverage A together at a normalized paint UV.
    public static float4 samplePaint(Texture2D<float4> paint, SamplerState paintSampler, float2 uv)
    {
        return paint.Sample(paintSampler, uv);
    }
}

/// Reconstructs single-mip paint with cubic B-spline weights, preserving ordinary sampling for other
/// textures.
public struct CubicFluidFilter : IFluidFilter
{
    /// Reads pigment RGB and height/coverage A together at a normalized paint UV.
    public static float4 samplePaint(Texture2D<float4> paint, SamplerState paintSampler, float2 uv)
    {
        return sampleFluidMask(paint, paintSampler, uv);
    }
}

/// Painted fluid texture and artist sampling controls. The filter type specializes all three paint reads.
public struct FluidMap<Filter : IFluidFilter>
{
    /// Material fluid texture. RGB holds pigment and neighboring alpha values supply the height field.
    public Texture2D<float4> paintMap;
    /// Unity sampler used for all center and neighbor paint reads with the selected filter.
    public SamplerState paintSampler;
    /// Normalized paint UV transform. XY scale the mesh UV and ZW offset it.
    public float4 scaleOffset;
    /// Reciprocal paint width and height in UV units, for one-texel height taps and UV displacement.
    public float2 texelSize;
    /// Spatial frequency of the two decorrelated fluid-noise samples.
    public float noiseScale;
    /// Amplitude of the noise displacement in paint texels.
    public float noiseAmount;
    /// Multiplier converting finite differences in alpha into tangent-space slopes.
    public float normalScale;

    /// Applies the chosen compile-time filter to one RGBA paint sample at normalized UV.
    float4 readPaint(float2 uv)
    {
        return Filter.samplePaint(paintMap, paintSampler, uv);
    }

    /// Warps normalized material UV and reads the center, +X and +Y paint texels for pigment and
    /// tangent-space normal.
    public FluidLayer sampleLayer(float2 materialUV)
    {
        float2 uv = mad(materialUV, scaleOffset.xy, scaleOffset.zw);
        float2 noise = float2(fluidNoise(uv * noiseScale),
                              fluidNoise((uv + float2(12, 34)) * noiseScale));
        uv = mad((noise - 0.5) * noiseAmount, texelSize, uv);

        FluidLayer layer;
        layer.paint = readPaint(uv);
        float heightX = readPaint(uv + float2(texelSize.x, 0)).a;
        float heightY = readPaint(uv + float2(0, texelSize.y)).a;
        float2 gradient = (layer.paint.a - float2(heightX, heightY)) * normalScale;
        layer.normalTS = normalize(float3(gradient, 1));
        return layer;
    }
}
