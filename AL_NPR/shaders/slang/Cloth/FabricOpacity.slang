// The color and depth passes use the same silhouette. Cutout fabrics additionally
// let dyed color and sheerness thin that silhouette.
public enum FabricKind { Opaque, Cutout }

public struct FabricOpacity<let kind : FabricKind>
{
    public float3 dyedColor;
    public float sheer;

    public float dryOpacity(float outline, float sheerStrength)
    {
        if (kind == FabricKind.Opaque)
            return outline;
        float luma = saturate(mad(dot(dyedColor, float3(0.299, 0.587, 0.114)), 0.6, 0.4));
        return saturate(mad(-sheerStrength, luma * sqrt(sheer), outline));
    }

    public static float targetAlpha(float coverage, bool alphaToMask)
    {
        return kind == FabricKind.Cutout || alphaToMask ? coverage : 1;
    }
};
