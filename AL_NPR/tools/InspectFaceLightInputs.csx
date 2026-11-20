{
    var camera = Camera.main;
    var heads = new List<Vector3>();
    foreach (var renderer in UnityEngine.Object.FindObjectsOfType<SkinnedMeshRenderer>()) {
        if (!renderer.enabled || !renderer.isVisible) continue;
        bool isFace = false;
        foreach (var material in renderer.sharedMaterials) {
            if (material != null && material.shader != null && material.shader.name == "AL/skin_head")
                isFace = true;
        }
        if (!isFace) continue;
        foreach (var bone in renderer.bones) {
            if (bone == null || bone.name != "cf_J_FaceBase") continue;
            var screen = camera.WorldToViewportPoint(bone.position);
            if (screen.z > 0 && screen.x >= 0 && screen.x <= 1 && screen.y >= 0 && screen.y <= 1)
                heads.Add(bone.position);
            break;
        }
    }
    Print(SceneManager.GetActiveScene().name);
    Print(alSceneLighting.GetMethod("Status").Invoke(null, null));
    var counts = Shader.GetGlobalVector("_FPParams0");
    var positions = Shader.GetGlobalVectorArray("_AdditionalLightsPosition");
    var colors = Shader.GetGlobalVectorArray("_AdditionalLightsColor");
    var masks = Shader.GetGlobalFloatArray("_AdditionalLightsLayerMasks");
    var atten = Shader.GetGlobalVectorArray("_AdditionalLightsAttenuation");
    var spots = Shader.GetGlobalVectorArray("_AdditionalLightsSpotDir");
    var lights = UnityEngine.Object.FindObjectsOfType<Light>();
    foreach (var head in heads) {
      Print("Face " + head.ToString("F3") + " viewport=" + camera.WorldToViewportPoint(head).ToString("F3")
          + " distance=" + Vector3.Distance(camera.transform.position, head).ToString("F2"));
      for (var i=0; i < (int)(counts.z+counts.w); i++) {
        int mask = BitConverter.SingleToInt32Bits(masks[i]);
        if ((mask & 4) == 0) continue;
        var pos = new Vector3(positions[i].x, positions[i].y, positions[i].z);
        var toward = pos - head * positions[i].w;
        var d2 = Mathf.Max(toward.sqrMagnitude, 0.000061f);
        var d = d2 * atten[i].x;
        var range = Mathf.Clamp01(1f - d*d);
        var dir = new Vector3(spots[i].x, spots[i].y, spots[i].z);
        var cone = Mathf.Clamp01(Vector3.Dot(dir, toward.normalized)*atten[i].z+atten[i].w);
        Vector4 c = colors[i] * (range*range*cone*cone/d2);
        float luma = 0.2126f*c.x + 0.7152f*c.y + 0.0722f*c.z;
        if (luma < 0.006f) continue;
        foreach (var light in lights) {
            if (!light.enabled) continue;
            var data = light.GetComponent<UnityEngine.Rendering.Universal.UniversalAdditionalLightData>();
            if (data == null || data.renderingLayers != unchecked((uint)mask)) continue;
            var target = positions[i].w == 0f ? -light.transform.forward : light.transform.position;
            if ((pos-target).sqrMagnitude > 0.001f) continue;
            Print(light.name + " " + light.type + " dist=" + Mathf.Sqrt(d2).ToString("F2") +
                " intensity=" + light.intensity.ToString("F1") + " cone=" + cone.ToString("F3") +
                " lumaBeforeNormalAndShadow=" + luma.ToString("F3") + " rgb=" + c.ToString("F3"));
        }
      }
    }
}
