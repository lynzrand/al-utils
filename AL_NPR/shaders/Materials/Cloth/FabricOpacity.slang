/// Color and depth passes share the dry silhouette. The color pass also writes
/// coverage to the render target after applying the garment masks and clipping.
public interface IFabricOpacity
{
    /// Returns dry coverage from outline alpha and the fabric's dyed color and sheerness.
    static float dryOpacity(float outline, float3 dyedColor, float sheer, float sheerStrength);
    /// Returns the render-target alpha after clipping, accounting for fabric type and alpha-to-coverage.
    static float targetAlpha(float coverage, bool alphaToMask);
}

/// Keeps the dry outline and writes solid alpha unless alpha-to-coverage is enabled.
public struct OpaqueFabric : IFabricOpacity
{
    /// Returns the outline alpha unchanged for the opaque weave.
    public static float dryOpacity(float outline, float3 dyedColor, float sheer, float sheerStrength)
    {
        return outline;
    }

    /// Preserves coverage for alpha-to-coverage and writes one otherwise.
    public static float targetAlpha(float coverage, bool alphaToMask)
    {
        return alphaToMask ? coverage : 1;
    }
}

/// Reduces dry opacity according to dyed luminance and sheerness, then writes the surviving coverage.
public struct CutoutFabric : IFabricOpacity
{
    /// Thins the outline using dyed luminance and the square root of the sheer-region weight.
    public static float dryOpacity(float outline, float3 dyedColor, float sheer, float sheerStrength)
    {
        float luma = saturate(mad(dot(dyedColor, float3(0.299, 0.587, 0.114)), 0.6, 0.4));
        return saturate(mad(-sheerStrength, luma * sqrt(sheer), outline));
    }

    /// Preserves coverage as alpha for the cutout weave.
    public static float targetAlpha(float coverage, bool alphaToMask)
    {
        return coverage;
    }
}
