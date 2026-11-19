extern alias unity;

using Il2CppInterop.Runtime.Attributes;
using BepInEx.Unity.IL2CPP.Utils;
using UnityEngine.Rendering.Universal;
using unity::UnityEngine;
using unity::UnityEngine.Rendering;
using Input = UnityEngine.Input;
using Object = unity::UnityEngine.Object;

namespace AL_VR;

public sealed class VrController : MonoBehaviour
{
    public VrController(IntPtr pointer) : base(pointer) { }

    private EyeCamera? left, right;
    private GamePanel? gamePanel;
    private ControllerVisual? controllerVisual;
    private readonly PlayerView playerView = new();
    private readonly CameraGrab cameraGrab = new();
    private bool firstPerson;
    private Camera? source;
    private bool sessionStarted, recenterRequested, loggedSubmit;
    private Vector3 trackingOrigin;
    private Quaternion trackingHeadingInverse;
    private IntPtr submitCallback;
    private bool leftRendered, rightRendered;
    private Il2CppSystem.Action<ScriptableRenderContext, Camera>? onEyeRendered;
    private Il2CppSystem.Action<ScriptableRenderContext, Camera>? onEyeRendering;
    private readonly List<UnityEngine.Canvas> hiddenCanvases = new();
    private readonly string? smokeLibrary = Environment.GetEnvironmentVariable("AL_VR_SMOKE_RUNTIME");
    private bool startAtLaunch = Environment.GetCommandLineArgs().Contains(Plugin.StartupArgument, StringComparer.OrdinalIgnoreCase);
    private bool previousRunInBackground;
    private float smokeDeadline;
    private Camera? fallbackSource;
    private bool restoreBackground;

    public void Start()
    {
        onEyeRendered = (Il2CppSystem.Action<ScriptableRenderContext, Camera>)AfterCamera;
        RenderPipelineManager.add_endCameraRendering(onEyeRendered);
        onEyeRendering = (Il2CppSystem.Action<ScriptableRenderContext, Camera>)BeforeCamera;
        RenderPipelineManager.add_beginCameraRendering(onEyeRendering);
    }

    public void LateUpdate()
    {
        try
        {
            bool focused = Application.isFocused;
            bool toggle = focused && Input.GetKeyDown(Plugin.Instance.Toggle.Value);
            if (toggle && sessionStarted)
            {
                StopSession();
                return;
            }

            if (!sessionStarted && !toggle && !startAtLaunch)
                return;

            bool usesUrp = GraphicsSettings.currentRenderPipeline?.TryCast<UniversalRenderPipelineAsset>() != null;
            var main = usesUrp ? Camera.main : null;
            if (!main || !main!.isActiveAndEnabled || main.orthographic)
                main = null;
            if (!sessionStarted)
            {
                bool showPanel = startAtLaunch || main == null;
                startAtLaunch = false;
                StartSession(smokeLibrary ?? Plugin.Instance.OpenVrLibrary.Value, showPanel);
            }

            OpenVrController? hand = OpenVr.AlVrReadController(out var controller) != 0 ? controller : null;
            bool recenter = gamePanel!.Update(hand, focused);
            if (recenter || (focused && Input.GetKeyDown(Plugin.Instance.Recenter.Value)))
            {
                gamePanel.Recenter();
                playerView.RequestReset();
                recenterRequested = true;
            }
            if (smokeLibrary != null && FinishSmoke())
                return;

            var nextSource = usesUrp ? main ?? GetFallbackSource() : null;
            if (source != nextSource)
                recenterRequested = true;
            source = nextSource;
            PrepareFrame(nextSource, hand);
        }
        catch (Exception error)
        {
            Fail(error);
        }
    }

    [HideFromIl2Cpp]
    private Camera GetFallbackSource()
    {
        if (fallbackSource)
            return fallbackSource!;

        // Title and loading screens can lack a perspective main camera. Give
        // the compositor a black scene behind the panel without drawing on desktop.
        var owner = new GameObject("AL SteamVR Panel Background");
        Object.DontDestroyOnLoad(owner);
        fallbackSource = owner.AddComponent<Camera>();
        fallbackSource.enabled = false;
        fallbackSource.nearClipPlane = 0.03f;
        fallbackSource.cullingMask = 0;
        fallbackSource.clearFlags = CameraClearFlags.SolidColor;
        fallbackSource.backgroundColor = Color.black;
        return fallbackSource;
    }

