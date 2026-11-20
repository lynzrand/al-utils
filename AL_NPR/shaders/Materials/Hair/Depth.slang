import Surface.Coverage;
import Surface.DepthCoverage;

/// Material controls shared by hair depth, depth-normal, and shadow coverage.
cbuffer UnityPerMaterial : register(b1)
{
    /// Material opacity tested against the Bayer pattern at the rasterized pixel.
    float _Dither : packoffset(c21.x);
    /// Alpha of surviving tips, saturated and floored at 0.01 before the pass's cutoff.
    float _TipAlpha : packoffset(c21.y);
};

/// Return tip opacity for a surviving Bayer sample, or zero for a rejected pixel.
public float hairCoverage(float2 positionCS)
{
    return coveredPixel(positionCS, _Dither) ? max(saturate(_TipAlpha), 0.01) : 0;
}

/// Apply the pass's cutoff to tip coverage with Unity's alpha-to-mask setting.
public void clipHairCoverage(float2 positionCS, float cutoff)
{
    clipCoverage(hairCoverage(positionCS), cutoff, alphaToMaskAvailable != 0);
}
