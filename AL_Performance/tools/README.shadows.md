# Comparing map and ray shadows

First measure the selected sun's raster shadows **off/on with the accepted character
lighting unchanged**. This measures the cost of adding shadows, not the relative
efficiency of two equivalent shadow implementations. As of 2026-11-16 the ray
path is a frozen one-shot diagnostic: it builds acceleration structures, traces
camera depth, reads the result back, and publishes a frozen mask. Timing a later
frame that only samples that mask is not a ray-shadow rendering benchmark.

The current session is map001 at 2560×1440, render scale 1, 8× MSAA, with stock
4096 shadow atlases, three cascades and shadow distance 300. These are a session
checkpoint, not defaults to force on subsequent sessions. Older `full-map-*`
captures are map002 at 3840×2160 with a different material revision.

## Matched captures

Use the running game's `AL_PERF_CONTROL` path; its startup log prints
`Benchmark control file:`. Do not launch another game instance for an A/B run.
The performance plugin's request restores its own previous overrides, so keep
shadow-mode selection in the renderer's own control. `DisableShadows` switches
stock camera shadows and is not the custom map toggle.

With the integrated raster bundle active, use
`AL_NPR.SceneLighting.SetRasterShadows(false)` for A and
`AL_NPR.SceneLighting.SetRasterShadows(true)` for B (substitute the active
namespace when using a hot-loaded runtime). Both keep the same authored sun
promoted into the main-light slot and retain the same caster masks. Existing
punctual shadows remain in both conditions. F7 is a full stock-versus-mod toggle
and is therefore unsuitable for isolating the incremental sun-shadow cost.

If the plugin is already loaded but `AL_PERF_CONTROL` was unset at startup, the
existing controller can be reinitialized through the development REPL without a
restart. Run this on the game's main thread with no benchmark in progress:

```csharp
var perfAssembly = AppDomain.CurrentDomain.GetAssemblies().Single(a => a.GetName().Name == "AL_Performance");
var perfPluginType = perfAssembly.GetType("AL_Performance.Plugin", true);
var perfPlugin = perfPluginType.GetProperty("Instance", System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.NonPublic).GetValue(null);
var perfController = perfPluginType.GetField("controller", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic).GetValue(perfPlugin);
var perfControl = @"H:\Projects\al-povx\artifacts\npr\shadow-comparison\control.json";
System.IO.Directory.CreateDirectory(System.IO.Path.GetDirectoryName(perfControl));
Environment.SetEnvironmentVariable("AL_PERF_CONTROL", perfControl);
perfController.GetType().GetMethod("Start").Invoke(perfController, null);
```

`Start()` rereads this environment variable and logs the control path; it does
not create another controller. After the final reset request completes, restore
the previous environment value and invoke `Start()` again to restore its previous
control path. Setting `AL_PERF_RENDERDOC` does not inject RenderDoc into an
already-running process.

1. Record the process ID, API, GPU, shader bundle and native DLL hashes, selected
   shadow mode, resolution, light names/types/transforms/intensities/ranges,
   caster/receiver lists and alpha-cutout policy. Record custom atlas size,
   cascade count, filtering, bias and update schedule separately; the performance
   plugin only records URP settings. Keep authored lights and material responses
   identical between conditions.
2. Freeze the same animation pose and camera for the first cost test. Keep the
   game focused. Check both outputs for intended sun occlusion and self-shadow,
   acne, peter-panning, missing thin/alpha surfaces and material coverage. Preserve
   those images with the results. Use a separate animated test once both paths
   support moving casters; frozen results do not establish animation performance.
3. Choose A = custom maps off, B = custom maps on. Capture A/B/B/A, preferably
   another B/A/A/B block to expose warming or clock drift. After each mode switch,
   use a new request ID and at least six seconds of warmup, then 15 seconds of
   measurement. Do not change mode until its JSON and CSV have been written.
4. Save the game log offsets before/after each run and inspect that segment for
   `FlockGPUComputation`, `CSMain`, device errors and new exceptions. Count errors
   over the sample duration, not over the whole game session. An error burst in
   just one run invalidates the comparison. Existing equal-rate errors remain a
   stated limitation, especially when comparing APIs. Keep setup/warmup errors
   separate from errors during sampling.

   Retail BepInEx logs may omit per-line timestamps. A byte range bracketed around
   the request then covers warmup **and** sampling; do not label its count as
   sampling-only. Preserve that full segment and its wall-clock duration, and
   reject any newly introduced error burst in the bracket. Exact sampling-only
   error rates require timestamped logs or separately recorded log offsets at
   the sampling boundary. The JSON `Start.At` records the actual post-warmup
   snapshot time, but cannot timestamp individual untimed log messages.

For each run, after selecting the mode through the renderer's control, write:

```powershell
# Use the already-running process's control path, with a unique ID for each run.
$control = 'H:\Projects\al-povx\artifacts\npr\shadow-comparison\control.json'
$request = @{ Id = 'shadow-off-a1'; Uncap = $true; Warmup = 6; Seconds = 15 }
$result = Join-Path (Split-Path -Parent $control) ($request.Id + '.json')
if (Test-Path -LiteralPath $result) { throw "Result already exists: $result" }
$request | ConvertTo-Json -Compress | Set-Content -LiteralPath $control -Encoding utf8
```

