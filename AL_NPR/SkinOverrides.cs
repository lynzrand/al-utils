extern alias unity;
using unity::UnityEngine;
using AssetBundle = UnityEngine.AssetBundle;

namespace AL_NPR;

// Keep the original material instances and their runtime properties. The
// bundle contains the same passes and property layouts as the stock shaders.
internal sealed class SkinOverrides : IDisposable
{
    private readonly AssetBundle bundle;
    private readonly Dictionary<string, Shader> replacements = new();
    private readonly Dictionary<int, Swap> swaps = new();
    private readonly Dictionary<int, Shader> originalsByReplacement = new();
    private readonly List<Shader> retainedOriginals = new();
    private readonly MapDirectional? mapDirectional;
    private bool visitedLoadedMaterials;
    internal bool UsesShaderMapLights { get; private set; }
    internal bool UsesMapDirectional { get; private set; }
    internal bool UsesMapDirectionalList { get; private set; }
    internal bool UsesRayVisibility { get; private set; }
    internal bool UsesRasterShadows { get; private set; }
    internal string? UploadedMapDirectional => mapDirectional?.UploadedLight;

    public SkinOverrides(string path)
    {
        bundle = AssetBundle.LoadFromFile(path);
        if (!bundle) throw new InvalidOperationException($"Could not load skin shader bundle at {path}.");
        try
        {
            LoadReplacement("skin_head", required: true);
            LoadReplacement("skin_body", required: true);
            LoadReplacement("cloth", required: false);
            LoadReplacement("cloth_alpha", required: false);
            LoadReplacement("hair", required: false);
            if (UsesMapDirectional || UsesMapDirectionalList)
                mapDirectional = new MapDirectional(UsesMapDirectionalList, UsesRayVisibility, UsesRasterShadows);
        }
        catch
        {
            bundle.Unload(true);
            throw;
        }
    }

    private void LoadReplacement(string name, bool required)
    {
        string path = $"assets/al_npr/{name}.shader";
        var shader = bundle.LoadAsset<Shader>(path);
        if (!required && !shader) return;
        if (!shader || !shader.isSupported)
            throw new InvalidOperationException($"The shader for AL/{name} is unsupported or missing.");
        string stockName = $"AL/{name}";
        bool usesMapDirectional = required && shader.name == stockName + "/MapDirectionalEnvironment";
        bool usesRayVisibility = required && shader.name == stockName + "/MapRayVisibilityEnvironment";
        bool usesRasterShadows = required && shader.name == stockName + "/MapRasterShadowsEnvironment";
        bool usesMapDirectionalList = usesRayVisibility || usesRasterShadows || required && shader.name == stockName + "/MapDirectionalsEnvironment";
        bool usesShaderMapLights = usesMapDirectional || usesMapDirectionalList || shader.name == stockName + "/MapEnvironment";
        if ((!usesShaderMapLights && shader.name != stockName + "/Environment") ||
            (required && replacements.Count > 0 &&
             (usesShaderMapLights != UsesShaderMapLights || usesMapDirectional != UsesMapDirectional ||
              usesMapDirectionalList != UsesMapDirectionalList || usesRayVisibility != UsesRayVisibility ||
              usesRasterShadows != UsesRasterShadows)))
            throw new InvalidOperationException($"Unexpected shader name or map light routing for {stockName}.");
        if (required)
        {
            UsesShaderMapLights = usesShaderMapLights;
            UsesMapDirectional = usesMapDirectional;
            UsesMapDirectionalList = usesMapDirectionalList;
            UsesRayVisibility = usesRayVisibility;
            UsesRasterShadows = usesRasterShadows;
        }
        // A managed reference held by the plugin does not survive Unity's
        // native unused-asset sweep during the transition from the title.
        shader.hideFlags |= HideFlags.DontUnloadUnusedAsset;
        replacements.Add(stockName, shader);
    }

    public int Apply()
    {
        foreach (var id in swaps.Where(pair => !pair.Value.Material).Select(pair => pair.Key).ToArray())
            swaps.Remove(id);

        // Some game passes build their own material copies. Update the
        // loaded originals when entering a map, then pick up renderers and
        // newly assigned instances during normal scene updates.
        if (!visitedLoadedMaterials)
        {
            visitedLoadedMaterials = true;
            foreach (var material in Resources.FindObjectsOfTypeAll<Material>())
                ApplyMaterial(material);
        }
        foreach (var renderer in unity::UnityEngine.Object.FindObjectsOfType<Renderer>())
            foreach (var material in renderer.sharedMaterials)
                ApplyMaterial(material);
        if (mapDirectional is not null) mapDirectional.Active = swaps.Count != 0;
        return swaps.Count;
    }

    private void ApplyMaterial(Material? material)
    {
        if (!material || !material!.shader) return;
        var original = material.shader;
        if (!replacements.TryGetValue(original.name, out var replacement) || !replacement) return;
        Assign(material, replacement);
        var assigned = material.shader;
        if (assigned == replacement)
        {
            if ((original.hideFlags & HideFlags.DontUnloadUnusedAsset) == 0)
            {
                original.hideFlags |= HideFlags.DontUnloadUnusedAsset;
                retainedOriginals.Add(original);
            }
            originalsByReplacement.TryAdd(replacement.GetInstanceID(), original);
            swaps[material.GetInstanceID()] = new Swap(material, original, replacement);
        }
        else
            Assign(material, original);
    }

    public void Restore()
    {
        if (mapDirectional is not null) mapDirectional.Active = false;
        foreach (var swap in swaps.Values)
            if (swap.Material && swap.Original &&
                (swap.Material.shader == swap.Replacement || !swap.Replacement))
                Assign(swap.Material, swap.Original);
        // The game can create a material from a template that already has
        // the replacement. Such copies have no pre-swap entry of their own.
        if (originalsByReplacement.Count > 0)
        {
            foreach (var material in Resources.FindObjectsOfTypeAll<Material>())
            {
                if (!material || !material.shader) continue;
                if (originalsByReplacement.TryGetValue(material.shader.GetInstanceID(), out var original) && original)
                    Assign(material, original);
            }
        }
        foreach (var shader in retainedOriginals)
            if (shader) shader.hideFlags &= ~HideFlags.DontUnloadUnusedAsset;
        retainedOriginals.Clear();
        originalsByReplacement.Clear();
        swaps.Clear();
        visitedLoadedMaterials = false;
    }

    public void Dispose()
    {
        Restore();
        mapDirectional?.Dispose();
        bundle.Unload(true);
    }

    private static void Assign(Material material, Shader shader)
    {
        var keywords = material.shaderKeywords;
        int queue = material.rawRenderQueue;
        material.shader = shader;
        material.shaderKeywords = keywords;
        material.renderQueue = queue;
    }

    private sealed record Swap(Material Material, Shader Original, Shader Replacement);
}
