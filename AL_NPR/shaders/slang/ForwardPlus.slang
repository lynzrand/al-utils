// Unity uploads four packed masks per register. Integer lanes preserve all bits
// when FXC lowers dynamic component selection (including subnormal bit patterns).
public cbuffer urp_ZBinBuffer : register(b2) { public uint4 urp_ZBinBufferData[1024]; }
public cbuffer urp_TileBuffer : register(b3) { public uint4 urp_TileBufferData[4096]; }

public struct ClusterLights
{
    uint tileOffset;
    uint zOffset;
    uint first;
    uint last;
    uint mask;

    public __init(uint tileOffset, uint zOffset, uint range)
    {
        this.tileOffset = tileOffset;
        this.zOffset = zOffset;
        first = range & 0xffff;
        last = range >> 16;
        mask = 0;
    }

    [mutating]
    public bool next(out uint index)
    {
        [loop] while (mask == 0 && first <= last)
        {
            uint word = first >> 5;
            uint t = tileOffset + word;
            uint z = zOffset + word;
            uint tiles = urp_TileBufferData[t >> 2][t & 3];
            uint bins = urp_ZBinBufferData[z >> 2][z & 3];
            uint lower = 0xffffffffu << (first & 31);
            uint upper = 0xffffffffu >> (31 - min(last - (word << 5), 31u));
            mask = tiles & bins & lower & upper;
            first = (word + 1) << 5;
        }
        bool found = mask != 0;
        index = 0;
        if (found)
        {
            index = first - 32 + firstbitlow(mask);
            mask &= mask - 1;
        }
        return found;
    }
}

// Tile and depth-bin headers contain *local* light indices. Callers add the
// directional count (fp0.w) when indexing the additional-light arrays.
public ClusterLights clusterForPixel(float2 screenUV, float viewDepth, bool perspective,
                                     float4 fp0, float4 fp1, float binCount)
{
    uint2 tile = uint2(max(screenUV * fp1.xy, 0));
    uint wordsPerTile = uint(fp1.w);
    uint tileOffset = (tile.y * uint(fp1.z) + tile.x) * wordsPerTile;
    float depth = perspective ? log2(viewDepth) : viewDepth;
    uint bin = min(uint(max(mad(depth, fp0.x, fp0.y), 0)), uint(binCount) - 1);
    uint header = bin * (wordsPerTile + 2);
    uint range = urp_ZBinBufferData[header >> 2][header & 3];
    return ClusterLights(tileOffset, header + 2, range);
}
