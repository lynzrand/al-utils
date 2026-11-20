/// Unity uploads four packed masks per register. Integer lanes preserve all bits
/// when FXC lowers dynamic component selection (including subnormal bit patterns).
public cbuffer urp_ZBinBuffer : register(b2)
{
    /// Four consecutive words per register. Each bin starts with two headers, then light masks with one bit
    /// per local light.
    public uint4 urp_ZBinBufferData[1024];
}
/// Unity's per-camera visibility masks for local lights overlapping each screen tile.
public cbuffer urp_TileBuffer : register(b3)
{
    /// Screen-tile light masks, four consecutive words per register. Each set bit admits one local light.
    public uint4 urp_TileBufferData[4096];
}

/// Iterator over local lights common to a depth bin and a screen tile.
public struct ClusterLights
{
    /// First 32-bit word of the current screen tile's light bit mask.
    uint tileOffset;
    /// First 32-bit word of this depth bin's light bit mask, after its two header words.
    uint zOffset;
    /// Next light bit to scan. During consumption it points just past the current 32-bit word.
    uint first;
    /// Inclusive last local-light bit admitted by the depth-bin header's high 16 bits.
    uint last;
    /// Unconsumed candidate bits in the current word after intersecting the tile, depth bin, and index bounds.
    uint mask;
    /// Number of directional entries preceding local lights in Unity's additional-light arrays.
    uint firstLocalLight;

    /// Initialize the local range from the low (first) and high (last) 16-bit halves of the Z-bin header.
    public __init(uint tileOffset, uint zOffset, uint range, uint firstLocalLight)
    {
        this.tileOffset = tileOffset;
        this.zOffset = zOffset;
        this.firstLocalLight = firstLocalLight;
        first = range & 0xffff;
        last = range >> 16;
        mask = 0;
    }

    /// Consume the lowest surviving bit and return an absolute additional-light index. Returns false after the
    /// range is exhausted.
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

/// Unity packs the camera's grid and light counts into _FPParams0/1/2.
/// Material code sees the leading directionals and absolute local light indices.
public struct ForwardPlusGrid
{
    /// XY maps linear orthographic depth or log2 perspective depth to a Z-bin index.
    float2 depthScaleBias;
    /// XY converts normalized screen coordinates to tile coordinates along each axis.
    float2 tileScale;
    /// Number of screen tiles across a row of the packed tile mask.
    uint tilesPerRow;
    /// Number of 32-bit light mask words per screen tile, also used for the Z-bin payload width.
    uint wordsPerTile;
    /// Number of depth bins in this camera's Forward+ grid.
    uint binCount;
    /// Number of directional entries preceding local lights in Unity's additional-light arrays.
    uint firstLocalLight;

    /// Unpack depth scale/bias from depthParams.xy and directional count from W. tileParams contains XY tile
    /// scale, Z row width, and W words per tile.
    public __init(float4 depthParams, float4 tileParams, float binCount)
    {
        depthScaleBias = depthParams.xy;
        firstLocalLight = uint(depthParams.w);
        tileScale = tileParams.xy;
        tilesPerRow = uint(tileParams.z);
        wordsPerTile = uint(tileParams.w);
        this.binCount = uint(binCount);
    }

    /// Number of leading additional directionals to traverse, limited to the bound 256-light arrays.
    public property directionalCount : uint { get { return min(firstLocalLight, 256u); } }

    /// Create a bit iterator for a normalized screen UV and positive view depth using the camera's projection
    /// mode.
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
