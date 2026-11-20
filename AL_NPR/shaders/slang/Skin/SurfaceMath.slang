// Object-space gradient noise modulates the stock skin's surface detail.
// Lock the lattice to the mesh so the pattern follows the character.
float2 grainGradient(float2 cell)
{
    float2 seed = mad(cell, float2(0.3183099, 0.3678794), float2(0.3678794, 0.3183099));
    float hash = frac((seed.y * seed.x) * (seed.y + seed.x));
    return mad(frac(hash * float2(5.0929585, 5.8860703)), 2, -1);
}

public float skinGrain(float2 positionOS)
{
    float2 grid = positionOS * 4;
    float2 cell = floor(grid);
    float2 uv = frac(grid);
    float2 blend = uv * uv * mad(-uv, 2, 3);
    float lowerLeft = dot(grainGradient(cell), uv);
    float lowerRight = dot(grainGradient(cell + float2(1, 0)), uv - float2(1, 0));
    float upperLeft = dot(grainGradient(cell + float2(0, 1)), uv - float2(0, 1));
    float upperRight = dot(grainGradient(cell + 1), uv - 1);
    float lower = mad(blend.x, lowerRight - lowerLeft, lowerLeft);
    float upper = mad(blend.x, upperRight - upperLeft, upperLeft);
    return mad(mad(blend.y, upper - lower, lower), 0.5, 0.5);
}
