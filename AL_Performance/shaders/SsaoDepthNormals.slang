// SM4 reconstruction of the captured URP 17 desktop DepthNormals/12-tap
// interleaved-gradient variant. Explicit packing keeps the captured bindings.
cbuffer Frame : register(b0)
{
    /// XY are the screen width and height in pixels for the interleaved sampling pattern.
    float4 ScreenSize : packoffset(c3);
    /// X is the sampling LOD bias for scene depth and normals.
    float4 MipBias : packoffset(c4);
    /// ZW convert a device depth d to eye distance as 1 / (z*d + w).
    float4 ZBuffer : packoffset(c24);
    /// XY scale normalized camera UVs into the occupied portion of the render textures.
    float4 RtScale : packoffset(c28);
    /// Z contributes the X coefficient of the axis used to recover projected eye depth.
    float4 ViewRow0 : packoffset(c66);
    /// Z contributes the Y coefficient of that eye-depth axis.
    float4 ViewRow1 : packoffset(c67);
    /// Z contributes the Z coefficient of that eye-depth axis.
    float4 ViewRow2 : packoffset(c68);
    /// XY are reciprocal depth texture dimensions for the half-texel shift and edge clamp.
    float4 DepthTexelSize : packoffset(c135);
    /// XY are reciprocal normals texture dimensions for the half-texel edge clamp.
    float4 NormalsTexelSize : packoffset(c136);
    /// X is intensity, Y sample radius, Z sampling-resolution scale and W the eye-distance cutoff.
    float4 Ao : packoffset(c138);
    /// XYZ locate the top-left near-plane point relative to the camera in the reconstruction basis.
    float4 ViewTopLeft : packoffset(c139);
    /// XY are the X-axis contribution to the projected sample position.
    float4 ProjectionCol0 : packoffset(c141);
    /// XY are the Y-axis contribution to the projected sample position.
    float4 ProjectionCol1 : packoffset(c142);
    /// XY are the Z-axis contribution to the projected sample position.
    float4 ProjectionCol2 : packoffset(c143);
    /// X is inverse near-clip distance. Multiplication by eye depth scales a near-plane ray.
    float4 NearReciprocal : packoffset(c150);
    /// XYZ span the near plane as normalized U increases from zero to one.
    float4 ViewXExtent : packoffset(c151);
    /// XYZ span the near plane in the direction of increasing 1 - V.
    float4 ViewYExtent : packoffset(c153);
};

/// Scene depth from the captured camera. The estimator reads the raw device depth in X.
Texture2D<float4> DepthTexture : register(t0);
/// XYZ supply the scene normal in the same basis as the reconstructed sample offsets.
Texture2D<float4> NormalsTexture : register(t1);
/// Sampler used for both depth and normals, including the frame's explicit mip bias.
SamplerState SceneSampler : register(s0);

static const int SampleCount = 12;
static const float SkyDepth = 0.00001;
static const float2 RandomOffsets[SampleCount] = {
    float2(0.00000000, 0.92968750), float2(0.33984375, 0.76171875),
    float2(0.75390625, 0.13333330), float2(0.56640625, 0.01562500),
    float2(0.98437500, 0.00000000), float2(0.07421875, 0.10546875),
    float2(0.23828125, 0.64062500), float2(0.64062500, 0.74609375),
    float2(0.35937500, 0.67968750), float2(0.50781250, 0.35156250),
    float2(0.38281250, 0.49218750), float2(0.98437500, 0.12500000)
};

struct Interpolators
{
    /// Raster position required by the captured fullscreen signature. The estimator derives pixel coordinates from UV.
    float4 position : SV_Position;
    /// Normalized screen coordinates used to look up depth and normals.
    float2 uv : TEXCOORD0;
};

/// Adjusts for sample resolution, clamps at the upper texture edge and returns raw device depth.
float SampleDepth(float2 uv)
{
    float2 halfTexel = DepthTexelSize.xy * 0.5;
    uv += halfTexel * (1.0 - (Ao.z - 0.5) * 2.0);
    return DepthTexture.SampleBias(SceneSampler, min(uv, 1.0 - halfTexel) * RtScale.xy, MipBias.x).x;
}

/// Linearizes raw device depth into positive distance along the camera depth axis.
float EyeDepth(float depth)
{
    return 1.0 / mad(ZBuffer.z, depth, ZBuffer.w);
}

