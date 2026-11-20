// Color and depth passes share the dry silhouette. The color pass also writes
// coverage to the render target after applying the garment masks and clipping.
public interface IFabricOpacity
{
    static float dryOpacity(float outline, float3 dyedColor, float sheer, float sheerStrength);
    static float targetAlpha(float coverage, bool alphaToMask);
}

public struct OpaqueFabric : IFabricOpacity
{
    public static float dryOpacity(float outline, float3 dyedColor, float sheer, float sheerStrength)
    {
        return outline;
    }

    public static float targetAlpha(float coverage, bool alphaToMask)
    {
        return alphaToMask ? coverage : 1;
    }
}

public struct CutoutFabric : IFabricOpacity
{
    public static float dryOpacity(float outline, float3 dyedColor, float sheer, float sheerStrength)
    {
        float luma = saturate(mad(dot(dyedColor, float3(0.299, 0.587, 0.114)), 0.6, 0.4));
        return saturate(mad(-sheerStrength, luma * sqrt(sheer), outline));
    }

    public static float targetAlpha(float coverage, bool alphaToMask)
    {
        return coverage;
    }
}