    [HideFromIl2Cpp]
    private void StartSession(string library, bool showPanel)
    {
        string path = OpenVr.FindLibrary(library);
        if (OpenVr.AlVrStart(path, out var display) == 0)
            throw new InvalidOperationException(OpenVr.LastError());

        sessionStarted = true;
        float scale = Plugin.Instance.EyeResolution.Value;
        int width = Mathf.RoundToInt(display.Width * scale);
        int height = Mathf.RoundToInt(display.Height * scale);
        if (width <= 0 || height <= 0 || width > SystemInfo.maxTextureSize || height > SystemInfo.maxTextureSize)
            throw new InvalidOperationException($"SteamVR supplied an invalid target size ({width} × {height}).");

        left = new EyeCamera("AL SteamVR Left Eye", display.Left, width, height);
        right = new EyeCamera("AL SteamVR Right Eye", display.Right, width, height);
        BindTargets();
        submitCallback = OpenVr.AlVrRenderEvent();
        gamePanel = new GamePanel(submitCallback, showPanel);
        controllerVisual = new ControllerVisual();
        this.StartCoroutine(gamePanel.CaptureFrames());
        if (smokeLibrary != null)
        {
            previousRunInBackground = Application.runInBackground;
            Application.runInBackground = true;
            restoreBackground = true;
            smokeDeadline = Time.unscaledTime + 30;
        }
        recenterRequested = true;
        loggedSubmit = false;
        Plugin.Instance.Log.LogInfo($"AL SteamVR started with {width} × {height} per eye.");
    }

    [HideFromIl2Cpp]
    private void BindTargets()
    {
        if (OpenVr.AlVrSetTextures(left!.Target.GetNativeTexturePtr(), right!.Target.GetNativeTexturePtr()) == 0)
            throw new InvalidOperationException(OpenVr.LastError());
    }

    [HideFromIl2Cpp]
    private void PrepareFrame(Camera? main, OpenVrController? hand)
    {
        DisableEyes();
        int result = OpenVr.AlVrBeginFrame(out var trackedHead);
        if (result < 0)
            throw new InvalidOperationException(OpenVr.LastError());
        if (result == 0 || main == null)
            return;

        if (!loggedSubmit && OpenVr.AlVrSubmittedFrames() > 0)
        {
            Plugin.Instance.Log.LogInfo("AL SteamVR submitted its first stereo frame.");
            loggedSubmit = true;
        }

        if (!left!.Target.IsCreated() || !right!.Target.IsCreated())
        {
            if (!left.Target.Create() || !right!.Target.Create())
                throw new InvalidOperationException("Unity could not recreate the eye targets.");
            BindTargets();
        }

        Quaternion rotation = trackedHead.Rotation;
        firstPerson = playerView.Update(main, out bool playerChanged);
        recenterRequested |= playerChanged;
        if (playerChanged)
            Plugin.Instance.Log.LogInfo(firstPerson ? "AL SteamVR anchored to the player's eyes." : "AL SteamVR returned to the scene camera anchor.");
        if (recenterRequested)
        {
            cameraGrab.Reset();
            trackingOrigin = trackedHead.Position;
            var forward = rotation * Vector3.forward;
            float yaw = Mathf.Atan2(forward.x, forward.z) * Mathf.Rad2Deg;
            trackingHeadingInverse = Quaternion.Euler(0, -yaw, 0);
            recenterRequested = false;
        }

        // The game's camera supplies position and heading. Keep headset pitch
        // and roll independent of a desktop camera's orbit angle.
        var cameraTransform = main.transform;
        var gameForward = cameraTransform.forward;
        var gameHeading = Quaternion.Euler(0, Mathf.Atan2(gameForward.x, gameForward.z) * Mathf.Rad2Deg, 0);
        var anchor = firstPerson ? playerView.Position : cameraTransform.position;
        if (firstPerson) gameHeading = playerView.Heading;
        var trackingToWorld = gameHeading * trackingHeadingInverse;
        float worldScale = Plugin.Instance.WorldUnitsPerMeter.Value;
        if (gamePanel!.MoveCameraMode && Application.isFocused && hand is { HasInput: true } grab && !grab.MenuPressed)
            cameraGrab.Update(grab.Device, grab.GripPressed, grab.GripClicked, grab.GripPose.Position, grab.GripPose.Rotation,
                anchor, trackingOrigin, trackingToWorld, worldScale);
        else
            cameraGrab.Release();
        trackingToWorld = cameraGrab.Rotation(trackingToWorld);
        anchor += cameraGrab.Offset;
        var headPosition = anchor + trackingToWorld * ((trackedHead.Position - trackingOrigin) * worldScale);
        var headRotation = trackingToWorld * rotation;
        var sourceUrp = main.GetComponent<UniversalAdditionalCameraData>();
        left.SetView(main, sourceUrp, headPosition, headRotation, worldScale, main.depth - 2);
        right!.SetView(main, sourceUrp, headPosition, headRotation, worldScale, main.depth - 1);
        if (firstPerson)
        {
            left.SetNearClip(0.03f * worldScale);
            right.SetNearClip(0.03f * worldScale);
        }
        if (hand is { } controller)
        {
            int layer = main.cullingMask == 0 ? 0 : System.Numerics.BitOperations.TrailingZeroCount((uint)main.cullingMask);
            left.Camera.cullingMask |= 1 << layer;
            right.Camera.cullingMask |= 1 << layer;
            var worldOrigin = anchor - trackingToWorld * (trackingOrigin * worldScale);
            controllerVisual!.Draw(controller, gamePanel!.IsOpen, gamePanel.MoveCameraMode, left.Camera, right.Camera, worldOrigin, trackingToWorld, worldScale, layer);
        }
    }

