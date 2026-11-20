import ShadowFiltering;
import VertexTransforms;

public cbuffer LightShadows : register(b5)
{
    TransformColumns mainWorldToShadow[5] : packoffset(c0);
    float4 cascadeSpheres[4] : packoffset(c20);
    float4 cascadeRadiiSquared : packoffset(c24);
    public float4 mainShadowParams : packoffset(c27);
    public float4 additionalShadowFadeParams : packoffset(c31);
    float4 additionalShadowParams[256] : packoffset(c33);
    TransformColumns additionalWorldToShadow[256] : packoffset(c289);
};

// Select the innermost containing cascade. Unity binds a fifth matrix for
// positions outside all four spheres.
public float3 mainShadowCoord(float3 positionWS)
{
    float4 inside;
    [unroll] for (uint i = 0; i < 4; ++i)
    {
        float3 delta = positionWS - cascadeSpheres[i].xyz;
        inside[i] = dot(delta, delta) < cascadeRadiiSquared[i] ? 1 : 0;
    }
    inside.yzw = max(inside.yzw - inside.xyz, 0);
    uint cascade = uint(4 - dot(inside, float4(4, 3, 2, 1)));
    return mainWorldToShadow[cascade].point(positionWS);
}

// Unity's cube-face order is +X, -X, +Y, -Y, +Z, -Z. The shader's light
// direction points back toward the lamp. Ties prefer Z, then Y.
uint pointShadowFace(float3 lightDirection)
{
    float3 magnitude = abs(lightDirection);
    if (magnitude.z >= magnitude.x && magnitude.z >= magnitude.y)
        return lightDirection.z > 0 ? 5 : 4;
    if (magnitude.y >= magnitude.x)
        return lightDirection.y > 0 ? 3 : 2;
    return lightDirection.x > 0 ? 1 : 0;
}

public float punctualVisibility(Texture2D<float4> atlas, SamplerComparisonState compare, uint index,
                                float3 positionWS, float3 lightDirection, float shadowFade, bool filterFace)
{
    float4 shadow = additionalShadowParams[index];
    int slice = int(shadow.w);
    float visibility = 1;
    if (slice >= 0)
    {
        if (shadow.z != 0)
            slice += int(pointShadowFace(lightDirection));
        float4 homogeneous = additionalWorldToShadow[slice].clipPosition(positionWS);
        float3 uvz = homogeneous.xyz / homogeneous.w;
        float sample = filterFace ? faceVisibility(atlas, compare, uvz)
                                  : atlas.SampleCmpLevelZero(compare, uvz.xy, uvz.z);
        if (uvz.z > 0 && uvz.z < 1)
            visibility = mad(sample, shadow.x, 1 - shadow.x);
    }
    return mad(shadowFade, 1 - visibility, visibility);
}
