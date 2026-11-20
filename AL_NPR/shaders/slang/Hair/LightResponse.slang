import Hair.Bindings;
import HairLighting;
import MapLighting;
import PunctualLighting;
import SceneLighting;

// Stock places the painted stripe with the camera and key light. The toon
// material retains a fraction of it and lights the rest from the scene.
public interface IHairLightResponse
{
    property lightLayers : uint { get; }
    property baseStripeGain : float { get; }
    float3 mapReflections();
    float3 punctualRadiance(PunctualLight light, float visibility, bool clustered, inout float3 reflected);
    float3 tintReflection(float3 reflected, float detailMask, float4 highlight);
}

public struct StockHairResponse : IHairLightResponse
{
    public __init(HairInput input, float3 view) {}
    public property lightLayers : uint { get { return asuint(renderingLayer.x); } }
    public property baseStripeGain : float { get { return 1; } }
    public float3 mapReflections() { return 0; }
    public float3 tintReflection(float3 reflected, float detailMask, float4 highlight) { return 0; }

    public float3 punctualRadiance(PunctualLight light, float visibility, bool clustered, inout float3 reflected)
    {
        return (light.attenuation * visibility) * light.color;
    }
}

public struct ToonHairResponse : IHairLightResponse
{
    float3 strandNormal, strandTangent, view;
    float strandU;
    float2 strandGradient;

    public __init(HairInput input, float3 viewDirection)
    {
        strandNormal = input.normalWS * rsqrt(max(dot(input.normalWS, input.normalWS), 1e-8));
        float3 tangent = input.tangentWS.xyz - strandNormal * dot(input.tangentWS.xyz, strandNormal);
        strandTangent = tangent * rsqrt(max(dot(tangent, tangent), 1e-8));
        view = viewDirection;
        strandU = input.uv1Uv0.x;
        strandGradient = ddx(input.uv1Uv0.xy);
    }

    public property lightLayers : uint { get { return 2u; } }
    public property baseStripeGain : float { get { return 0.26; } }

    float streak(float3 direction)
    {
        // The release binds zero and ddx(UV) to the two explicit gradient operands.
        return paintedReflection(paintedHighlight, paintedHighlightSampler, strandNormal, strandTangent,
                                 direction, view, strandU, 0, strandGradient);
    }

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

    public float3 tintReflection(float3 reflected, float detailMask, float4 highlight)
    {
        return finishHairReflection(reflected, detailMask, highlight);
    }
}
