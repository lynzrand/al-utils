{
    var probes = LightmapSettings.lightProbes;
    Print("scene=" + SceneManager.GetActiveScene().name + " api=" + SystemInfo.graphicsDeviceType
        + " ambient=" + RenderSettings.ambientMode + " intensity=" + RenderSettings.ambientIntensity
        + " bakedProbes=" + (probes == null ? 0 : probes.count));

    var ambient = RenderSettings.ambientProbe;
    for (int rgb = 0; rgb < 3; rgb++)
    {
        var coefficients = new string[9];
        for (int term = 0; term < 9; term++) coefficients[term] = ambient[rgb, term].ToString("F4");
        Print("ambient SH " + "RGB"[rgb] + ": " + string.Join(", ", coefficients));
    }

    var reflections = UnityEngine.Object.FindObjectsOfType<ReflectionProbe>();
    foreach (var renderer in UnityEngine.Object.FindObjectsOfType<SkinnedMeshRenderer>())
    {
        if (!renderer.enabled || !renderer.isVisible) continue;
        var shaders = new List<string>();
        foreach (var material in renderer.sharedMaterials)
        {
            if (material == null || material.shader == null) continue;
            string shader = material.shader.name;
            bool isSkin = shader == "AL/skin_head" || shader.StartsWith("AL/skin_head/", StringComparison.Ordinal)
                || shader == "AL/skin_body" || shader.StartsWith("AL/skin_body/", StringComparison.Ordinal);
            if (isSkin && !shaders.Contains(shader)) shaders.Add(shader);
        }
        if (shaders.Count == 0) continue;
        var anchor = renderer.probeAnchor;
        var position = anchor == null ? renderer.bounds.center : anchor.position;
        Print("skin=" + string.Join(", ", shaders.ToArray()) + " objectLayer=" + LayerMask.LayerToName(renderer.gameObject.layer)
            + " renderMask=0x" + renderer.renderingLayerMask.ToString("X") + " at=" + position
            + " diffuse=" + renderer.lightProbeUsage + " reflection=" + renderer.reflectionProbeUsage);
        foreach (var reflection in reflections)
        {
            if (!reflection.enabled || !reflection.bounds.Contains(position)) continue;
            var texture = reflection.texture;
            Print("  overlapping reflection: " + reflection.name + " " + reflection.mode
                + " priority=" + reflection.importance + " intensity=" + reflection.intensity
                + " texture=" + (texture == null ? "-" : texture.name + " " + texture.graphicsFormat));
        }
    }

    foreach (var light in UnityEngine.Object.FindObjectsOfType<Light>())
    {
        if (!light.enabled || light.intensity <= 0f) continue;
        Print("light=" + light.name + " " + light.type + " rgb=" + light.color + " intensity=" + light.intensity
            + " objectMask=0x" + light.cullingMask.ToString("X") + " renderMask=0x" + light.renderingLayerMask.ToString("X")
            + " range=" + light.range + " shadows=" + light.shadows);
    }
}