/// Reconstructs a camera-relative point from normalized screen coordinates and linear eye depth.
float3 ViewPosition(float2 uv, float depth)
{
    float3 ray = mad(ViewXExtent.xyz, uv.x, ViewTopLeft.xyz);
    ray = mad(ViewYExtent.xyz, 1.0 - uv.y, ray);
    return ray * (depth * NearReciprocal.x);
}

/// Rotates one of twelve deterministic offsets into the normal's hemisphere and scales it by its tap radius.
float3 SampleOffset(float2 screenPosition, float3 normal, int index)
{
    float2 noisePosition = mad(screenPosition, Ao.z, float2(2.083, 4.867) * index);
    float noise = frac(52.9829189 * frac(dot(noisePosition, float2(0.06711056, 0.00583715))));
    float u = mad(frac(RandomOffsets[index].x + noise), 2.0, -1.0);
    float theta = (RandomOffsets[index].y + noise) * 6.28318530717958647693;
    float sine, cosine;
    sincos(theta, sine, cosine);
    float circleRadius = sqrt(mad(-u, u, 1.0));
    float3 offset = float3(circleRadius * cosine, circleRadius * sine, u);
    offset *= sqrt((index + 1.0) / SampleCount);
    return faceforward(offset, -normal, offset);
}

/// Projects one offset, rejects sky and depth discontinuities, and weights the valid displacement by the normal.
float EstimateOcclusion(float2 screenPosition, float3 viewPosition, float3 normal, float eyeDepth, int index)
{
    float3 samplePosition = mad(SampleOffset(screenPosition, normal, index), Ao.y, viewPosition);
    float2 projected = ProjectionCol1.xy * samplePosition.y;
    projected = mad(ProjectionCol0.xy, samplePosition.x, projected);
    projected = mad(ProjectionCol2.xy, samplePosition.z, projected);
    float zDistance = -dot(float3(ViewRow0.z, ViewRow1.z, ViewRow2.z), samplePosition);
    float2 sampleUv = saturate(mad(projected, 1.0 / zDistance, 1.0) * 0.5);
    float rawSample = SampleDepth(sampleUv);
    float sampleDepth = EyeDepth(rawSample);
    bool valid = abs(zDistance - sampleDepth) < Ao.y && rawSample > SkyDepth;

#ifdef SKIP_INVALID_SAMPLE
    // A depth discontinuity or sky contributes zero. A coherent tile can skip
    // reconstruction, the AO denominator, and the reciprocal for that tap.
    [branch] if (!valid) return 0.0;
#endif

    float3 displacement = ViewPosition(sampleUv, sampleDepth) - viewPosition;
    float numerator = max(mad(-eyeDepth, 0.004, dot(displacement, normal)), 0.0);
#ifdef SKIP_ZERO_NUMERATOR
    [branch] if (numerator == 0.0) return 0.0;
#endif
    float reciprocal = 1.0 / (dot(displacement, displacement) + 0.0001);
    return numerator * reciprocal * (valid ? 1.0 : 0.0);
}

/// Writes occlusion to R and the normal encoded into [0, 1] to GBA. Rejected pixels use a neutral encoded normal.
[shader("fragment")]
float4 main(Interpolators input) : SV_Target
{
    float rawDepth = SampleDepth(input.uv);
    if (rawDepth < SkyDepth) return float4(0.0, 0.5, 0.5, 0.5);

    float eyeDepth = EyeDepth(rawDepth);
    if (eyeDepth > Ao.w) return float4(0.0, 0.5, 0.5, 0.5);

    float2 normalsUv = min(input.uv, 1.0 - NormalsTexelSize.xy * 0.5) * RtScale.xy;
    float3 normal = NormalsTexture.SampleBias(SceneSampler, normalsUv, MipBias.x).xyz;
    float3 position = ViewPosition(input.uv, eyeDepth);
    float2 screenPosition = input.uv * ScreenSize.xy;
    float occlusion = 0.0;
    [unroll] for (int index = 0; index < SampleCount; index++)
        occlusion += EstimateOcclusion(screenPosition, position, normal, eyeDepth, index);

    float falloff = mad(-eyeDepth, 1.0 / Ao.w, 1.0);
    occlusion *= Ao.y * (falloff * falloff) * Ao.x * (1.0 / SampleCount);
    return float4(pow(saturate(occlusion), 0.6), mad(normal, 0.5, 0.5));
}
