using System.Runtime.InteropServices;

namespace AL_VR;

internal sealed class GameWindowMouse
{
    private const uint LeftDown = 0x0002, LeftUp = 0x0004, RightDown = 0x0008, RightUp = 0x0010, Wheel = 0x0800;
    private bool leftHeld, rightHeld;

    internal bool IsDragging => leftHeld || rightHeld;

    internal static bool Move(float x, float y)
    {
        IntPtr window = GetForegroundWindow();
        GetWindowThreadProcessId(window, out uint processId);
        if (processId != Environment.ProcessId || !GetClientRect(window, out var client) ||
            client.Right <= 0 || client.Bottom <= 0)
            return false;

        var point = new Point
        {
            X = (int)(Math.Clamp(x, 0, 1) * (client.Right - 1)),
            Y = (int)(Math.Clamp(y, 0, 1) * (client.Bottom - 1))
        };
        return ClientToScreen(window, ref point) && WindowFromPoint(point) == window && SetCursorPos(point.X, point.Y);
    }

    internal void PressLeft() => leftHeld = leftHeld || SendMouse(LeftDown);
    internal void PressRight() => rightHeld = rightHeld || SendMouse(RightDown);
    internal void ReleaseLeft() => leftHeld = leftHeld && !SendMouse(LeftUp);
    internal void ReleaseRight() => rightHeld = rightHeld && !SendMouse(RightUp);
    internal static void Scroll(int steps) => SendMouse(Wheel, steps * 120);

    internal void Release()
    {
        ReleaseLeft();
        ReleaseRight();
    }

    private static bool SendMouse(uint flags, int data = 0)
    {
        var input = new Input { Mouse = new MouseInput { Flags = flags, Data = data } };
        return SendInput(1, ref input, Marshal.SizeOf<Input>()) == 1;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Point { internal int X, Y; }

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect { internal int Left, Top, Right, Bottom; }

    // INPUT_MOUSE is zero. MOUSEINPUT is the largest member of INPUT's union.
    [StructLayout(LayoutKind.Sequential)]
    private struct Input
    {
        private uint type;
        internal MouseInput Mouse;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MouseInput
    {
        private int dx, dy;
        internal int Data;
        internal uint Flags;
        private uint time;
        private UIntPtr extraInfo;
    }

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetClientRect(IntPtr window, out Rect rect);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ClientToScreen(IntPtr window, ref Point point);

    [DllImport("user32.dll")]
    private static extern IntPtr WindowFromPoint(Point point);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    private static extern uint SendInput(uint count, ref Input input, int size);
}
