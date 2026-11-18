extern alias unity;
using UnityEngine.Rendering.Universal;
using unity::UnityEngine;

namespace AL_NPR;

// A separate light lets the character receive less intensity without scaling
// the authored light on the map. Its shadow caster mask can still include the map.
internal sealed class CharacterFill
{
    private readonly Light light;
    private readonly UniversalAdditionalLightData data;

    public CharacterFill(Transform owner, string sourceName)
    {
        var host = new GameObject("AL Fill: " + sourceName);
        host.transform.SetParent(owner, false);
        light = host.AddComponent<Light>();
        light.enabled = false;
        data = host.AddComponent<UniversalAdditionalLightData>();
        data.renderingLayers = EnvironmentLightingController.CharacterLayer;
        data.customShadowLayers = true;
    }

    public void Apply(Light source, UniversalAdditionalLightData sourceData, int characterObjectLayers, float gain)
    {
        light.type = source.type;
        light.transform.SetPositionAndRotation(source.transform.position, source.transform.rotation);
        light.color = source.color;
        light.useColorTemperature = source.useColorTemperature;
        light.colorTemperature = source.colorTemperature;
        light.range = source.range;
        light.spotAngle = source.spotAngle;
        light.innerSpotAngle = source.innerSpotAngle;
        light.cookie = source.cookie;
        light.cullingMask = source.cullingMask | characterObjectLayers;
        light.shadows = source.shadows;
        light.shadowStrength = source.shadowStrength;
        light.shadowBias = source.shadowBias;
        light.shadowNormalBias = source.shadowNormalBias;
        light.shadowNearPlane = source.shadowNearPlane;
        data.usePipelineSettings = sourceData.usePipelineSettings;
        data.shadowRenderingLayers = (sourceData.customShadowLayers ? sourceData.shadowRenderingLayers :
            sourceData.renderingLayers) | EnvironmentLightingController.CharacterLayer;
        light.intensity = source.intensity * gain;
        light.enabled = true;
    }

    public void Destroy()
    {
        if (!light) return;
        light.enabled = false;
        unity::UnityEngine.Object.Destroy(light.gameObject);
    }
}
