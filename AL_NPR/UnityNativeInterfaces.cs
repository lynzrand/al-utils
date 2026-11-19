extern alias unity;
using System.Runtime.InteropServices;
using unity::UnityEngine;

namespace AL_NPR;

internal static class UnityNativeInterfaces
{
    private const int PluginLoadCall = 0x551d68;
    private const int RegistryRva = 0x1f3d410;
    private const int TextStart = 0x1000;
    private const int TextEnd = 0x19f8558;
    private const ulong GraphicsHigh = 0x7CBA0A9CA4DDB544;
    private const ulong GraphicsLow = 0x8C5AD4926EB17B11;
    private static readonly byte[] LoadSignature = { 0x48, 0x8d, 0x0d, 0xa1, 0xb6, 0x9e, 0x01, 0x41, 0xff, 0x57, 0x18 };

    internal static IntPtr Get()
    {
        if (Application.unityVersion != "6000.0.65f1" || !Environment.Is64BitProcess)
            throw new NotSupportedException("The native interface registry lookup requires AL's audited x64 Unity player.");
        var player = GetModuleHandle("UnityPlayer.dll");
        if (player == IntPtr.Zero) throw new InvalidOperationException("UnityPlayer.dll is not loaded.");

        // The runner loads plug-ins through .NET. Unity's own loader passes
        // this same registry address as the sole argument to UnityPluginLoad.
        var source = IntPtr.Add(player, PluginLoadCall);
        for (int i = 0; i < LoadSignature.Length; i++)
            if (Marshal.ReadByte(source, i) != LoadSignature[i])
                throw new NotSupportedException("UnityPlayer's native plug-in loader does not match the audited build.");

        var registry = IntPtr.Add(player, RegistryRva);
        for (int i = 0; i < 4; i++)
        {
            long relative = Marshal.ReadIntPtr(registry, i * IntPtr.Size).ToInt64() - player.ToInt64();
            if (relative < TextStart || relative >= TextEnd)
                throw new InvalidOperationException("Unity's native interface registry has not been initialized.");
        }
        return registry;
    }

    internal static string Describe()
    {
        var registry = Get();
        var lookup = Marshal.GetDelegateForFunctionPointer<GetInterfaceSplit>(
            Marshal.ReadIntPtr(registry, 2 * IntPtr.Size));
        var graphics = lookup(GraphicsHigh, GraphicsLow);
        if (graphics == IntPtr.Zero) throw new InvalidOperationException("Unity's graphics interface was not found.");
        var renderer = Marshal.GetDelegateForFunctionPointer<GetRenderer>(Marshal.ReadIntPtr(graphics));
        return $"Unity graphics renderer {renderer()}, D3D12 v7: " +
            $"{lookup(0x4624B0DA41B64AAC, 0x915AABCB9BC3F0D3) != IntPtr.Zero}, " +
            $"v6: {lookup(0xA396DCE58CAC4D78, 0xAFDD9B281F20B840) != IntPtr.Zero}.";
    }

    [DllImport("kernel32.dll", EntryPoint = "GetModuleHandleW", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string moduleName);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr GetInterfaceSplit(ulong high, ulong low);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int GetRenderer();
}
