import Materials.Cloth.Bindings;
import Materials.Cloth.FabricSampling;
import Surface.MaterialNoise;
import Surface.SurfaceNormals;

public struct ClothSurface
{
    public float4 fluid;
    public float3 region;
    public float wetness;
    public float3 wetNormalTS;
    public float3 fluidNormalTS;
    public float3 baseNormalTS;
    public float3 normalTS;
};

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
