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
    uint firstLocalLight;

    public __init(uint tileOffset, uint zOffset, uint range, uint firstLocalLight)
    {
        this.tileOffset = tileOffset;
        this.zOffset = zOffset;
        this.firstLocalLight = firstLocalLight;
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
            index = firstLocalLight + (first - 32 + firstbitlow(mask));
            mask &= mask - 1;
        }
        return found;
    }
}

// Unity packs the camera's grid and light counts into _FPParams0/1/2.
// Material code sees the leading directionals and absolute local light indices.
public struct ForwardPlusGrid
{
    float2 depthScaleBias;
    float2 tileScale;
    uint tilesPerRow;
    uint wordsPerTile;
    uint binCount;
    uint firstLocalLight;

    public __init(float4 depthParams, float4 tileParams, float binCount)
    {
        depthScaleBias = depthParams.xy;
        firstLocalLight = uint(depthParams.w);
        tileScale = tileParams.xy;
        tilesPerRow = uint(tileParams.z);
        wordsPerTile = uint(tileParams.w);
        this.binCount = uint(binCount);
    }

    public property directionalCount : uint { get { return min(firstLocalLight, 256u); } }

    public ClusterLights localLights(float2 screenUV, float viewDepth, bool perspective)
    {
        uint2 tile = uint2(max(screenUV * tileScale, 0));
        uint tileOffset = (tile.y * tilesPerRow + tile.x) * wordsPerTile;
        float depth = perspective ? log2(viewDepth) : viewDepth;
        uint bin = min(uint(max(mad(depth, depthScaleBias.x, depthScaleBias.y), 0)), binCount - 1);
        uint header = bin * (wordsPerTile + 2);
        uint range = urp_ZBinBufferData[header >> 2][header & 3];
        return ClusterLights(tileOffset, header + 2, range, firstLocalLight);
    }
}
