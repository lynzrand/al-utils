extern alias unity;

using UnityEngine.Rendering.Universal;
using unity::UnityEngine;
using Object = unity::UnityEngine.Object;

namespace AL_VR;

internal sealed class EyeCamera : IDisposable
{
    private readonly GameObject owner;
    private readonly UniversalAdditionalCameraData urp;
    private readonly OpenVrEye eye;
    internal Camera Camera { get; }
    internal RenderTexture Target { get; }

    internal EyeCamera(string name, OpenVrEye eye, int width, int height)
    {
        this.eye = eye;
        owner = new GameObject(name);
        Object.DontDestroyOnLoad(owner);
        try
        {
            Camera = owner.AddComponent<Camera>();
            Camera.enabled = false;
            urp = owner.AddComponent<UniversalAdditionalCameraData>();
            Target = new RenderTexture(width, height, 24, RenderTextureFormat.ARGB32, RenderTextureReadWrite.Default)
            {
                name = name,
                antiAliasing = 1,
                useMipMap = false,
                autoGenerateMips = false
            };
            if (!Target.Create())
                throw new InvalidOperationException($"Unity could not allocate the {name} target ({width} × {height}).");
        }
        catch
        {
            Dispose();
            throw;
        }
    }

    internal void SetView(Camera source, UniversalAdditionalCameraData? sourceUrp, Vector3 headPosition,
        Quaternion headRotation, float worldUnitsPerMeter, float depth)
    {
        Camera.CopyFrom(source);
        Camera.targetTexture = Target;
        Camera.rect = new Rect(0, 0, 1, 1);
        Camera.depth = depth;
        Camera.allowMSAA = false;
        Camera.allowDynamicResolution = false;

        // Copy renderer selection and volume configuration, but keep each eye's
        // volume, history, and stack ownership independent of the desktop camera.
        urp.SetRenderer(sourceUrp ? sourceUrp!.m_RendererIndex : -1);
        urp.renderShadows = !sourceUrp || sourceUrp!.renderShadows;
        urp.renderPostProcessing = sourceUrp && sourceUrp!.renderPostProcessing;
        urp.volumeFrameworkUpdateMode = VolumeFrameworkUpdateMode.ViaScripting;
        urp.requiresColorOption = sourceUrp ? sourceUrp!.requiresColorOption : CameraOverrideOption.UsePipelineSettings;
        urp.requiresDepthOption = sourceUrp ? sourceUrp!.requiresDepthOption : CameraOverrideOption.UsePipelineSettings;
        urp.volumeLayerMask = sourceUrp ? sourceUrp!.volumeLayerMask : (LayerMask)1;
        urp.volumeTrigger = sourceUrp ? sourceUrp!.volumeTrigger : null;
        urp.stopNaN = sourceUrp && sourceUrp!.stopNaN;
        urp.dithering = sourceUrp && sourceUrp!.dithering;
        // Temporal AA jitters the two projection matrices independently.
        urp.antialiasing = sourceUrp && sourceUrp!.antialiasing != AntialiasingMode.TemporalAntiAliasing
            ? sourceUrp!.antialiasing : AntialiasingMode.None;
        urp.antialiasingQuality = sourceUrp ? sourceUrp!.antialiasingQuality : AntialiasingQuality.Medium;
        urp.allowXRRendering = false;

        Camera.transform.SetPositionAndRotation(headPosition + headRotation * (eye.EyeToHead.Position * worldUnitsPerMeter),
            headRotation * eye.EyeToHead.Rotation);
        Camera.ResetWorldToCameraMatrix();
        Camera.ResetCullingMatrix();
        Camera.projectionMatrix = eye.Projection(Camera.nearClipPlane, Camera.farClipPlane);
        Camera.nonJitteredProjectionMatrix = Camera.projectionMatrix;
        Camera.enabled = true;
    }

    internal void SetNearClip(float near)
    {
        Camera.nearClipPlane = near;
        Camera.projectionMatrix = eye.Projection(near, Camera.farClipPlane);
        Camera.nonJitteredProjectionMatrix = Camera.projectionMatrix;
    }

    internal void PreparePostProcessing()
    {
        // Update our own stack before URP selects it. Shared desktop profiles
        // stay untouched, and URP cannot overwrite these exclusions afterwards.
        CameraExtensions.UpdateVolumeStack(Camera, urp);
        var stack = urp.volumeStack;
        if (stack == null) return;
        stack.GetComponent<LensDistortion>().active = false;
        stack.GetComponent<PaniniProjection>().active = false;
        stack.GetComponent<MotionBlur>().active = false;
        stack.GetComponent<DepthOfField>().active = false;
        stack.GetComponent<ChromaticAberration>().active = false;
    }

    public void Dispose()
    {
        if (Camera)
        {
            Camera.enabled = false;
            Camera.targetTexture = null;
        }
        if (Target)
            Object.Destroy(Target);
        if (owner)
            Object.Destroy(owner);
    }
}
