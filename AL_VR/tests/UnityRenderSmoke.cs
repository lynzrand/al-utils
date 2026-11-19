extern alias unity;

using UnityEngine;
using UnityEngine.UI;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering;
using unity::UnityEngine;
using Object = unity::UnityEngine.Object;

namespace AL_VR;

internal static class UnityRenderSmoke
{
    internal static void Run(EyeCamera left, EyeCamera right)
    {
        CheckProjection(left.Camera, -1.2f, 0.9f);
        CheckProjection(right.Camera, -0.9f, 1.2f);
        CheckCameraGrab();
        CheckPoseChanges();
        CheckPostProcessing(left, right);
        var existing = Object.FindObjectsOfType<Canvas>().Where(canvas => canvas.isActiveAndEnabled && canvas.isRootCanvas).ToArray();
        using var capture = new UiCamera();
        var target = new RenderTexture(128, 128, 24, RenderTextureFormat.ARGB32);
        var pixels = new Texture2D(128, 128, TextureFormat.RGBA32, false);
        var root = new GameObject("VR UI smoke canvas");
        var child = new GameObject("VR UI smoke image");
        var scene = GameObject.CreatePrimitive(PrimitiveType.Cube);
        var desktop = new GameObject("VR UI smoke desktop camera");
        var previous = RenderTexture.active;
        try
        {
            foreach (var existingCanvas in existing) existingCanvas.gameObject.SetActive(false);
            var desktopCamera = desktop.AddComponent<Camera>();
            desktopCamera.enabled = false;
            var canvas = root.AddComponent<Canvas>();
            child.transform.SetParent(root.transform, false);
            var image = child.AddComponent<RawImage>();
            image.texture = Texture2D.whiteTexture;
            image.rectTransform.sizeDelta = new Vector2(64, 64);
            image.rectTransform.anchorMin = image.rectTransform.anchorMax = new Vector2(0.5f, 0.5f);
            image.rectTransform.anchoredPosition = Vector2.zero;
            scene.transform.position = new Vector3(0, 0, 3);
            scene.transform.localScale = new Vector3(1000, 1000, 1);
            target.Create();
            foreach (var mode in new[] { RenderMode.ScreenSpaceOverlay, RenderMode.ScreenSpaceCamera })
            {
                canvas.renderMode = mode;
                canvas.worldCamera = desktopCamera;
                canvas.planeDistance = 2;
                capture.Render(target);
                if (canvas.renderMode != mode || canvas.worldCamera != desktopCamera || canvas.planeDistance != 2 ||
                    root.layer != 0 || child.layer != 0)
                    throw new InvalidOperationException("UI capture did not restore canvas state.");
                RenderTexture.active = target;
                pixels.ReadPixels(new Rect(0, 0, 128, 128), 0, 0);
                pixels.Apply();
                var center = pixels.GetPixel(64, 64);
                var corner = pixels.GetPixel(2, 2);
                if (center.r < 0.9f || center.a < 0.9f || corner.a > 0.01f)
                    throw new InvalidOperationException($"UI-only capture failed for {mode}: center={center}, corner={corner}.");
            }
            Plugin.Instance.Log.LogInfo("AL SteamVR render checks passed: camera grab/release/yaw, pose-change reset timing, asymmetric eye projections, isolated VR post-processing, UI pixels, transparent scene exclusion, and canvas restoration.");
        }
        finally
        {
            foreach (var canvas in existing)
                if (canvas) canvas.gameObject.SetActive(true);
            RenderTexture.active = previous;
            Object.Destroy(root);
            Object.Destroy(scene);
            Object.Destroy(desktop);
            Object.Destroy(target);
            Object.Destroy(pixels);
        }
    }

    private static void CheckProjection(Camera camera, float left, float right)
    {
        // Independent reference: Valve's IVRSystem::GetProjectionRaw
        // ComposeProjection formula, including its counterintuitive Y naming.
        // Do not derive expected rays by reversing our Frustum arguments.
        const float top = -1.0f, bottom = 0.85f;
        foreach (float x in new[] { -0.6f, 0, 0.6f })
            foreach (float y in new[] { -0.6f, 0, 0.6f })
            {
                var world = camera.transform.TransformPoint(new Vector3(x, y, 1));
                var actual = camera.WorldToViewportPoint(world);
                float expectedX = 0.5f + 0.5f * (2 * x - (right + left)) / (right - left);
                float expectedY = 0.5f + 0.5f * (2 * y - (bottom + top)) / (bottom - top);
                if (Mathf.Abs(actual.x - expectedX) > 0.001f || Mathf.Abs(actual.y - expectedY) > 0.001f)
                    throw new InvalidOperationException($"Eye ray disagrees with Valve projection: actual={actual}, expected=({expectedX}, {expectedY}).");
            }
    }

