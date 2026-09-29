extern alias unity;
using Character;
using Il2CppInterop.Runtime.Attributes;
using unity::UnityEngine;
using unity::UnityEngine.Rendering;
using Input = UnityEngine.Input;

namespace AL_PovX;

public sealed class PovController : MonoBehaviour
{
    public PovController(IntPtr pointer) : base(pointer) { }

    private Settings S { [HideFromIl2Cpp] get => Plugin.Instance.Settings; }
    private Human? target;
    private Transform? head;
    private Transform? leftEye;
    private Transform? rightEye;
    private Camera? camera;
    private bool active, released, cursorOwned, subscribed, rendering;
    private CursorLockMode savedLock;
    private bool savedCursor;
    private float pitch, yaw;
    private Vector3 savedPosition, initialEyes;
    private Quaternion savedRotation, initialRotation;
    private Quaternion lastViewRotation;
    private bool hasViewRotation;
    private readonly PoseChangeTracker poseChanges = new();
    private AL.H.HScene? aimScene;
    private float savedFov, savedNearClip;
    private readonly Dictionary<int, (Renderer Renderer, bool ForceRenderingOff)> hiddenRenderers = new();
    private Il2CppSystem.Action<ScriptableRenderContext, Camera>? beginRender, endRender;

    public void Start()
    {
        // Keep the exact native delegates alive so unloading can unsubscribe them.
        beginRender = (Il2CppSystem.Action<ScriptableRenderContext, Camera>)BeforeRender;
        endRender = (Il2CppSystem.Action<ScriptableRenderContext, Camera>)AfterRender;
        RenderPipelineManager.add_beginCameraRendering(beginRender);
        RenderPipelineManager.add_endCameraRendering(endRender);
        subscribed = true;
        Plugin.Instance.Log.LogInfo("POV render callbacks registered.");
    }

    public void Update()
    {
        try
        {
            // Recover even if a render was interrupted before its end callback.
            RestoreRender();
            if (active && (!Valid(target) || !head || target!.IsReloading || Camera.main != camera))
                StopPov();
            if (active) UpdateHeadVisibility();

            if (!Application.isFocused) return;
            if (active && Input.GetKeyDown(S.ExitPov.Value)) { StopPov(); return; }
            if (IsTyping()) return;
            if (Input.GetKeyDown(S.Toggle.Value))
            {
                if (active) StopPov();
                else StartPov();
            }
            if (!active) return;
            if (Input.GetKeyDown(S.Cycle.Value)) CycleTarget();
            if (!active) return;
            if (Input.GetKeyDown(S.Recenter.Value)) ResetLook();
            if (Input.GetKeyDown(S.Release.Value)) released = !released;
            UpdateCursor();
            if (Time.timeScale == 0) return;
            UpdateAimShortcut();

            if (!released && (S.LockCursor.Value || Input.GetKey(S.Drag.Value)))
            {
                float sensitivity = S.Sensitivity.Value;
                if (Input.GetKey(S.Zoom.Value)) sensitivity *= S.ZoomFov.Value / S.Fov.Value;
                float mouseX = Input.GetAxisRaw("Mouse X");
                float mouseY = Input.GetAxisRaw("Mouse Y");
                if (mouseX != 0 || mouseY != 0) ReleaseAim();
                pitch = Math.Clamp(pitch + mouseY * sensitivity * (S.InvertY.Value ? 1 : -1), -S.PitchLimit.Value, S.PitchLimit.Value);
                yaw += mouseX * sensitivity;
                yaw = S.FollowRotation.Value ? Math.Clamp(yaw, -S.YawLimit.Value, S.YawLimit.Value) : Mathf.Repeat(yaw + 180, 360) - 180;
            }
        }
        catch (Exception error) { Fail(error); }
    }

    [HideFromIl2Cpp]
    internal static bool IsTyping()
    {
        var events = UnityEngine.EventSystems.EventSystem.current;
        var selected = events ? events.currentSelectedGameObject : null;
        if (!selected) return false;
        var text = selected!.GetComponent<TMPro.TMP_InputField>();
        if (text && text.isFocused) return true;
        var legacy = selected.GetComponent<UnityEngine.UI.InputField>();
        return legacy && legacy.isFocused;
    }

