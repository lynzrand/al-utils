// Unity packs four 32-bit light masks per float4 in these two constant buffers.
public cbuffer urp_ZBinBuffer : register(b2) { public float4 urp_ZBinBufferData[1024]; }
public cbuffer urp_TileBuffer : register(b3) { public float4 urp_TileBufferData[4096]; }

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
            uint tiles = asuint(urp_TileBufferData[t >> 2][t & 3]);
            uint bins = asuint(urp_ZBinBufferData[z >> 2][z & 3]);
            uint lower = 0xffffffffu << (first & 31);
            uint upper = 0xffffffffu >> (31 - min(last - (word << 5), 31u));
            mask = tiles & bins & lower & upper;
            first = (word + 1) << 5;
        }
        if (mask == 0)
        {
            index = 0;
            return false;
        }
        index = first - 32 + firstbitlow(mask);
        mask &= mask - 1;
        return true;
    }
}
