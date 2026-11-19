using System.Runtime.InteropServices;
using BepInEx.Preloader.Core.Patching;

namespace AL_Performance;

[PatcherPluginInfo("com.al-povx.renderdoc-preloader", "AL RenderDoc Preloader", "0.1.0")]
public sealed class RenderDocPreloader : BasePatcher
{
    public override void Initialize()
    {
        if (!OperatingSystem.IsWindows() || Environment.GetEnvironmentVariable("AL_PERF_RENDERDOC") != "1")
            return;

        string? path = Environment.GetEnvironmentVariable("AL_PERF_RENDERDOC_DLL");
        if (string.IsNullOrWhiteSpace(path) || !Path.IsPathFullyQualified(path) ||
            !string.Equals(Path.GetFileName(path), "renderdoc.dll", StringComparison.OrdinalIgnoreCase) || !File.Exists(path))
        {
            Log.LogWarning("AL_PERF_RENDERDOC_DLL must point to an existing absolute path to renderdoc.dll.");
            return;
        }

        // Doorstop already owns the bootstrap hooks. RenderDoc must hook the graphics API before Unity creates its device.
        // Keep this library loaded until process exit because it installs graphics hooks.
        if (!NativeLibrary.TryLoad(path, out _))
        {
            Log.LogWarning($"Could not load RenderDoc from {path}.");
            return;
        }

        Log.LogInfo($"Loaded RenderDoc during BepInEx preloader from {path}.");
    }
}
