// The plugin uploads the count as a packed uint, followed by pairs of
// direction/color registers. All NPR forward passes read this same buffer.
public struct MapDirectional
{
    public float4 direction;
    public float4 color;
}

public cbuffer ALMapLighting : register(b10)
{
    public uint mapDirectionalCount : packoffset(c0.x);
    public MapDirectional mapDirectionals[32] : packoffset(c1);
};
