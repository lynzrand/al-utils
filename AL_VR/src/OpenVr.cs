extern alias unity;

using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32;
using unity::UnityEngine;

namespace AL_VR;

[StructLayout(LayoutKind.Sequential)]
internal readonly struct OpenVrTransform
{
    // OpenVR is right handed, with -Z forward. Convert the matrix with
    // diag(1, 1, -1) on both sides before extracting its Unity-space pose.
    private readonly float m00, m01, m02, m03;
    private readonly float m10, m11, m12, m13;
    private readonly float m20, m21, m22, m23;

    internal Vector3 Position => new(m03, m13, -m23);

    internal Quaternion Rotation => Quaternion.LookRotation(
        new Vector3(-m02, -m12, m22), new Vector3(m01, m11, -m21));
}

[StructLayout(LayoutKind.Sequential)]
internal readonly struct OpenVrEye
{
    internal readonly OpenVrTransform EyeToHead;
    private readonly float left, right, top, bottom;

    internal Matrix4x4 Projection(float near, float far) =>
        Matrix4x4.Frustum(left * near, right * near, -bottom * near, -top * near, near, far);
}

[StructLayout(LayoutKind.Sequential)]
internal readonly struct OpenVrDisplay
{
    internal readonly uint Width, Height;
    internal readonly OpenVrEye Left, Right;
}

[StructLayout(LayoutKind.Sequential)]
internal readonly struct OpenVrController
{
    internal readonly uint Device;
    private readonly uint buttons, clicked;
    internal readonly float Scroll, PanelX, PanelY;
    private readonly uint pointsAtPanel;

    internal bool TriggerPressed => (buttons & 1) != 0;
    internal bool SecondaryPressed => (buttons & 2) != 0;
    internal bool MenuPressed => (buttons & 4) != 0;
    internal bool TriggerClicked => (clicked & 1) != 0;
    internal bool SecondaryClicked => (clicked & 2) != 0;
    internal bool MenuClicked => (clicked & 4) != 0;
    internal bool PointsAtPanel => pointsAtPanel != 0;
}

internal static class OpenVr
{
    private const string Bridge = "AL_VR_Native";
    private static IntPtr bridgeHandle;

    static OpenVr() => NativeLibrary.SetDllImportResolver(typeof(OpenVr).Assembly, ResolveBridge);

    private static IntPtr ResolveBridge(string name, Assembly assembly, DllImportSearchPath? searchPath)
    {
        if (name != Bridge)
            return IntPtr.Zero;

        // Unity can still dispatch a queued render event during plugin teardown.
        // Keep the bridge loaded until process exit and let AlVrStop invalidate it.
        if (bridgeHandle == IntPtr.Zero)
        {
            string directory = Path.GetDirectoryName(assembly.Location)!;
            bridgeHandle = NativeLibrary.Load(Path.Combine(directory, Bridge + ".dll"));
        }
        return bridgeHandle;
    }

    internal static string FindLibrary(string configuredPath)
    {
        if (!string.IsNullOrWhiteSpace(configuredPath))
        {
            string path = Environment.ExpandEnvironmentVariables(configuredPath.Trim());
            if (!Path.IsPathFullyQualified(path) || !File.Exists(path))
                throw new FileNotFoundException("OpenVR DLL Path must name an existing absolute path.", path);
            return path;
        }

        string? steamVrRoot = Registry.GetValue(
            @"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 250820",
            "InstallLocation", null) as string;
        if (steamVrRoot != null)
        {
            string path = Path.Combine(steamVrRoot, "bin", "win64", "openvr_api.dll");
            if (Path.IsPathFullyQualified(path) && File.Exists(path))
                return path;
        }

        string? steamRoot = Registry.GetValue(@"HKEY_CURRENT_USER\Software\Valve\Steam", "SteamPath", null) as string
            ?? Registry.GetValue(@"HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Valve\Steam", "InstallPath", null) as string;
        if (steamRoot != null)
        {
            string path = Path.Combine(steamRoot, "steamapps", "common", "SteamVR", "bin", "win64", "openvr_api.dll");
            if (Path.IsPathFullyQualified(path) && File.Exists(path))
                return path;
        }

        throw new FileNotFoundException("SteamVR's 64-bit openvr_api.dll could not be found. Set OpenVR DLL Path in the plugin config.");
    }

    internal static string LastError()
    {
        var buffer = new byte[256];
        AlVrGetLastError(buffer, (nuint)buffer.Length);
        return Encoding.UTF8.GetString(buffer, 0, Array.IndexOf(buffer, (byte)0));
    }

    [DllImport(Bridge, CharSet = CharSet.Unicode, ExactSpelling = true, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int AlVrStart(string libraryPath, out OpenVrDisplay info);

    [DllImport(Bridge, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int AlVrSetTextures(IntPtr left, IntPtr right);

    [DllImport(Bridge, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int AlVrBeginFrame(out OpenVrTransform headToTracking);

    [DllImport(Bridge, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int AlVrArmSubmit();

    [DllImport(Bridge, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int AlVrReadController(out OpenVrController controller);

    [DllImport(Bridge, CallingConvention = CallingConvention.Cdecl)]
    internal static extern void AlVrSuspendControllerInput();

    [DllImport(Bridge, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int AlVrOpenPanel();

    [DllImport(Bridge, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int AlVrQueuePanel(IntPtr texture);

    [DllImport(Bridge, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int AlVrPanelReady();

    [DllImport(Bridge, CallingConvention = CallingConvention.Cdecl)]
    internal static extern void AlVrClosePanel();

    [DllImport(Bridge, CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr AlVrRenderEvent();

    [DllImport(Bridge, CallingConvention = CallingConvention.Cdecl)]
    internal static extern void AlVrStop();

    [DllImport(Bridge, CallingConvention = CallingConvention.Cdecl)]
    internal static extern ulong AlVrSubmittedFrames();

    [DllImport(Bridge, CallingConvention = CallingConvention.Cdecl)]
    private static extern void AlVrGetLastError([Out] byte[] destination, nuint capacity);
}