    [HideFromIl2Cpp]
    private bool FinishSmoke()
    {
        ulong submitted = OpenVr.AlVrSubmittedFrames();
        bool panelReady = OpenVr.AlVrPanelReady() != 0;
        if (submitted >= 30 && panelReady)
        {
            UnityRenderSmoke.Run(left!, right!);
            Plugin.Instance.Log.LogInfo($"AL SteamVR smoke passed: {submitted} stereo frames and a game panel accepted by the test compositor.");
            StopSession();
            return true;
        }
        if (Time.unscaledTime >= smokeDeadline)
            throw new InvalidOperationException($"Smoke timed out after {submitted} stereo frames. Game panel submitted: {panelReady}.");
        return false;
    }

    [HideFromIl2Cpp]
    private void BeforeCamera(ScriptableRenderContext context, Camera camera)
    {
        if (left == null || right == null || (camera != left.Camera && camera != right.Camera))
            return;
        try
        {
            (camera == left.Camera ? left : right).PreparePostProcessing();
            if (firstPerson) playerView.HideHead(camera.transform.position, 0.25f * Plugin.Instance.WorldUnitsPerMeter.Value);
        }
        catch (Exception error)
        {
            Fail(error);
            return;
        }
        // Screen-space camera canvases can otherwise also appear in the eye
        // frusta. Only the panel should carry 2D UI; world-space UI stays in 3D.
        foreach (var canvas in Object.FindObjectsOfType<UnityEngine.Canvas>())
            if (canvas.isActiveAndEnabled && canvas.isRootCanvas && canvas.renderMode == UnityEngine.RenderMode.ScreenSpaceCamera)
            {
                hiddenCanvases.Add(canvas);
                // Keep the canvas hierarchy alive for the game's composite UI.
                // Overlay canvases do not render into these offscreen eye targets.
                canvas.renderMode = UnityEngine.RenderMode.ScreenSpaceOverlay;
            }
    }

    [HideFromIl2Cpp]
    private void RestoreCanvases()
    {
        playerView.RestoreHead();
        foreach (var canvas in hiddenCanvases)
            if (canvas) canvas.renderMode = UnityEngine.RenderMode.ScreenSpaceCamera;
        hiddenCanvases.Clear();
    }

    [HideFromIl2Cpp]
    private void AfterCamera(ScriptableRenderContext context, Camera camera)
    {
        if (!sessionStarted || left == null || right == null)
            return;

        // URP submits each standalone base camera before endCameraRendering.
        // Issue one graphics-thread event only after both eye passes completed.
        if (camera == left.Camera)
            leftRendered = true;
        else if (camera == right.Camera)
            rightRendered = true;
        else
            return;

        RestoreCanvases();

        if (!leftRendered || !rightRendered)
            return;

        try
        {
            leftRendered = rightRendered = false;
            int eventId = OpenVr.AlVrArmSubmit();
            if (eventId == 0)
                throw new InvalidOperationException(OpenVr.LastError());
            GL.IssuePluginEvent(submitCallback, eventId);
        }
        catch (Exception error)
        {
            Fail(error);
        }
    }

    [HideFromIl2Cpp]
    private void DisableEyes()
    {
        leftRendered = rightRendered = false;
        if (left != null)
            left.Camera.enabled = false;
        if (right != null)
            right.Camera.enabled = false;
    }

    [HideFromIl2Cpp]
    private void Fail(Exception error)
    {
        Plugin.Instance.Log.LogWarning($"AL SteamVR stopped. {error}");
        StopSession();
    }

    [HideFromIl2Cpp]
    private void StopSession()
    {
        RestoreCanvases();
        playerView.Reset();
        cameraGrab.Reset();
        firstPerson = false;
        if (fallbackSource) Object.Destroy(fallbackSource!.gameObject);
        fallbackSource = null;
        if (!sessionStarted)
            return;

        sessionStarted = false;
        if (restoreBackground)
        {
            Application.runInBackground = previousRunInBackground;
            restoreBackground = false;
        }
        gamePanel?.Dispose();
        gamePanel = null;
        controllerVisual?.Dispose();
        controllerVisual = null;
        OpenVr.AlVrStop();
        left?.Dispose();
        right?.Dispose();
        left = right = null;
        source = null;
        Plugin.Instance.Log.LogInfo("AL SteamVR session closed.");
    }

    [HideFromIl2Cpp]
    internal void Shutdown()
    {
        StopSession();
        if (onEyeRendered != null)
        {
            RenderPipelineManager.remove_endCameraRendering(onEyeRendered);
            onEyeRendered = null;
        }
        if (onEyeRendering != null)
        {
            RenderPipelineManager.remove_beginCameraRendering(onEyeRendering);
            onEyeRendering = null;
        }
    }

    public void OnDestroy() => Shutdown();
    public void OnGUI() => gamePanel?.DrawPointer();
    public void OnApplicationFocus(bool focused) { if (!focused) gamePanel?.SuspendInput(); }
}
