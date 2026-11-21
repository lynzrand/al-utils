import Materials.Hair.Bindings;
import Materials.Hair.HairLighting;
import Materials.Hair.FiberStreak;
import Lighting.MapLighting;
import Lighting.PunctualLighting;
import Lighting.SceneLighting;

/// Stock places the painted stripe with the camera and key light. The toon
/// material retains a fraction of it and lights the rest from the scene.
public interface IHairLightResponse
{
    /// Rendering-layer bits accepted when selecting additional lights.
    property lightLayers : uint { get; }
    /// Scale of the original painted stripe before its two color lobes are shaded.
    property baseStripeGain : float { get; }
    /// RGB strand reflection contributed by the map's authored directional lights.
    float3 mapReflections();
    /// Return diffuse radiance for this light and add its reflected streak to the running RGB sum when
    /// applicable.
    float3 punctualRadiance(PunctualLight light, float visibility, bool clustered, inout float3 reflected);
    /// Turn accumulated RGB reflections into the highlight added after the palette.
    float3 tintReflection(float3 reflected, float detailMask, float4 highlight);
}

/// The original hair material lights the diffuse lobes and places its highlight with the painted stripe.
public struct StockHairResponse : IHairLightResponse
{
    public __init(HairInput input, float3 view) {}
    /// Use the receiver's Unity rendering-layer mask.
    public property lightLayers : uint { get { return asuint(renderingLayer.x); } }
    /// Keep the original painted stripe at full strength.
    public property baseStripeGain : float { get { return 1; } }
    /// Stock hair starts with zero scene-lit reflection.
    public float3 mapReflections() { return 0; }
    /// The stock palette returns zero additional reflection.
    public float3 tintReflection(float3 reflected, float detailMask, float4 highlight) { return 0; }

    /// Return the light color weighted by its attenuation and shadow visibility.
    public float3 punctualRadiance(PunctualLight light, float visibility, bool clustered, inout float3 reflected)
    {
        return (light.attenuation * visibility) * light.color;
    }
}

/// Strand frame and texture gradients shared by all scene-light streaks at this fragment.
public struct ToonHairResponse : IHairLightResponse
{
    /// World-space geometric normal defining the plane of the painted streak.
    float3 strandNormal;
    /// World-space tangent orthogonalized against the strand normal.
    float3 strandTangent;
    /// World-space direction toward the camera.
    float3 view;
    /// U coordinate from UV1, retained while the half-vector shifts the painted stripe vertically.
    float strandU;
    /// Screen-space X derivative of both UV1 components, carried into the explicit-gradient sample.
    float2 strandGradient;
#ifdef HAIR_FIBER
    float2 strandGradientY;
    float sheenScale;
    float strandTilt;
#endif

    /// Cache the orthogonalized strand axes and the UV1 derivative before entering the light loops.
    public __init(HairInput input, float3 viewDirection)
    {
        strandNormal = input.normalWS * rsqrt(max(dot(input.normalWS, input.normalWS), 1e-8));
        float3 tangent = input.tangentWS.xyz - strandNormal * dot(input.tangentWS.xyz, strandNormal);
        strandTangent = tangent * rsqrt(max(dot(tangent, tangent), 1e-8));
        view = viewDirection;
        strandU = input.uv1Uv0.x;
        strandGradient = ddx(input.uv1Uv0.xy);
#ifdef HAIR_FIBER
        strandTangent = paintedFiberAxis(strandNormal, strandTangent, input.uv1Uv0.xy, input.positionWS.xyz);
        strandGradientY = ddy(input.uv1Uv0.xy);
#ifdef HAIR_FIBER_DENSE
        strandTilt = fiberStrandTilt(input.uv1Uv0.xy);
#else
        strandTilt = 0;
#endif
#ifdef HAIR_FIBER_NOISE
        sheenScale = fiberSheenNoise(input.uv1Uv0.xy);
#else
        sheenScale = 1;
#endif
#endif
    }

    /// Select the map lights on rendering-layer bit 1 (mask value 2).
    public property lightLayers : uint { get { return 2u; } }
    /// Keep 26% of the original painted stripe alongside the scene-lit streak.
    public property baseStripeGain : float { get { return 0.26; } }

    /// Sample one light's stripe from its world-space direction and the cached strand frame.
    float streak(float3 direction)
    {
#ifdef HAIR_FIBER
        return fiberStreak(paintedHighlight, paintedHighlightSampler, strandNormal, strandTangent,
                           direction, view, strandU, strandGradient, strandGradientY, sheenScale, strandTilt);
#else
        // The release binds zero and ddx(UV) to the two explicit gradient operands.
        return paintedReflection(paintedHighlight, paintedHighlightSampler, strandNormal, strandTangent,
                                 direction, view, strandU, 0, strandGradient);
#endif
    }

    /// RGB strand reflection contributed by the map's authored directional lights.
    public float3 mapReflections()
    {
        float3 reflected = 0;
        [loop] for (uint i = 0; i < min(mapDirectionalCount, 32u); ++i)
        {
            MapDirectional light = mapDirectionals[i];
            float3 color = light.color.rgb;
            float peak = max(color.r, max(color.g, color.b));
            color /= 1 + 1.2 * max(peak - 0.5, 0);
            reflected += color * streak(light.direction.xyz);
        }
        return reflected;
    }

    /// Compress the diffuse RGB and accumulate a shadow-weighted painted reflection for each clustered local
    /// light.
    public float3 punctualRadiance(PunctualLight light, float visibility, bool clustered, inout float3 reflected)
    {
        float3 arriving = (light.attenuation * visibility) * light.color;
        float3 incident = light.attenuation * light.color;
        if (clustered)
        {
            float peak = max(incident.r, max(incident.g, incident.b));
            float energy = (peak + dot(incident, float3(0.212673, 0.715152, 0.072175))) * 0.5;
            float excess = max(energy - 0.5, 0);
            float gain = (0.5 + excess / (1 + 2 * excess)) / (0.5 + excess);
            reflected += (arriving * gain) * streak(light.direction);
        }
        return arriving * rcp(directLightCompression(incident));
    }

    /// Turn accumulated RGB reflections into the highlight added after the palette.
    public float3 tintReflection(float3 reflected, float detailMask, float4 highlight)
    {
        return finishHairReflection(reflected, detailMask, highlight);
    }
}
