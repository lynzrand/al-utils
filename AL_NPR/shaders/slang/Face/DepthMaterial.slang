import DepthCoverage;

cbuffer UnityPerMaterial : register(b1)
{
    float _Dither : packoffset(c33.w);
};
