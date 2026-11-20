/// The plugin uploads the count as a packed uint, followed by pairs of
/// direction/color registers. All NPR forward passes read this same buffer.
public struct MapDirectional
{
    /// XYZ points toward the authored directional light in world space. The uploader writes zero to W.
    public float4 direction;
    /// RGB stores Unity's final light color. W flags the raster-shadow main light in that experimental upload
    /// mode.
    public float4 color;
}

/// Directional lights and optional visibility settings uploaded by AL_NPR for the current map.
public cbuffer ALMapLighting : register(b10)
{
    /// Number of active direction/color pairs in this camera's upload. The optional visibility upload reserves
    /// c0.yzw for its enable bit, width, and height.
    public uint mapDirectionalCount : packoffset(c0.x);
    /// Packed map lights in upload order. Each entry occupies one direction and one color register.
    public MapDirectional mapDirectionals[32] : packoffset(c1);
};
