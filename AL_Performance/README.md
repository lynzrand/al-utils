# AL Performance

AL Performance is a BepInEx 6 IL2CPP plugin for Amanatsu Location 1.0.4 on Unity 6000.0.65f1. It exposes the game's URP multisampling and internal render scale separately. The game's own anti-aliasing menu selects a render scale of 1.0, 1.5, or 2.0, while the URP asset requests 8× MSAA. The default plugin configuration keeps the game's settings.

## Build and install

```powershell
dotnet build .\AL_Performance\AL_Performance.csproj -c Release
```

The project defaults to `H:\Programs\gal\amanatsu-location`. Pass `-p:GamePath=...` or `-p:InteropPath=...` if the game or the generated BepInEx interop assemblies are elsewhere.

Close the game and copy `AL_Performance.dll` from `AL_Performance\bin\Release\net6.0` to `BepInEx\plugins\AL_Performance`. Edit `BepInEx\config\com.al-povx.performance.cfg` after the first launch. Remove the DLL to uninstall.

```ini
[Rendering]
Render Scale = 0
MSAA Samples = 0
Disable FSR = false
Soft Shadow Filter = Game
```

`MSAA Samples = 4` reduces multisampling at the game's current internal resolution. `0` delegates the choice to the game and `1` disables multisampling. `Render Scale = 0.85` is a separate image-quality tradeoff. It renders 3D at 85% of output width and height, or about 72% of the output pixel count. A value of `0` uses the game's selected scale. `Disable FSR = true` selects URP's Auto filter, which also drops the stock FSR sharpening path at native resolution. The soft shadow filter can select a different URP PCF quality. Keep `Game` for authored light and pipeline settings.

See [the rendering study](RESEARCH.md) for frame timings, shader variants, and the results of byte-for-byte replay comparisons.

## Reproduce the benchmarks

Set `AL_PERF_CONTROL` to an absolute JSON file path in a writable results directory before launching the game. A running game reads each new `Id` once. `Seconds` defaults to zero, which writes a state snapshot without a timed run. For example, after settling into a scene, write `{"Id":"msaa-4","Uncap":true,"Msaa":4,"Warmup":5,"Seconds":15}` to collect a timed run. Write `{"Id":"reset"}` to restore the runtime settings. The CSV records frame intervals and any Unity CPU and GPU timings exposed by the player. The JSON records camera and graphics settings at the beginning and end.

```powershell
.\AL_Performance\tools\run-sweep.ps1 -ControlFile .\artifacts\bench\control.json -Prefix maker
python .\AL_Performance\tools\summarize-sweep.py .\artifacts\bench maker
```

Keep the game focused and the camera in the same place for an A/B run. The sweep brackets its changes with a baseline at each end and removes v-sync and the frame cap for measurement. The stock release does not populate Unity's frame timing samples. The temporary, build-specific `artifacts\static\set-frame-timing.ps1` can enable the serialized timing flag on the verified build and restore it after the session. Check the installed asset hash on restore. The benchmark controller also runs with the stock asset and records frame intervals when GPU timestamps are unavailable.

When the game is already running with RenderDoc injected, set `AL_PERF_RENDERDOC=1` at launch and include `"Capture":true` in a fresh request to queue a frame capture. Let settings settle in a separate request before capturing. The RenderDoc capture and replay tools are optional. An injected RenderDoc can open its target-control socket and trigger a Windows firewall prompt. [RenderDoc target-control initialization](https://github.com/baldurk/renderdoc/blob/v1.47/renderdoc/core/core.cpp#L649-L688)
