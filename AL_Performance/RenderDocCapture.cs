using System.Runtime.InteropServices;

namespace AL_Performance;

internal static class RenderDocCapture
{
    private const uint PinModule = 1;
    private const int ApiVersion = 10000;

    // RenderDoc's version 1.0 table is a stable array of function pointers.
    private const int SetCaptureFilePathTemplateSlot = 11;
    private const int TriggerCaptureSlot = 15;

    private static readonly Lazy<CaptureApi?> Api = new(Bind);

    internal static bool IsAvailable => Api.Value is not null;

    // True means a request was queued for the next presented frame. RenderDoc writes it asynchronously.
    // Call on Unity's main thread with an absolute filename template from the benchmark output directory.
    internal static bool TryTrigger(string pathTemplate)
    {
        if (!Path.IsPathFullyQualified(pathTemplate) || pathTemplate.Contains('\0') || Api.Value is not { } api)
            return false;

        api.SetPathTemplate(pathTemplate);
        api.Trigger();
        return true;
    }

    private static CaptureApi? Bind()
    {
        if (!OperatingSystem.IsWindows() || Environment.GetEnvironmentVariable("AL_PERF_RENDERDOC") != "1")
            return null;

        // Use the already-injected capture module. Pin it for the lifetime of the cached native delegates.
        if (!GetModuleHandleEx(PinModule, "renderdoc.dll", out IntPtr module) ||
            !NativeLibrary.TryGetExport(module, "RENDERDOC_GetAPI", out IntPtr entryPoint))
            return null;

        var getApi = Marshal.GetDelegateForFunctionPointer<GetApi>(entryPoint);
        if (getApi(ApiVersion, out IntPtr table) != 1 || table == IntPtr.Zero)
            return null;

        IntPtr setPath = Marshal.ReadIntPtr(table, SetCaptureFilePathTemplateSlot * IntPtr.Size);
        IntPtr trigger = Marshal.ReadIntPtr(table, TriggerCaptureSlot * IntPtr.Size);
        if (setPath == IntPtr.Zero || trigger == IntPtr.Zero)
            return null;

        return new CaptureApi(
            Marshal.GetDelegateForFunctionPointer<SetCaptureFilePathTemplate>(setPath),
            Marshal.GetDelegateForFunctionPointer<TriggerCapture>(trigger));
    }

    [DllImport("kernel32.dll", EntryPoint = "GetModuleHandleExW", ExactSpelling = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetModuleHandleEx(uint flags, string moduleName, out IntPtr module);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int GetApi(int version, out IntPtr table);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void SetCaptureFilePathTemplate([MarshalAs(UnmanagedType.LPUTF8Str)] string template);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void TriggerCapture();

    private sealed record CaptureApi(SetCaptureFilePathTemplate SetPathTemplate, TriggerCapture Trigger);
}
