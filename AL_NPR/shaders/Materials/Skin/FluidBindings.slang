// Face and body expose these Unity property names at different byte offsets.
// Project each pass's bindings into the inputs consumed by the fluid modules.
#if SKIN_FACE
import Materials.Face.Bindings;
import Materials.Face.Material;
#else
import Materials.Body.Bindings;
import Materials.Body.Material;
#endif
import Materials.Skin.FluidLayer;
import Materials.Skin.FluidPigment;

public FluidMap<Filter> skinFluidMap<Filter : IFluidFilter>()
{
    FluidMap<Filter> map;
    map.paintMap = _FluidTex;
    map.paintSampler = sampler_FluidTex;
    map.scaleOffset = _FluidTex_ST;
    map.texelSize = _FluidTex_TexelSize.xy;
    map.noiseScale = _Fluid_Noise_Scale;
    map.noiseAmount = _Fluid_Noise_Amount;
    map.normalScale = _FluidNormalScale;
    return map;
}

public FluidPigment skinFluidPigment()
{
    FluidPigment pigment;
    pigment.transmittance = _FluidTransmittance;
    pigment.highlightPower = _FluidHighlightPower;
    pigment.shadowSaturation = _FluidShadowSaturation;
    pigment.shadowSize = _FluidShadowSize;
    pigment.shadowPower = _FluidShadowPower;
    pigment.highlightSize = _FluidHighlightSize;
    pigment.colorScatter = _FluidColorScatter;
    pigment.minColorScale = _FluidMinColorScale;
    pigment.scale = _FluidScale;
    return pigment;
}