    [HideFromIl2Cpp]
    private static bool Valid(Human? human) => human != null && !human.Disposed && !human.IsReloading &&
        human.GameObject && human.GameObject.activeInHierarchy && human.IsActiveAndEnabled && human.Face?.objHeadBone;

    [HideFromIl2Cpp]
    private static List<Human> Targets()
    {
        var result = new List<Human>();
        // Use the game's registry: Human is an IL2CPP object, not a MonoBehaviour.
        var humans = Human.List;
        if (humans == null) return result;
        int count = humans.Cast<Il2CppSystem.Collections.Generic.IReadOnlyCollection<Human>>().Count;
        for (int i = 0; i < count; i++)
            if (Valid(humans[i])) result.Add(humans[i]);
        result.Sort((a, b) => a.GameObject.GetInstanceID().CompareTo(b.GameObject.GetInstanceID()));
        var player = Manager.Game._instance?.Player?.Human;
        int playerIndex = result.FindIndex(h => player != null && h.Pointer == player.Pointer);
        if (playerIndex > 0)
        {
            var first = result[playerIndex];
            result.RemoveAt(playerIndex);
            result.Insert(0, first);
        }
        return result;
    }

    [HideFromIl2Cpp]
    private void StartPov()
    {
        var candidates = Targets();
        var main = Camera.main;
        if (!main || candidates.Count == 0)
        {
            Plugin.Instance.Log.LogInfo("POV unavailable: no active character or main camera. Enter a scene and try again.");
            return;
        }
        camera = main;
        SelectTarget(candidates[0]);
        savedLock = Cursor.lockState;
        savedCursor = Cursor.visible;
        released = false;
        active = true;
        UpdateHeadVisibility();
        Plugin.Instance.Log.LogInfo("POV enabled; Period switches characters, Escape exits.");
    }

    [HideFromIl2Cpp]
    private void SelectTarget(Human human)
    {
        RestoreRender();
        RestoreHead();
        target = human;
        head = human.Face.objHeadBone.transform;
        var eyes = human.Face.eyeLookCtrl?.EyeLookScript?.EyeObjs;
        leftEye = eyes != null && eyes.Length > 0 ? eyes[0]?.EyeTransform : null;
        rightEye = eyes != null && eyes.Length > 1 ? eyes[1]?.EyeTransform : null;
        ResetLook();
        if (active) UpdateHeadVisibility();
        Plugin.Instance.Log.LogInfo($"POV target: {human.Name}; eye tracking: {(leftEye && rightEye ? "both eyes" : "head fallback")}");
    }

    private void ResetLook()
    {
        hasViewRotation = false;
        aimScene = null;
        pitch = yaw = 0;
        initialEyes = EyePosition();
        initialRotation = head ? head!.rotation : Quaternion.identity;
    }

    private void UpdateAimShortcut()
    {
        if (!Input.GetKeyDown(KeyCode.Q) && !Input.GetKeyDown(KeyCode.W) &&
            !Input.GetKeyDown(KeyCode.E) && !Input.GetKeyDown(KeyCode.R)) return;
        var scene = AL.H.HScene._instance;
        if (!scene || !scene.Loaded || scene.IsDisposed || scene.IsEnded || scene.CameraKeyUnused ||
            !scene.IsNormalCamera || scene.MainCamera != camera) return;
        // Let HScene.InputKey select the body part normally. Resolve its resulting
        // target at render time, after all native Update/LateUpdate work finishes.
        aimScene = scene;
        pitch = yaw = 0;
    }

    private void ReleaseAim()
    {
        if (aimScene == null) return;
        aimScene = null;
        pitch = yaw = 0;
        if (!hasViewRotation || !head) return;
        // Express the last aim direction in the current head frame. Do not turn
        // the tracked world orientation into a new, frozen head reference.
        var basis = S.FollowRotation.Value ? head!.rotation : initialRotation;
        var direction = Quaternion.Inverse(basis) * (lastViewRotation * Vector3.forward);
        pitch = Math.Clamp(-Mathf.Atan2(direction.y, Mathf.Sqrt(direction.x * direction.x + direction.z * direction.z)) * Mathf.Rad2Deg,
            -S.PitchLimit.Value, S.PitchLimit.Value);
        yaw = Mathf.Atan2(direction.x, direction.z) * Mathf.Rad2Deg;
        if (S.FollowRotation.Value) yaw = Math.Clamp(yaw, -S.YawLimit.Value, S.YawLimit.Value);
    }

