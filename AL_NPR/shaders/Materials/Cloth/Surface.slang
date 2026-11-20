import Materials.Cloth.Bindings;
import Materials.Cloth.FabricSampling;
import Surface.MaterialNoise;
import Surface.SurfaceNormals;

/// Sampled fluid, wetness, and tangent-space normal layers used by cloth pigment and lighting.
public struct ClothSurface
{
    /// Noise-offset fluid texture sample. RGB is layer color and A is its height and coverage.
    public float4 fluid;
    /// RGB sample from the garment region mask at transformed UV0.
    public float3 region;
    /// Combined liquid amount after weighting the four garment regions.
    public float wetness;
    /// Tangent-space liquid bump decoded at twice the wetness strength.
    public float3 wetNormalTS;
    /// Unit tangent-space normal from adjacent fluid alpha heights.
    public float3 fluidNormalTS;
    /// Unit tangent-space combination of the garment and liquid bump normals.
    public float3 baseNormalTS;
    /// Final unit tangent-space normal including the fluid height layer.
    public float3 normalTS;
};

/// Samples fluid color and adjacent heights, evaluates wetness, and combines the tangent-space normal layers at UV0.
public ClothSurface sampleClothSurface(float2 uv)
{
    ClothSurface surface;
    float2 fluidUV = mad(uv, _FluidTex_ST.xy, _FluidTex_ST.zw);
    float2 noise = float2(fluidNoise(fluidUV * _Fluid_Noise_Scale),
        fluidNoise((fluidUV + float2(12, 34)) * _Fluid_Noise_Scale));
    float2 texel = _FluidTex_TexelSize.xy;
    fluidUV = mad((noise - 0.5) * _Fluid_Noise_Amount, texel, fluidUV);
    surface.fluid = _FluidTex.Sample(sampler_FluidTex, fluidUV);
    float2 heights = float2(_FluidTex.Sample(sampler_FluidTex, fluidUV + float2(texel.x, 0)).a,
        _FluidTex.Sample(sampler_FluidTex, fluidUV + float2(0, texel.y)).a);
    surface.fluidNormalTS = normalize(float3((surface.fluid.a - heights) * _FluidNormalScale, 1));

    float2 liquidUV = mad(uv, _LiquidTiling.zw, _LiquidTiling.xy);
    surface.region = clothRegion(uv);
    surface.wetness = clothWetness(liquidUV, surface.region);

    float3 materialNormal = unpackScaledNormal(_Normal_map.Sample(sampler_Normal_map, uv), _BumpMapScale);
    surface.wetNormalTS = unpackScaledNormal(_LiquidBump.Sample(sampler_LiquidBump, liquidUV), 2 * surface.wetness);
    surface.baseNormalTS = normalize(combineNormalSlopes(materialNormal, surface.wetNormalTS));
    surface.normalTS = normalize(combineNormalSlopes(surface.fluidNormalTS, surface.baseNormalTS));
    return surface;
}
