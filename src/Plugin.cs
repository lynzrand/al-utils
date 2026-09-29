extern alias unity;
using BepInEx;
using BepInEx.Configuration;
using BepInEx.Unity.IL2CPP;
using UnityObject = unity::UnityEngine.Object;
using KeyCode = unity::UnityEngine.KeyCode;

namespace AL_PovX;

[BepInPlugin(Id, "AL H Utils", "0.5.0")]
[BepInProcess("AmanatsuLocation.exe")]
public sealed class Plugin : BasePlugin
{
    public const string Id = "com.al-povx.camera";
    internal static Plugin Instance = null!;
    internal Settings Settings = null!;
    private PovController? controller;
    private SceneHotkeys? sceneHotkeys;

    public override void Load()
    {
        Instance = this;
        Settings = new Settings(Config);
        controller = AddComponent<PovController>();
        sceneHotkeys = AddComponent<SceneHotkeys>();
        Log.LogInfo("AL H Utils loaded. Key bindings are configurable in com.al-povx.camera.cfg.");
    }

    public override bool Unload()
    {
        if (sceneHotkeys) UnityObject.Destroy(sceneHotkeys);
        if (controller)
        {
            controller!.Shutdown();
            UnityObject.Destroy(controller);
        }
        return true;
    }
}

internal sealed class Settings
{
    internal readonly ConfigEntry<KeyCode> Toggle, Cycle, Drag, Release, Zoom, Recenter, ExitPov;
    internal readonly ConfigEntry<KeyCode> Stronger, MaleLock, FemaleLock;
    internal readonly ConfigEntry<float> RepeatInterval;
    internal readonly ConfigEntry<bool> HideHead, LockCursor, InvertY, FollowRotation, FollowPosition, ResetOnPoseChange;
    internal readonly ConfigEntry<float> Sensitivity, Fov, ZoomFov, NearClip, OffsetX, OffsetY, OffsetZ, PitchLimit, YawLimit;

    internal Settings(ConfigFile config)
    {
        Toggle = config.Bind("Hotkeys", "PoV Toggle Key", KeyCode.Comma);
        Cycle = config.Bind("Hotkeys", "Character Cycle Key", KeyCode.Period);
        Drag = config.Bind("Hotkeys", "Camera Drag Key", KeyCode.Mouse1);
        Release = config.Bind("Hotkeys", "Cursor Release Key", KeyCode.LeftControl);
        Zoom = config.Bind("Hotkeys", "Zoom Key", KeyCode.Z);
        Recenter = config.Bind("Hotkeys", "Recenter Key", KeyCode.Home);
        ExitPov = config.Bind("Hotkeys", "PoV Exit Key", KeyCode.Escape);
        ResetOnPoseChange = config.Bind("General", "Reset On Pose Change", true,
            "Clear mouse-look offsets and target tracking after a scene pose transition completes.");
        Stronger = config.Bind("Scene Hotkeys", "Stronger Key", KeyCode.Space);
        MaleLock = config.Bind("Scene Hotkeys", "Male Gauge Lock Key", KeyCode.D);
        FemaleLock = config.Bind("Scene Hotkeys", "Female Gauge Lock Key", KeyCode.F);
        RepeatInterval = config.Bind("Scene Hotkeys", "Stronger Repeat Interval", 0.15f,
            new ConfigDescription("Seconds between button clicks while held.", new AcceptableValueRange<float>(0.05f, 1f)));
        HideHead = config.Bind("General", "Hide Head", true, "Hide the selected head and hair throughout POV; restore them on exit or character switch.");
        LockCursor = config.Bind("General", "Lock Cursor", false, "Lock the pointer for mouse look; Left Control releases it, Escape exits POV.");
        InvertY = config.Bind("Camera", "Invert Y Axis", false);
        FollowRotation = config.Bind("Camera", "Follow Head Rotation", true, "Apply mouse-look angles relative to the current animated head orientation. Disable for the legacy captured orientation. Scene pose changes recenter the view and clear target tracking.");
        FollowPosition = config.Bind("Camera", "Follow Head Position", true, "Follow the animated eye position. Disable to keep the position captured on entry or Home.");
        Sensitivity = Number("Camera Sensitivity", 2f, 0.01f, 20f);
        Fov = Number("Field of View", 60f, 10f, 120f);
        ZoomFov = Number("Zoom Field of View", 20f, 1f, 120f);
        NearClip = Number("Near Clip Plane", 0.01f, 0.001f, 0.3f);
        OffsetX = Number("Offset X", 0f, -1f, 1f);
        OffsetY = Number("Offset Y", 0f, -1f, 1f);
        OffsetZ = Number("Offset Z", 0.02f, -1f, 1f);
        PitchLimit = Number("Pitch Limit", 80f, 0f, 89f);
        YawLimit = Number("Yaw Limit", 90f, 0f, 180f);

        ConfigEntry<float> Number(string name, float value, float min, float max) =>
            config.Bind("Camera", name, value, new ConfigDescription(name, new AcceptableValueRange<float>(min, max)));
    }
}
