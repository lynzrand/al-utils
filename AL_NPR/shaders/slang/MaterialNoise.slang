// Value noise used to distort the painted liquid mask. Match the game's
// corner interpolation order so the mip-free wet normal follows the mask.
float hashCell(float2 cell)
{
    return frac(sin(dot(cell, float2(12.9898, 78.233))) * 43758.547);
}

public float valueNoise(float2 uv)
{
    float2 cell = floor(uv);
    float2 f = frac(uv);
    float2 square = f * f;
    float2 cubic = mad(-f, 2, 3);
    float2 high = square * cubic;
    float2 low = mad(-square, cubic, 1);
    float row0 = mad(low.x, hashCell(cell), high.x * hashCell(cell + float2(1, 0)));
    float row1 = mad(low.x, hashCell(cell + float2(0, 1)), high.x * hashCell(cell + 1));
    return mad(low.y, row0, high.y * row1);
}

public float fluidNoise(float2 uv)
{
    float fine = valueNoise(uv);
    float medium = valueNoise(uv * 0.5);
    float coarse = valueNoise(uv * 0.25);
    return mad(coarse, 0.5, mad(fine, 0.125, medium * 0.25));
}

// Each grid cell contains one animated sweat droplet. The material combines
// the nearest two half-squared distances to form its height and wet-normal mask.
public float2 sweatCellDistances(float2 cell, float2 localUV, float phase)
{
    float2 nearest = 8;
    [unroll] for (int y = -1; y <= 1; ++y)
    {
        [unroll] for (int x = -1; x <= 1; ++x)
        {
            float2 offset = float2(x, y);
            float2 neighbor = cell + offset;
            float2 seed = float2(dot(neighbor, float2(127.1, 311.7)),
                                 dot(neighbor, float2(269.5, 183.3)));
            float2 angle = mad(frac(sin(seed) * 43758.547), 6.2831, phase);
            float2 center = mad(sin(angle), 0.5, 0.5);
            float2 delta = (localUV - offset) - center;
            float distance = 0.5 * dot(delta, delta);
            nearest.y = distance < nearest.x ? nearest.x : min(distance, nearest.y);
            nearest.x = min(distance, nearest.x);
        }
    }
    return nearest;
}
