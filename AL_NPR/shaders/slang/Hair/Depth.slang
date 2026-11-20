import Coverage;
import DepthCoverage;

cbuffer UnityPerMaterial : register(b1)
{
    float _Dither : packoffset(c21.x);
    float _TipAlpha : packoffset(c21.y);
};

public float hairCoverage(float2 positionCS)
{
    return coveredPixel(positionCS, _Dither) ? max(saturate(_TipAlpha), 0.01) : 0;
}

public void clipHairCoverage(float2 positionCS, float cutoff)
{
    clipCoverage(hairCoverage(positionCS), cutoff, alphaToMaskAvailable != 0);
}
