extern alias unity;
using BepInEx;
using BepInEx.Unity.IL2CPP;
using Il2CppInterop.Runtime.Injection;
using unity::UnityEngine;

namespace AL_NPR;

[BepInPlugin("local.al.npr", "AL Scene Lighting", "0.1.0")]
[BepInProcess("AmanatsuLocation.exe")]
public sealed class Plugin : BasePlugin
{
    internal static BepInEx.Configuration.ConfigEntry<bool>? HigherMapShadowResolution { get; private set; }
    internal static BepInEx.Configuration.ConfigEntry<bool>? HigherShadowDepthPrecision { get; private set; }

    public override void Load()
    {
        HigherMapShadowResolution = Config.Bind("Shadows", "HigherMapShadowResolution", true,
            "Double the requested side length of authored map point/spot shadow slices and their atlas, up to 8192.");
        HigherShadowDepthPrecision = Config.Bind("Shadows", "HigherShadowDepthPrecision", false,
            "Request 32-bit depth for the additional-light shadow atlas while the map-light shader is active.");
        var path = Path.Combine(Path.GetDirectoryName(GetType().Assembly.Location)!, "al-skin-lighting.unity3d");
        if (File.Exists(path))
        {
            try { Log.LogInfo(SceneLighting.StartDirect(path)); }
            catch (Exception error) { Log.LogWarning(error); }
        }
        else SceneLighting.Start();
        Log.LogInfo("F7 compares stock and environment lighting. F8 toggles character light suppression.");
    }

    public override bool Unload()
    {
        SceneLighting.Stop();
        return true;
    }
}

public static class SceneLighting
{
    private static GameObject? host;
    private static EnvironmentLightingController? trial;

    // Can also be called through the development REPL without a restart.
    public static string Start()
    {
        if (trial) return Status();
        ClassInjector.RegisterTypeInIl2Cpp<EnvironmentLightingController>();
        host = new GameObject("AL Scene Lighting");
        unity::UnityEngine.Object.DontDestroyOnLoad(host);
        trial = host.AddComponent<EnvironmentLightingController>();
        return Status();
    }

    public static string StartDirect(string bundlePath)
    {
        Start();
        trial!.UseDirectLighting(bundlePath);
        return Set(true, !trial.UsesShaderMapLights);
    }

    public static string Set(bool shareMapLights, bool automaticKey)
    {
        Start();
        trial!.SetMode(shareMapLights, automaticKey);
        return Status();
    }

    public static string Status() => trial ? trial!.Status : "Scene lighting trial stopped.";

    // Keep the selected sun and light slots fixed while comparing shadow cost.
    public static string SetRasterShadows(bool enabled)
    {
        if (!trial) throw new InvalidOperationException("Start the scene lighting trial first.");
        trial!.SetRasterShadows(enabled);
        return Status();
    }

    public static void Stop()
    {
        if (trial) trial!.Shutdown();
        if (host) unity::UnityEngine.Object.Destroy(host);
        trial = null;
        host = null;
    }
}
