# RenderDoc preloader

Doorstop installs its Unity runtime hook before the BepInEx preloader starts. Loading RenderDoc from this patcher puts its graphics API hooks after Doorstop's bootstrap and before Unity creates its graphics device. This addresses the initialization order described in [Unity Doorstop issue #24](https://github.com/NeighTools/UnityDoorstop/issues/24).

Build the patcher from the repository root and copy its DLL to `BepInEx/patchers` in the game directory.

```powershell
dotnet build .\AL_Performance\RenderDocPreloader\AL_RenderDocPreloader.csproj -c Release
```

Set `AL_PERF_RENDERDOC=1` and set `AL_PERF_RENDERDOC_DLL` to the absolute path of the x64 `renderdoc.dll` from the [portable RenderDoc release](https://renderdoc.org/builds). Launch `AmanatsuLocation.exe` normally with that environment. The BepInEx log records when the patcher loads the DLL. RenderDoc starts its target-control listener and Windows may display a firewall prompt. Capturing via the in-game API writes directly to disk and does not require a remote connection.

With `AL_PERF_CONTROL` also configured, set `Capture` in the benchmark request to queue a frame capture. RenderDoc appends the frame number and `.rdc` extension to the benchmark ID in the control directory. Capture can pause or slow the game. Collect frame-time comparisons in a regular launch.
