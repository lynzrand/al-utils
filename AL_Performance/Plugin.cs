extern alias unity;
using BepInEx;
using BepInEx.Configuration;
using BepInEx.Unity.IL2CPP;
using UnityEngine.Rendering.Universal;
using unity::UnityEngine;

namespace AL_Performance;

[BepInPlugin(Id, "AL Performance", "0.1.0")]
[BepInProcess("AmanatsuLocation.exe")]
public sealed class Plugin : BasePlugin
{
    public const string Id = "com.al-povx.performance";
    internal static Plugin Instance { get; private set; } = null!;
    internal ConfigEntry<float> RenderScale { get; private set; } = null!;
    internal ConfigEntry<int> MsaaSamples { get; private set; } = null!;
    internal ConfigEntry<bool> DisableFsr { get; private set; } = null!;
    internal ConfigEntry<ShadowFilter> SoftShadows { get; private set; } = null!;
    private PerformanceController? controller;

    public override void Load()
    {
        Instance = this;
        RenderScale = Config.Bind("Rendering", "Render Scale", 0f,
            "Internal URP render scale. 0 uses the game's scale. Values from 0.5 to 1 change 3D resolution while retaining the window size.");
        MsaaSamples = Config.Bind("Rendering", "MSAA Samples", 0, new ConfigDescription(
            "0 uses the game's MSAA. 1 disables it. 2, 4 and 8 select the sample count.",
            new AcceptableValueList<int>(0, 1, 2, 4, 8)));
        DisableFsr = Config.Bind("Rendering", "Disable FSR", false,
            "Select URP's Auto filter. At 100% this also removes the stock FSR sharpening pass.");
        SoftShadows = Config.Bind("Rendering", "Soft Shadow Filter", ShadowFilter.Game,
            "Set the PCF filter quality for the pipeline and active soft-shadow lights. Game uses the authored settings.");
        controller = AddComponent<PerformanceController>();
    }

    public override bool Unload()
    {
        if (controller)
        {
            controller!.Shutdown();
            unity::UnityEngine.Object.Destroy(controller);
        }
        return true;
    }
}

public enum ShadowFilter { Game, Low, Medium, High }
