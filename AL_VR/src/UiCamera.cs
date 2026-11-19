extern alias unity;

using UnityEngine;
using UnityEngine.Rendering.Universal;
using unity::UnityEngine;
using unity::UnityEngine.Rendering;
using Object = unity::UnityEngine.Object;

namespace AL_VR;

// Render screen-space canvases separately after the desktop frame. Restore their
// cameras and layers before the next input update so desktop raycasts still work.
internal sealed class UiCamera : IDisposable
{
    private readonly GameObject owner = new("AL SteamVR UI Camera");
    private readonly Camera camera;
    private readonly List<(Canvas Canvas, RenderMode Mode, Camera? Camera, float Distance)> canvases = new();
    private readonly List<(GameObject Object, int Layer)> layers = new();

    internal UiCamera()
    {
        Object.DontDestroyOnLoad(owner);
        camera = owner.AddComponent<Camera>();
        camera.enabled = false;
        camera.orthographic = true;
        camera.nearClipPlane = 0.01f;
        camera.farClipPlane = 10;
        camera.clearFlags = CameraClearFlags.SolidColor;
        camera.backgroundColor = Color.clear;
        camera.allowHDR = camera.allowMSAA = false;
        var urp = owner.AddComponent<UniversalAdditionalCameraData>();
        urp.renderPostProcessing = urp.renderShadows = urp.allowXRRendering = false;
        urp.requiresColorOption = urp.requiresDepthOption = CameraOverrideOption.Off;
    }

    internal void Render(RenderTexture target)
    {
        // Borrow a layer with no scene geometry for this synchronous render only.
        // CanvasRenderer is separate from Renderer, so UI does not occupy it yet.
        uint occupied = 0;
        foreach (var renderer in Object.FindObjectsOfType<Renderer>())
            occupied |= 1u << renderer.gameObject.layer;
        foreach (var terrain in Terrain.activeTerrains)
            occupied |= 1u << terrain.gameObject.layer;
        if (occupied == uint.MaxValue)
            throw new InvalidOperationException("No geometry-free layer is available for the VR UI camera.");
        int layer = System.Numerics.BitOperations.TrailingZeroCount(~occupied);
        camera.cullingMask = 1 << layer;
        camera.targetTexture = target;
        camera.aspect = (float)target.width / target.height;
        camera.orthographicSize = target.height * 0.5f;
        try
        {
            foreach (var canvas in Object.FindObjectsOfType<Canvas>())
            {
                if (!canvas.isActiveAndEnabled || !canvas.isRootCanvas || canvas.renderMode == RenderMode.WorldSpace)
                    continue;
                // Offscreen canvases belong to in-world displays, not the game UI.
                if (canvas.renderMode == RenderMode.ScreenSpaceCamera && canvas.worldCamera && canvas.worldCamera.targetTexture)
                    continue;
                canvases.Add((canvas, canvas.renderMode, canvas.worldCamera, canvas.planeDistance));
                foreach (var transform in canvas.GetComponentsInChildren<Transform>(true))
                {
                    var item = transform.gameObject;
                    layers.Add((item, item.layer));
                    item.layer = layer;
                }
                canvas.renderMode = RenderMode.ScreenSpaceCamera;
                canvas.worldCamera = camera;
                canvas.planeDistance = 1;
            }
            Canvas.ForceUpdateCanvases();
            RenderPipeline.SubmitRenderRequest(camera, new UniversalRenderPipeline.SingleCameraRequest { destination = target });
        }
        finally
        {
            foreach (var state in canvases)
                if (state.Canvas)
                {
                    state.Canvas.renderMode = state.Mode;
                    state.Canvas.worldCamera = state.Camera;
                    state.Canvas.planeDistance = state.Distance;
                }
            foreach (var state in layers)
                if (state.Object) state.Object.layer = state.Layer;
            canvases.Clear();
            layers.Clear();
            camera.targetTexture = null;
            Canvas.ForceUpdateCanvases();
        }
    }

    public void Dispose() => Object.Destroy(owner);
}
