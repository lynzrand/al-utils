// Ordered 4x4 coverage pattern used by the game across color and depth passes.
public static const float coveragePattern[16] = {
     1, 9,  3, 11,
    13, 5, 15,  7,
     4, 12, 2, 10,
    16, 8, 14,  6
};

// The render-target scale/bias and projection sign determine the screen-space
// orientation of the Bayer cell, including when drawing into a shadow atlas.
public float ditherThreshold(float2 positionCS, float2 screenSize, float2 scaleBias, float projectionSign)
{
    float2 uv = (1 / screenSize) * positionCS;
    float y = 1 - mad(uv.y, scaleBias.x, scaleBias.y);
    float2 pixel = float2(uv.x * screenSize.x,
                          projectionSign < 0 ? mad(-y, screenSize.y, screenSize.y) : y * screenSize.y);
    uint2 cell = uint2(max(fmod(pixel * 0.25, 1.0) * 4, 0));
    return coveragePattern[min(cell.y * 4 + cell.x, 15u)] / 16.0;
}

public bool passesDither(float opacity, float threshold)
{
    return saturate(opacity * 1.00001) >= threshold;
}

public void clipCoverage(float opacity, float cutoff, bool alphaToMask)
{
    float delta = opacity - cutoff;
    if (alphaToMask && cutoff > 0)
    {
        float width = abs(ddx_coarse(opacity)) + abs(ddy_coarse(opacity));
        delta = saturate(mad(-width, 0.5, delta) / max(width, 0.0001) + 1) - 0.0001;
    }
    if (delta < 0) discard;
}

// The red and blue channels are paired across the two garments. Green
// selects each garment's coverage ceiling. The material switches are rounded.
public float clothingMask(float3 top, float3 bottom, float topSetting, float bottomSetting)
{
    float topSwitch = round(topSetting);
    float bottomSwitch = round(bottomSetting);
    float topCeiling = saturate(max(2 - top.g, topSwitch) - 1);
    float bottomCeiling = saturate(max(2 - bottom.g, bottomSwitch) - 1);
    float topMask = max(min(1 - top.r, 1 - bottom.b), topSwitch);
    float bottomMask = max(min(1 - top.b, 1 - bottom.r), bottomSwitch);
    return round(min(min(topMask, topCeiling), min(bottomMask, bottomCeiling)));
}
