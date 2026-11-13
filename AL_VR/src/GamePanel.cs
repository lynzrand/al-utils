extern alias unity;

using System.Collections;
using UnityEngine;
using unity::UnityEngine;
using Object = unity::UnityEngine.Object;

namespace AL_VR;

internal sealed class GamePanel(IntPtr renderEvent) : IDisposable
{
    private readonly GameWindowMouse mouse = new();
    private RenderTexture? target;
    private IntPtr nativeTexture;
    private uint? device;
    private bool open, disposed, toggleRequested, pointing;
    private bool menuStarted;
    private float menuDownAt, wheel;
    private Vector2 pointer;
    internal bool IsOpen => open;

    // Returns true when the controller requests a headset recenter.
    internal bool Update(bool focused)
    {
        if (!focused || OpenVr.AlVrReadController(out var input) == 0)
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
            toggleRequested = !toggleRequested;
        }
        if (toggleRequested && open)
        {
            Close();
            toggleRequested = false;
        }
        else if (toggleRequested || (recenter && open))
            toggleRequested = OpenAtHead() == 0 && !open;
        else
            UpdatePointer(input);
        return recenter;
    }

    internal int OpenAtHead()
    {
        mouse.Release();
        pointing = false;
        wheel = 0;
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
        pointing = open && !menu && input.PointsAtPanel && GameWindowMouse.Move(input.PanelX, input.PanelY);
        if (!pointing && open && !menu && mouse.IsDragging &&
            float.IsFinite(input.PanelX) && float.IsFinite(input.PanelY))
            GameWindowMouse.Move(input.PanelX, input.PanelY);
        if (!input.TriggerPressed || menu) mouse.ReleaseLeft();
        if (!input.SecondaryPressed || menu) mouse.ReleaseRight();
        if (!pointing)
        {
            wheel = 0;
            return;
        }

        pointer = new Vector2(input.PanelX, input.PanelY);
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
        mouse.Release();
        menuStarted = toggleRequested = pointing = false;
        wheel = 0;
    }

    internal IEnumerator CaptureFrames()
    {
        // Screen-space UI is available only after the desktop frame has finished.
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
            target = new RenderTexture(width, height, 0, RenderTextureFormat.ARGB32) { name = "AL SteamVR Game Panel" };
            if (!target.Create())
                throw new InvalidOperationException("Unity could not allocate the game panel texture.");
            nativeTexture = target.GetNativeTexturePtr();
        }

        ScreenCapture.CaptureScreenshotIntoRenderTexture(target);
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
        mouse.Release();
        open = pointing = false;
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
    }
}
