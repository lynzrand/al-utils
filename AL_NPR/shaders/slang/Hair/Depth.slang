import Coverage;
import DepthCoverage;

cbuffer UnityPerMaterial : register(b1)
{
    float _Dither : packoffset(c21.x);
    float _TipAlpha : packoffset(c21.y);
};

float hairCoverage(float2 positionCS)
{
    return coveredPixel(positionCS, _Dither) ? max(saturate(_TipAlpha), 0.01) : 0;
}
