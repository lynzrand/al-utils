import Coverage;

// Depth, normals and shadow passes use the same screen transform for coverage.
public cbuffer Globals : register(b0)
{
    public float2 scaledScreenSize : packoffset(c3);
    public float alphaToMaskAvailable : packoffset(c4.z);
    public float projectionSign : packoffset(c22);
    public float2 scaleBias : packoffset(c27);
};

public bool coveredPixel(float2 positionCS, float opacity)
{
    return passesDither(opacity, ditherThreshold(positionCS, scaledScreenSize, scaleBias, projectionSign));
}
