extern alias unity;

using System.Collections;
using UnityEngine;
using unity::UnityEngine;
using Object = unity::UnityEngine.Object;

namespace AL_VR;

internal sealed class GamePanel(IntPtr renderEvent, bool showOnStart) : IDisposable
{
    private readonly GameWindowMouse mouse = new();
    private readonly UiCamera uiCamera = new();
    private RenderTexture? target;
    private IntPtr nativeTexture;
    private uint? device;
    private bool openRequested = showOnStart;
    private bool open, disposed, pointing;
    private bool menuStarted, grabbing;
    private float menuDownAt, wheel;
    private Vector2 pointer;
    internal bool IsOpen => open;
    internal bool MoveCameraMode { get; private set; }

    // Returns true when the controller requests a headset recenter.
    internal bool Update(OpenVrController? controller, bool focused)
    {
        // Startup waits for a tracked controller so the panel always appears
        // within reach of the hand that will operate it.
        if (openRequested)
            openRequested = OpenAtController() == 0;

        if (!focused || controller is not { HasInput: true } input)
        {
            SuspendInput();
            return false;
        }

        if (device != input.Device)
        {
            ResetPointerInput();
            device = input.Device;
        }

        bool recenter = false;
        if (input.ModeClicked)
        {
            ResetPointerInput();
            MoveCameraMode = !MoveCameraMode;
            Plugin.Instance.Log.LogInfo(MoveCameraMode ? "AL SteamVR grip mode: move camera (amber ray)." : "AL SteamVR grip mode: move panel (blue ray).");
        }
        float now = Time.unscaledTime;
        if (input.MenuClicked)
        {
            menuDownAt = now;
            menuStarted = true;
        }
        if (menuStarted && now - menuDownAt >= 0.75f)
        {
            menuStarted = false;
            recenter = true;
        }
        if (!input.MenuPressed && menuStarted)
        {
            menuStarted = false;
            if (open)
                Close();
            else
                openRequested = !openRequested;
        }
        else
            UpdatePointer(input);
        return recenter;
    }

    internal void Recenter()
    {
        if (open)
            openRequested = true;
    }

    private int OpenAtController()
    {
        mouse.Release();
        pointing = false;
        wheel = 0;
        grabbing = false;
        int result = OpenVr.AlVrOpenPanel();
        if (result < 0)
            Disable("SteamVR could not open the game panel.");
        else if (result > 0)
            open = true;
        return result;
    }

    private void UpdatePointer(OpenVrController input)
    {
        bool menu = input.MenuPressed;
        pointing = open && !menu && input.PointsAtPanel;
        if (MoveCameraMode && input.GripPressed)
        {
            mouse.Release();
            wheel = 0;
            return;
        }
        if (!MoveCameraMode && pointing && input.GripClicked) grabbing = true;
        if (grabbing)
        {
            mouse.Release();
            wheel = 0;
            int result = OpenVr.AlVrDragPanel(input.Device, input.GripPressed && !menu ? 1 : 0);
            grabbing = result > 0;
            if (result < 0) Disable("SteamVR could not move the game panel.");
            return;
        }
        bool canClick = pointing && GameWindowMouse.Move(input.PanelX, input.PanelY);
        if (!pointing && open && !menu && mouse.IsDragging &&
            float.IsFinite(input.PanelX) && float.IsFinite(input.PanelY))
            GameWindowMouse.Move(input.PanelX, input.PanelY);
        if (!input.TriggerPressed || menu) mouse.ReleaseLeft();
        if (!input.SecondaryPressed || menu) mouse.ReleaseRight();
        if (pointing)
            pointer = new Vector2(input.PanelX, input.PanelY);
        if (!canClick)
        {
            wheel = 0;
            return;
        }

        if (input.TriggerClicked) mouse.PressLeft();
        if (input.SecondaryClicked) mouse.PressRight();

        float scroll = input.Scroll;
        if (Mathf.Abs(scroll) < 0.35f || !float.IsFinite(scroll))
            wheel = 0;
        else
        {
            wheel += scroll * Mathf.Min(Time.unscaledDeltaTime, 0.05f) * 12;
            int steps = (int)wheel;
            if (steps != 0)
            {
                GameWindowMouse.Scroll(steps);
                wheel -= steps;
            }
        }
    }

    internal void SuspendInput()
    {
        if (device.HasValue)
            OpenVr.AlVrSuspendControllerInput();
        device = null;
        ResetPointerInput();
    }

    private void ResetPointerInput()
    {
        if (grabbing) OpenVr.AlVrDragPanel(0, 0);
        grabbing = false;
        mouse.Release();
        menuStarted = pointing = false;
        wheel = 0;
    }

    internal IEnumerator CaptureFrames()
    {
        // Capture after desktop rendering so temporary canvas changes cannot
        // affect the game's camera passes or this frame's input processing.
        var endOfFrame = new WaitForEndOfFrame();
        while (!disposed)
        {
            yield return endOfFrame;
            if (disposed || !open)
                continue;

            try
            {
                CaptureFrame();
            }
            catch (Exception error)
            {
                Disable(error.Message);
            }
        }
    }

    private void CaptureFrame()
    {
        int width = Screen.width, height = Screen.height;
        if (width <= 0 || height <= 0)
            return;
        if (!target || target!.width != width || target.height != height || !target.IsCreated())
        {
            if (target) Object.Destroy(target);
            target = new RenderTexture(width, height, 24, RenderTextureFormat.ARGB32) { name = "AL SteamVR Game Panel" };
            if (!target.Create())
                throw new InvalidOperationException("Unity could not allocate the game panel texture.");
            nativeTexture = target.GetNativeTexturePtr();
        }

        uiCamera.Render(target);
        if (pointing)
        {
            var previous = RenderTexture.active;
            RenderTexture.active = target;
            GL.PushMatrix();
            try
            {
                GL.LoadPixelMatrix(0, width, height, 0);
                Graphics.DrawTexture(new Rect(pointer.x * width - 3, pointer.y * height - 3, 6, 6), Texture2D.whiteTexture);
            }
            finally
            {
                GL.PopMatrix();
                RenderTexture.active = previous;
            }
        }
        int eventId = OpenVr.AlVrQueuePanel(nativeTexture);
        if (eventId < 0)
            throw new InvalidOperationException("SteamVR rejected the game panel texture.");
        if (eventId > 0)
            GL.IssuePluginEvent(renderEvent, eventId);
    }

    internal void DrawPointer()
    {
        if (!pointing || Event.current?.type != EventType.Repaint)
            return;

        int depth = GUI.depth;
        Color color = GUI.color;
        GUI.depth = int.MinValue;
        float x = pointer.x * Screen.width, y = pointer.y * Screen.height;
        GUI.color = Color.black;
        GUI.DrawTexture(new Rect(x - 5, y - 5, 10, 10), Texture2D.whiteTexture);
        GUI.color = Color.white;
        GUI.DrawTexture(new Rect(x - 3, y - 3, 6, 6), Texture2D.whiteTexture);
        GUI.color = color;
        GUI.depth = depth;
    }

    private void Disable(string reason)
    {
        Close();
        Plugin.Instance.Log.LogWarning($"AL SteamVR game panel closed. {reason}");
    }

    private void Close()
    {
        ResetPointerInput();
        mouse.Release();
        open = openRequested = pointing = false;
        wheel = 0;
        OpenVr.AlVrClosePanel();
        if (target) Object.Destroy(target);
        target = null;
        nativeTexture = IntPtr.Zero;
    }

    public void Dispose()
    {
        disposed = true;
        Close();
        uiCamera.Dispose();
    }
}