    private static void CheckPostProcessing(EyeCamera left, EyeCamera right)
    {
        var owner = new GameObject("VR volume smoke");
        var sourceOwner = new GameObject("VR post-processing source");
        var profile = ScriptableObject.CreateInstance<VolumeProfile>();
        try
        {
            var volume = owner.AddComponent<Volume>();
            volume.isGlobal = true;
            volume.priority = 10000;
            volume.sharedProfile = profile;
            var bloom = profile.Add<Bloom>(true);
            bloom.intensity.value = 2;
            var lens = profile.Add<LensDistortion>(true);
            lens.intensity.value = 0.7f;
            var source = sourceOwner.AddComponent<Camera>();
            source.enabled = false;
            source.cullingMask = 0;
            var data = sourceOwner.AddComponent<UniversalAdditionalCameraData>();
            data.renderPostProcessing = true;
            data.volumeLayerMask = (LayerMask)1;
            foreach (var eye in new[] { left, right })
            {
                eye.SetView(source, data, Vector3.zero, Quaternion.identity, 1, -1);
                eye.PreparePostProcessing();
                var eyeData = eye.Camera.GetComponent<UniversalAdditionalCameraData>();
                var stack = eyeData.volumeStack;
                if (!eyeData.renderPostProcessing || stack == null ||
                    stack.GetComponent<LensDistortion>().active || stack.GetComponent<MotionBlur>().active ||
                    stack.GetComponent<DepthOfField>().active || stack.GetComponent<PaniniProjection>().active ||
                    stack.GetComponent<ChromaticAberration>().active ||
                    Mathf.Abs(stack.GetComponent<Bloom>().intensity.value - 2) > 0.001f)
                    throw new InvalidOperationException("VR volume stack did not preserve bloom and exclude distortion/blur.");
                unity::UnityEngine.Rendering.RenderPipeline.SubmitRenderRequest(eye.Camera,
                    new UniversalRenderPipeline.SingleCameraRequest { destination = eye.Target });
            }
            if (!lens.active || lens.intensity.value != 0.7f || !bloom.active ||
                left.Camera.GetComponent<UniversalAdditionalCameraData>().volumeStack.Pointer ==
                right.Camera.GetComponent<UniversalAdditionalCameraData>().volumeStack.Pointer)
                throw new InvalidOperationException("VR post-processing changed the source profile or shared eye stacks.");
        }
        finally
        {
            Object.Destroy(owner);
            Object.Destroy(sourceOwner);
            Object.Destroy(profile);
        }
    }

    private static void CheckCameraGrab()
    {
        var grab = new CameraGrab();
        var anchor = new Vector3(10, 2, -3);
        var origin = new Vector3(0, 1, 0);
        var hand = new Vector3(0.3f, 0.8f, 0.5f);
        var basis = Quaternion.Euler(0, 30, 0);
        var grabbedPoint = anchor + basis * (hand - origin);
        grab.Update(1, true, true, hand, Quaternion.identity, anchor, origin, basis, 1);
        hand += new Vector3(0.2f, 0.1f, -0.3f);
        grab.Update(1, true, false, hand, Quaternion.Euler(0, 45, 0), anchor, origin, basis, 1);
        var actual = anchor + grab.Offset + grab.Rotation(basis) * (hand - origin);
        if ((actual - grabbedPoint).sqrMagnitude > 0.000001f || Mathf.Abs(grab.Yaw + 45) > 0.001f)
            throw new InvalidOperationException("Camera grab did not keep the world point fixed under translation/yaw.");
        var saved = grab.Offset;
        grab.Release();
        grab.Update(2, true, false, hand + Vector3.one, Quaternion.identity, anchor, origin, basis, 1);
        if ((saved - grab.Offset).sqrMagnitude > 0.000001f)
            throw new InvalidOperationException("Held grip moved the camera after release or handoff without a new press.");
        grab.Reset();
        if (grab.Offset.sqrMagnitude > 0 || grab.Yaw != 0)
            throw new InvalidOperationException("Camera offsets survived recenter.");
    }

    private static void CheckPoseChanges()
    {
        var tracker = new AL_PovX.PoseChangeTracker();
        if (tracker.Observe(1, 0, 0, false, false) || tracker.Observe(1, 0, 1, true, true) ||
            !tracker.Observe(1, 0, 1, true, false) || tracker.Observe(1, 0, 1, true, false))
            throw new InvalidOperationException("Pose changes must reinitialize once after the transition settles.");
    }
}