    private void ResetForPoseChange()
    {
        var scene = AL.H.HScene._instance;
        if (!scene || !scene.Loaded || scene.IsDisposed || scene.IsEnded || scene.MainCamera != camera)
        {
            poseChanges.Clear();
            return;
        }
        var selected = scene.SelectedData;
        if (poseChanges.Observe(scene.Pointer.ToInt64(), selected.Item1, selected.Item2,
            scene.NowChangedPosture, scene.NowChangeAnimation) && S.ResetOnPoseChange.Value)
        {
            ResetLook();
            Plugin.Instance.Log.LogInfo("POV recentered after scene pose change.");
        }
    }

    [HideFromIl2Cpp]
    private bool TryAimPosition(out Vector3 position)
    {
        position = Vector3.zero;
        if (aimScene == null) return false;
        var scene = AL.H.HScene._instance;
        if (!aimScene || !scene || scene.Pointer != aimScene.Pointer || !scene.Loaded ||
            scene.IsDisposed || scene.IsEnded || !scene.IsNormalCamera || scene.MainCamera != camera)
        {
            ReleaseAim();
            return false;
        }
        var regular = scene.CameraController;
        if (!regular) { ReleaseAim(); return false; }
        var nativeTarget = regular._targetTrans;
        if (nativeTarget) position = nativeTarget.position;
        else
        {
            // CameraPos is the orbit pivot in the regular camera's base frame.
            var basis = regular.BaseTransform;
            position = basis ? basis.TransformPoint(regular.CameraPos) : regular.CameraPos;
        }
        return true;
    }

    private Vector3 EyePosition() => leftEye && rightEye
        ? (leftEye!.position + rightEye!.position) * 0.5f
        : head ? head!.position : Vector3.zero;

    private void UpdateHeadVisibility()
    {
        if (!S.HideHead.Value) { RestoreHead(); return; }
        if (target == null || !head) return;
        // Mesh hiding leaves the animated rig and eye transforms intact. Capture
        // each renderer only once, including meshes replaced during customization.
        HideUnder(head!.gameObject);
        HideUnder(target.Face.objHead);
        var hairs = target.Hair?.Hairs;
        if (hairs != null)
            foreach (var hair in hairs)
                if (hair != null && !hair.IsDisposed) HideUnder(hair.Obj);
        foreach (var entry in hiddenRenderers.Values)
            if (entry.Renderer) entry.Renderer.forceRenderingOff = true;
    }

    [HideFromIl2Cpp]
    private void HideUnder(GameObject? root)
    {
        if (!root) return;
        foreach (var renderer in root!.GetComponentsInChildren<Renderer>(true))
        {
            if (!renderer) continue;
            int id = renderer.GetInstanceID();
            if (!hiddenRenderers.ContainsKey(id))
                hiddenRenderers.Add(id, (renderer, renderer.forceRenderingOff));
            renderer.forceRenderingOff = true;
        }
    }

    private void RestoreHead()
    {
        foreach (var entry in hiddenRenderers.Values)
            if (entry.Renderer) entry.Renderer.forceRenderingOff = entry.ForceRenderingOff;
        hiddenRenderers.Clear();
    }

    public void LateUpdate()
    {
        if (!active) return;
        try { UpdateHeadVisibility(); }
        catch (Exception error) { Fail(error); }
    }

    private void CycleTarget()
    {
        var candidates = Targets();
        if (candidates.Count == 0) { StopPov(); return; }
        int index = candidates.FindIndex(h => target != null && h.Pointer == target.Pointer);
        SelectTarget(candidates[(index + 1) % candidates.Count]);
    }

