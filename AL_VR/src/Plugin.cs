extern alias unity;

using System.Runtime.Versioning;
using BepInEx;
using BepInEx.Configuration;
using BepInEx.Unity.IL2CPP;
using unity::UnityEngine;
using unity::UnityEngine.Rendering;
using Object = unity::UnityEngine.Object;

[assembly: SupportedOSPlatform("windows")]

namespace AL_VR;

[BepInPlugin(Id, "AL SteamVR", "0.1.0")]
[BepInProcess("AmanatsuLocation.exe")]
public sealed class Plugin : BasePlugin
{
    public const string Id = "com.al-vr.steamvr";
    internal static Plugin Instance = null!;
    internal ConfigEntry<KeyCode> Toggle = null!;
    internal ConfigEntry<KeyCode> Recenter = null!;
    internal ConfigEntry<float> EyeResolution = null!;
    internal ConfigEntry<float> WorldUnitsPerMeter = null!;
    internal ConfigEntry<string> OpenVrLibrary = null!;
    private VrController? controller;

    public override void Load()
    {
        Instance = this;
        Toggle = Config.Bind("Controls", "Toggle", KeyCode.F9, "Start or stop the SteamVR session.");
        Recenter = Config.Bind("Controls", "Recenter", KeyCode.F10, "Align the headset's current position and heading with the game camera.");
        EyeResolution = Config.Bind("Rendering", "Eye Resolution Scale", 0.75f,
            new ConfigDescription("Scale SteamVR's recommended width and height for each eye at session start.",
                new AcceptableValueRange<float>(0.25f, 1.5f)));
        WorldUnitsPerMeter = Config.Bind("Rendering", "World Units Per Meter", 1.0f,
            new ConfigDescription("Scale physical eye separation and positional tracking into game world units.",
                new AcceptableValueRange<float>(0.1f, 10.0f)));
        OpenVrLibrary = Config.Bind("SteamVR", "OpenVR DLL Path", string.Empty,
            "Absolute path to SteamVR's 64-bit openvr_api.dll. Empty uses the default Steam installation.");
        if (SystemInfo.graphicsDeviceType == GraphicsDeviceType.Direct3D11)
        {
            controller = AddComponent<VrController>();
            Log.LogInfo("AL SteamVR ready. Start SteamVR with your headset connected and press F9 in game.");
        }
        else
            Log.LogInfo("AL SteamVR requires Direct3D 11. Launch with -force-d3d11.");
    }

    public override bool Unload()
    {
        if (controller)
        {
            controller!.Shutdown();
            Object.Destroy(controller);
        }
        return true;
    }
}
