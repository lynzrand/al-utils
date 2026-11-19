extern alias unity;

using Character;
using unity::UnityEngine;
using unity::UnityEngine.SceneManagement;

namespace AL_VR;

// Initialize from the player's eyes once per scene, after the rig is ready.
// The fixed anchor leaves subsequent head motion entirely to headset tracking.
internal sealed class PlayerView
{
    private Human? player;
    private Transform? head;
    private int? sceneHandle;
    private bool initialized;
    private readonly AL_PovX.PoseChangeTracker poseChanges = new();
    private int? viewpoint;
    private bool? normalCamera;
    private IntPtr cameraPointer;
    private readonly Dictionary<int, (Renderer Renderer, bool Hidden)> hidden = new();
    internal Vector3 Position { get; private set; }
    internal Quaternion Heading { get; private set; }

    internal bool Update(Camera source, out bool changed)
    {
        changed = false;
        int scene = SceneManager.GetActiveScene().handle;
        if (sceneHandle != scene)
        {
            changed = initialized;
            initialized = false;
            player = null;
            head = null;
            sceneHandle = scene;
            poseChanges.Clear();
            viewpoint = null;
            normalCamera = null;
        }
        if (cameraPointer != source.Pointer)
        {
            cameraPointer = source.Pointer;
            initialized = false;
        }
        var hScene = AL.H.HScene._instance;
        if (hScene && hScene.Loaded && !hScene.IsDisposed && !hScene.IsEnded)
        {
            var selected = hScene.SelectedData;
            if (poseChanges.Observe(hScene.Pointer.ToInt64(), selected.Item1, selected.Item2,
                hScene.NowChangedPosture, hScene.NowChangeAnimation) ||
                viewpoint != AL.H.HScene._cameraIndex || normalCamera != hScene.IsNormalCamera)
                initialized = false;
            viewpoint = AL.H.HScene._cameraIndex;
            normalCamera = hScene.IsNormalCamera;
            // Wait for the new rig pose to settle before sampling the eyes.
            if (hScene.NowChangeAnimation) return head != null;
        }
        else
        {
            poseChanges.Clear();
            viewpoint = null;
            normalCamera = null;
        }
        if (initialized) return true;
        var next = Manager.Game._instance?.Player?.Human;
        if (next == null || next.Disposed || next.IsReloading || !next.GameObject ||
            !next.GameObject.activeInHierarchy || !next.IsActiveAndEnabled || !next.Face?.objHeadBone)
            next = null;
        var nextHead = next?.Face!.objHeadBone.transform;
        player = next;
        head = nextHead;
        if (!head || player == null) return false;
        var eyes = player.Face!.eyeLookCtrl?.EyeLookScript?.EyeObjs;
        var left = eyes != null && eyes.Length > 0 ? eyes[0]?.EyeTransform : null;
        var right = eyes != null && eyes.Length > 1 ? eyes[1]?.EyeTransform : null;
        Position = left && right ? (left!.position + right!.position) * 0.5f : head!.position;
        var forward = head!.forward;
        Heading = Quaternion.Euler(0, Mathf.Atan2(forward.x, forward.z) * Mathf.Rad2Deg, 0);
        initialized = changed = true;
        return true;
    }

    internal void Reset()
    {
        RestoreHead();
        sceneHandle = null;
        initialized = false;
        player = null;
        head = null;
        poseChanges.Clear();
        viewpoint = null;
        normalCamera = null;
        cameraPointer = IntPtr.Zero;
    }

    internal void RequestReset() => initialized = false;

    internal void HideHead(Vector3 viewPosition, float radius)
    {
        if (player == null || player.Disposed || !head) return;
        if ((viewPosition - head!.position).sqrMagnitude > radius * radius) return;
        HideUnder(head!.gameObject);
        HideUnder(player.Face.objHead);
        var hairs = player.Hair?.Hairs;
        if (hairs != null)
            foreach (var hair in hairs)
                if (hair != null && !hair.IsDisposed) HideUnder(hair.Obj);
    }

    private void HideUnder(GameObject? root)
    {
        if (!root) return;
        foreach (var renderer in root!.GetComponentsInChildren<Renderer>(true))
        {
            int id = renderer.GetInstanceID();
            if (!hidden.ContainsKey(id)) hidden.Add(id, (renderer, renderer.forceRenderingOff));
            renderer.forceRenderingOff = true;
        }
    }

    internal void RestoreHead()
    {
        foreach (var state in hidden.Values)
            if (state.Renderer) state.Renderer.forceRenderingOff = state.Hidden;
        hidden.Clear();
    }
}
