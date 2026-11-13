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
    private Camera? source;
    private bool sessionStarted, recenterRequested, loggedSubmit;
    private Vector3 trackingOrigin;
    private Quaternion trackingHeadingInverse;
    private IntPtr submitCallback;
    private bool leftRendered, rightRendered;
    private Il2CppSystem.Action<ScriptableRenderContext, Camera>? onEyeRendered;
    private readonly string? smokeLibrary = Environment.GetEnvironmentVariable("AL_VR_SMOKE_RUNTIME");
    private bool smokeStarted, previousRunInBackground;
    private float smokeDeadline;
    private Camera? smokeSource;
    private bool restoreBackground;

    public void Start()
    {
        onEyeRendered = (Il2CppSystem.Action<ScriptableRenderContext, Camera>)AfterCamera;
        RenderPipelineManager.add_endCameraRendering(onEyeRendered);
    }

    public void LateUpdate()
    {
        try
        {
            bool toggle = Application.isFocused && Input.GetKeyDown(Plugin.Instance.Toggle.Value);
            if (!sessionStarted && !toggle && (smokeLibrary == null || smokeStarted))
                return;

            var main = Camera.main;
            bool canRender = IsStereoSource(main);
            if (!canRender && smokeLibrary != null && (!smokeStarted || sessionStarted) &&
                GraphicsSettings.currentRenderPipeline?.TryCast<UniversalRenderPipelineAsset>() != null)
            {
                // Title screens can switch between cameras that only render UI.
                // Use a dedicated perspective source for the integration smoke.
                if (!smokeSource)
                {
                    var owner = new GameObject("AL SteamVR Smoke Source");
                    Object.DontDestroyOnLoad(owner);
                    smokeSource = owner.AddComponent<Camera>();
                    smokeSource.enabled = false;
                }
                main = smokeSource;
                canRender = true;
            }
            if (toggle && sessionStarted)
            {
                StopSession();
                return;
            }

            if (gamePanel?.Update(Application.isFocused) == true)
                recenterRequested = true;
            if (sessionStarted && smokeStarted && FinishSmoke())
                return;
            if (!canRender)
            {
                DisableEyes();
                if (toggle)
                    Plugin.Instance.Log.LogInfo("AL SteamVR needs an active perspective camera in URP. Try again after loading a scene.");
                return;
            }
            if (!sessionStarted)
            {
                smokeStarted = smokeLibrary != null;
                StartSession(smokeLibrary ?? Plugin.Instance.OpenVrLibrary.Value);
            }

            if (source != main || (Application.isFocused && Input.GetKeyDown(Plugin.Instance.Recenter.Value)))
                recenterRequested = true;
            source = main;
            PrepareFrame(main!);
        }
        catch (Exception error)
        {
            Fail(error);
        }
    }

    [HideFromIl2Cpp]
    private static bool IsStereoSource(Camera? camera) => camera && camera!.isActiveAndEnabled && !camera.orthographic &&
        GraphicsSettings.currentRenderPipeline?.TryCast<UniversalRenderPipelineAsset>() != null;

    [HideFromIl2Cpp]
    private void StartSession(string library)
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
        gamePanel = new GamePanel(submitCallback);
        this.StartCoroutine(gamePanel.CaptureFrames());
        if (smokeStarted)
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
    private void PrepareFrame(Camera main)
    {
        DisableEyes();
        int result = OpenVr.AlVrBeginFrame(out var trackedHead);
        if (result < 0)
            throw new InvalidOperationException(OpenVr.LastError());
        if (result == 0)
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
        if (recenterRequested)
        {
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
        var trackingToWorld = gameHeading * trackingHeadingInverse;
        float worldScale = Plugin.Instance.WorldUnitsPerMeter.Value;
        var headPosition = cameraTransform.position + trackingToWorld * ((trackedHead.Position - trackingOrigin) * worldScale);
        var headRotation = trackingToWorld * rotation;
        var sourceUrp = main.GetComponent<UniversalAdditionalCameraData>();
        left.SetView(main, sourceUrp, headPosition, headRotation, worldScale, main.depth - 2);
        right!.SetView(main, sourceUrp, headPosition, headRotation, worldScale, main.depth - 1);
    }

    [HideFromIl2Cpp]
    private bool FinishSmoke()
    {
        ulong submitted = OpenVr.AlVrSubmittedFrames();
        bool panelReady = OpenVr.AlVrPanelReady() != 0;
        if (submitted >= 30 && panelReady)
        {
            Plugin.Instance.Log.LogInfo($"AL SteamVR smoke passed: {submitted} stereo frames and a game panel accepted by the test compositor.");
            StopSession();
            return true;
        }
        if (Time.unscaledTime >= smokeDeadline)
            throw new InvalidOperationException($"Smoke timed out after {submitted} stereo frames. Game panel submitted: {panelReady}.");
        if (submitted > 0 && !gamePanel!.IsOpen && gamePanel.OpenAtHead() < 0)
            throw new InvalidOperationException("The smoke runtime could not open the game panel.");
        return false;
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
        if (smokeSource) Object.Destroy(smokeSource!.gameObject);
        smokeSource = null;
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
    }

    public void OnDestroy() => Shutdown();
    public void OnGUI() => gamePanel?.DrawPointer();
    public void OnApplicationFocus(bool focused) { if (!focused) gamePanel?.SuspendInput(); }
}
