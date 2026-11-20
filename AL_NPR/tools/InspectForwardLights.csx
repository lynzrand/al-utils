{
    var camera = Camera.main;
    var counts = Shader.GetGlobalVector("_FPParams0");
    var positions = Shader.GetGlobalVectorArray("_AdditionalLightsPosition");
    var colors = Shader.GetGlobalVectorArray("_AdditionalLightsColor");
    var masks = Shader.GetGlobalFloatArray("_AdditionalLightsLayerMasks");
    var stop = Math.Min((int)(counts.z + counts.w), Math.Min(positions.Length, Math.Min(colors.Length, masks.Length)));
    var lights = UnityEngine.Object.FindObjectsOfType<Light>();

    Print("Frame " + Time.frameCount + " camera " + camera.transform.position.ToString("F3")
        + " forward " + camera.transform.forward.ToString("F3")
        + " additional " + stop + " main " + Shader.GetGlobalVector("_MainLightColor").ToString("F3")
        + " direction " + Shader.GetGlobalVector("_MainLightPosition").ToString("F3"));
    Print(alSceneLighting.GetMethod("Status").Invoke(null, null));
    for (var index = 0; index < stop; index++)
    {
        int mask = BitConverter.SingleToInt32Bits(masks[index]);
        if ((mask & 4) == 0) continue;
        var position = positions[index];
        var at = new Vector3(position.x, position.y, position.z);
        var name = "";
        foreach (var light in lights)
        {
            var target = position.w == 0f ? -light.transform.forward : light.transform.position;
            if ((at - target).sqrMagnitude < 0.001f)
                name += light.name + (light.enabled ? "(enabled);" : "(disabled);");
        }
        Print("L " + mask + " " + position.ToString("F3") + " " + colors[index].ToString("F3") + " " + name);
    }
}
