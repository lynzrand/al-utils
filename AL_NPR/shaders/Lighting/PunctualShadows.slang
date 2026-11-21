import Lighting.ShadowFiltering;
import Geometry.VertexTransforms;

/// Unity shadow transforms and strengths for the main cascade atlas and additional lights.
public cbuffer LightShadows : register(b5)
{
    /// Four cascade transforms plus Unity's fallback transform for receivers outside all four split spheres.
    TransformColumns mainWorldToShadow[5] : packoffset(c0);
    /// World-space center in XYZ for each main-light split sphere. The radius test uses cascadeRadiiSquared.
    float4 cascadeSpheres[4] : packoffset(c20);
    /// Squared radii of the four split spheres in cascade order across XYZW.
    float4 cascadeRadiiSquared : packoffset(c24);
    /// X is the main shadow strength used to mix the comparison sample toward full visibility.
    public float4 mainShadowParams : packoffset(c27);
    /// X scales squared camera distance and Y biases it to produce the additional-light shadow fade.
    public float4 additionalShadowFadeParams : packoffset(c31);
    /// X is shadow strength, Z selects six-face point sampling, and W is the first slice index or a negative
    /// sentinel. Y is unused here.
    float4 additionalShadowParams[256] : packoffset(c33);
    /// World-to-atlas homogeneous transforms indexed by the additional shadow slice, including individual
    /// point-light faces.
    TransformColumns additionalWorldToShadow[256] : packoffset(c289);
};

/// Select the innermost containing cascade. Unity binds a fifth matrix for
/// positions outside all four spheres.
/// Return atlas UV in XY and comparison depth in Z from the innermost main cascade containing the receiver.
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

/// Unity's cube-face order is +X, -X, +Y, -Y, +Z, -Z. The shader's light
/// direction points back toward the lamp. Ties prefer Z, then Y.
/// Select the point-light cube face for a surface-to-light direction, breaking ties in Z then Y order.
uint pointShadowFace(float3 lightDirection)
{
    float3 magnitude = abs(lightDirection);
    uint face = lightDirection.x > 0 ? 1 : 0;
    if (magnitude.y >= magnitude.x)
        face = lightDirection.y > 0 ? 3 : 2;
    if (magnitude.z >= magnitude.x && magnitude.z >= magnitude.y)
        face = lightDirection.z > 0 ? 5 : 4;
    return face;
}

/// Return per-light shadow visibility after strength and camera fade, optionally using a 3 × 3 tent.
public float punctualVisibility(Texture2D<float4> atlas, SamplerComparisonState compare, uint index,
                                float3 positionWS, float3 lightDirection, float shadowFade, bool useTent)
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
        float sample = useTent ? tentVisibility(atlas, compare, uvz)
                                  : atlas.SampleCmpLevelZero(compare, uvz.xy, uvz.z);
        if (uvz.z > 0 && uvz.z < 1)
            visibility = mad(sample, shadow.x, 1 - shadow.x);
    }
    return mad(shadowFade, 1 - visibility, visibility);
}
