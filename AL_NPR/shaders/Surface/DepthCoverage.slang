import Surface.Coverage;

/// Depth, normals and shadow passes use the same screen transform for coverage.
public cbuffer Globals : register(b0)
{
    /// Width and height of the active scaled viewport in pixels.
    public float2 scaledScreenSize : packoffset(c3);
    /// Nonzero enables the derivative-based coverage clip used for alpha-to-mask passes.
    public float alphaToMaskAvailable : packoffset(c4.z);
    /// A negative projection sign flips the Bayer lookup vertically.
    public float projectionSign : packoffset(c22);
    /// X scales and Y biases the normalized vertical coordinate for the current render target.
    public float2 scaleBias : packoffset(c27);
};

/// Test opacity against the projected pixel's 4 × 4 ordered-dither threshold.
public bool coveredPixel(float2 positionCS, float opacity)
{
    return passesDither(opacity, ditherThreshold(positionCS, scaledScreenSize, scaleBias, projectionSign));
}