The example path must match the log or process environment. Omitting output
dimensions preserves the current window unless a previous performance request
overrode it. Verify the resulting JSON `Start` and `End` dimensions. `Uncap`
removes the benchmark's frame limit and restores it with a fresh reset request
after the block. This does not restore custom shadow mode or animation state;
restore those through their owner after recording the final comparison.

After writing each request, focus the existing game window during warmup and
keep it focused through completion. Poll only the output files while sampling;
do not run REPL inspections, captures, shader builds or change camera/pose in
that interval. Wait for both output files and confirm their request ID before
switching mode. The plugin writes CSV first and JSON second. Endpoint focus
checks cannot rule out losing focus briefly between them, so a known focus loss
invalidates the run even if both recorded endpoints say `true`.

```powershell
python .\AL_Performance\tools\summarize-shadow-comparison.py `
  --a .\artifacts\npr\shadow-comparison\shadow-off-a1.json .\artifacts\npr\shadow-comparison\shadow-off-a2.json `
  --b .\artifacts\npr\shadow-comparison\shadow-on-b1.json .\artifacts\npr\shadow-comparison\shadow-on-b2.json
@{ Id = 'shadow-reset-1' } | ConvertTo-Json -Compress | Set-Content -LiteralPath $control -Encoding utf8
```

The analyzer reports each run's FPS and nearest-rank p50/p95 wall-frame, Unity
CPU-frame, GPU, main-thread and render-thread times. Unity timings use only positive samples;
the positive/total sample counts remain visible. It compares medians of run
percentiles rather than letting a faster run contribute more pooled frames.
It rejects empty/incomplete CSVs, duplicate runs, nonfinite timings, unfocused
endpoints and differences in recorded state (including camera and URP settings).
Mismatch messages identify the exact nested field and before/after values. Camera
positions/rotations remain exact checks: an unexplained difference is evidence
to inspect, not grounds to silently round the state into a matched comparison.
It cannot detect state changes that return to their original value between the
endpoints, different lights/geometry, intermediate focus loss or visual defects.
Those require the capture checks above. A rejected comparison exits with code 2.

`FrameIntervalMs` comes from consecutive `Stopwatch` observations in `LateUpdate`.
It is wall-clock frame cadence, including stalls and waiting, and remains useful
for throughput when `UnityFrameTiming` is false. It does **not** isolate CPU work
or GPU execution. `UnityCpuFrameMs`, `UnityMainThreadMs`, `UnityRenderThreadMs`
and `UnityGpuFrameMs` come from the player's frame-timing API; missing/zero
samples are unavailable measurements, never zero cost. Do not infer GPU timing
support from a config entry or from the presence of the CSV column. For a useful
first result with frame timing unavailable, report wall-frame FPS/p50/p95, sample
count, full recorded state, matched visual coverage and log diagnostics, and
explicitly leave CPU-work/GPU attribution unresolved.

## When a raster-versus-ray result is meaningful

Use the same set of lights and the same supported caster geometry for the first
controlled comparison. Preserve a second result showing the intended full scene;
excluding cutout hair or animated characters must not disappear from the report.
Compare the continuous full-frame paths at matching image quality, including
filtering/denoising if either path requires it. Record light count and light type;
a directional map, a spot map and six point-light faces are different workloads.
Then increase the same light set in steps to measure scaling, rather than assume
that either technique wins for multiple lights.

Report these costs separately, with CPU/GPU units and measurement method:

| Cost | Raster | Ray |
| --- | --- | --- |
| One-time setup | Atlas allocation and shader warmup | Geometry upload, BLAS/TLAS build, allocations and shader warmup |
| Per-frame scene work | Caster culling and submission | Skinning/mesh extraction, uploads and BLAS/TLAS update or rebuild |
| GPU visibility | All atlas slices/faces/cascades and filtering | Depth preparation, trace dispatch and any denoising |
| Receiver work | Map sampling in affected materials | Ray visibility sampling in affected materials |
| Synchronization | Relevant barriers/copies | Barriers/copies, queue waits and diagnostic readback if enabled |
| End-to-end | Frame and GPU p50/p95, same scene | Frame and GPU p50/p95, same scene |

The current native queue path rebuilds the acceleration structures for each
request. Do not amortize that cost as though caching/refitting already exists.
Likewise, include atlas rendering every frame if the raster candidate updates it
every frame. Cached static-light tests must state each path's invalidation rules
and show correct refresh after a moving light or caster. Report the one-shot ray
experiment as setup/dispatch diagnostics until this contract is implemented.

AL Performance provides end-to-end timings, not these individual native GPU
phases. Add GPU timestamp queries in the owning renderer to isolate build,
update, dispatch, copy and atlas passes. CPU stopwatch durations measure queue
submission or readback latency, not GPU execution. RenderDoc replay can attribute
atlas draws when the preloader is present; see [capture tools](README.md). Sum
non-overlapping leaf events only, and label results as replay timings. Do not
subtract a frozen-mask frame from a live-raster frame and call the difference
ray-versus-map performance.

Frame-timing availability is reported by each JSON's `UnityFrameTiming` and by
positive GPU samples. The config file alone does not establish it. The stock
player may need the existing build-specific temporary timing patch described in
[AL Performance](../README.md); do not edit that asset during a running session.
PresentMon is an independent present-interval cross-check, with display/GPU
tracking disabled on the tested host as documented in [capture tools](README.md).