    private void UpdateCursor()
    {
        if (S.LockCursor.Value && !released)
        {
            cursorOwned = true;
            Cursor.lockState = CursorLockMode.Locked;
            Cursor.visible = false;
        }
        else if (released)
        {
            cursorOwned = true;
            Cursor.lockState = CursorLockMode.None;
            Cursor.visible = true;
        }
        else RestoreCursor();
    }

    private void RestoreCursor()
    {
        if (!cursorOwned) return;
        Cursor.lockState = savedLock;
        Cursor.visible = savedCursor;
        cursorOwned = false;
    }

    [HideFromIl2Cpp]
    private void BeforeRender(ScriptableRenderContext context, Camera current)
    {
        if (!active || current != camera) return;
        try
        {
            if (!Valid(target) || !head || target!.Face.objHeadBone.transform != head)
            {
                StopPov();
                return;
            }
            if (rendering) RestoreRender();
            savedPosition = current.transform.position;
            savedRotation = current.transform.rotation;
            savedFov = current.fieldOfView;
            savedNearClip = current.nearClipPlane;
            rendering = true;

            UpdateHeadVisibility();
            // Read the new pose only after the game's animation/IK update. A
            // transition queues one reset, rather than resetting every frame.
            ResetForPoseChange();
            Vector3 eyes = S.FollowPosition.Value ? EyePosition() : initialEyes;
            Quaternion orientation = S.FollowRotation.Value ? head.rotation : initialRotation;
            var offset = new Vector3(S.OffsetX.Value, S.OffsetY.Value, S.OffsetZ.Value);
            // Positional offsets stay attached to the head even when its rotation
            // is decoupled from the viewing direction.
            Vector3 position = eyes + head.rotation * offset;
            Quaternion rotation = orientation * Quaternion.Euler(pitch, yaw, 0);
            if (TryAimPosition(out var aimPosition))
            {
                Vector3 direction = aimPosition - position;
                if (direction.sqrMagnitude > 0.000001f)
                {
                    Vector3 up = Math.Abs(Vector3.Dot(direction.normalized, Vector3.up)) > 0.999f
                        ? Vector3.forward : Vector3.up;
                    rotation = Quaternion.LookRotation(direction, up);
                }
            }
            current.transform.SetPositionAndRotation(position, rotation);
            lastViewRotation = rotation;
            hasViewRotation = true;
            current.fieldOfView = Input.GetKey(S.Zoom.Value) ? S.ZoomFov.Value : S.Fov.Value;
            current.nearClipPlane = S.NearClip.Value;
        }
        catch (Exception error) { Fail(error); }
    }

    [HideFromIl2Cpp]
    private void AfterRender(ScriptableRenderContext context, Camera current)
    {
        if (current != camera) return;
        try { RestoreRender(); }
        catch (Exception error) { Fail(error); }
    }

    private void RestoreRender()
    {
        if (!rendering) return;
        rendering = false;
        if (!camera) return;
        camera!.transform.SetPositionAndRotation(savedPosition, savedRotation);
        camera.fieldOfView = savedFov;
        camera.nearClipPlane = savedNearClip;
    }

    private void StopPov()
    {
        active = false;
        poseChanges.Clear();
        hasViewRotation = false;
        aimScene = null;
        RestoreRender();
        RestoreHead();
        RestoreCursor();
        target = null;
        head = leftEye = rightEye = null;
        camera = null;
    }

    [HideFromIl2Cpp]
    private void Fail(Exception error)
    {
        active = false;
        Plugin.Instance.Log.LogError($"POV stopped after an error: {error}");
        try { StopPov(); }
        catch (Exception cleanupError) { Plugin.Instance.Log.LogError(cleanupError); }
    }

    public void OnApplicationFocus(bool focused) { if (!focused) StopPov(); }
    public void OnDisable() => StopPov();
    public void OnDestroy() => Shutdown();

    [HideFromIl2Cpp]
    public void Shutdown()
    {
        StopPov();
        if (!subscribed) return;
        RenderPipelineManager.remove_beginCameraRendering(beginRender);
        RenderPipelineManager.remove_endCameraRendering(endRender);
        subscribed = false;
        beginRender = endRender = null;
    }
}
