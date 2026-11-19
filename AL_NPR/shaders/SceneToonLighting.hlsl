// Extracted AL 1.0.4 Forward+ material shaders supply light lists, surface
// normals, shadow samples, and the original texture/palette composition.
static const float3 Luminance = float3(0.212673, 0.715152, 0.072175);

// These three functions describe the existing direction and range mapping.
// L points from the surface to the source. V points to the camera.
float3 BandDirection(float3 L, float3 V)
{
    float3 bent = L + 1.4 * dot(L, V) * V;
    return bent * rsqrt(max(dot(bent, bent), 1e-12));
}

float3 LimitLight(float3 rgb, float knee, float strength)
{
    float peak = max(rgb.r, max(rgb.g, rgb.b));
    return rgb / (1.0 + strength * max(peak - knee, 0.0));
}

float3 LightAtSurface(float3 rgb, float distanceAndSpot, float visibility,
                      float3 normal, float3 L, float3 V)
{
    return LimitLight(rgb * distanceAndSpot, 0.10, 7.0)
         * visibility * saturate(dot(normal, BandDirection(L, V)));
}

// The builder compiles this entry into both light loops in all four materials.
// Each lamp independently crosses a 0.04 to 0.08 luminance transition.
float3 PerLightBand(float3 arrivingRGB : TEXCOORD0) : SV_Target
{
    float y = dot(arrivingRGB, Luminance);
    float ramp = saturate(25.0 * y - 1.0);
    return arrivingRGB * ((0.18 * ramp) / max(y, 1e-6));
}

// The game accumulates PerLightBand() across eligible sources, then passes
// the resulting RGB to the palette and its normalized luminance to the fill.
float4 MergeBands(float3 sum)
{
    float3 rgb = LimitLight(sum, 0.18, 4.5);
    return float4(rgb, saturate(dot(rgb, Luminance) / 0.18));
}

// lighting.xyz is the material's scene SH evaluated at its shading normal,
// lighting.w is MergeBands().w. Multiplying the result by the material's
// processed pigment keeps prints and skin tones visible under diffuse fill.
float DiffuseFill(float4 lighting)
{
    return 0.84 * saturate(dot(lighting.rgb, Luminance)) + 0.49 * lighting.w;
}

float SkinFill(float4 lighting : TEXCOORD0) : SV_Target
{
    return 0.06 * DiffuseFill(lighting);
}

float FabricFill(float4 lighting : TEXCOORD0) : SV_Target
{
    return 0.97 * DiffuseFill(lighting);
}
