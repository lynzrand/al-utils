# Current checkpoint — 2026-11-17

## Latest: requested night-scene all-light shadow benchmark

User supplied map002 and asked to enable all light shadows and benchmark.
Completed authored/all A/B/B/A plus two off runs; an unfocused A was excluded
and repeated. All 38 active light flags were set to Soft; the actual additional
atlas increased from 18 lights/63 slices to 24 lights/74 slices. Existing masks
and atlas settings were retained; this does not mean 38 independently rendered
shadow maps. Results: authored 103.60/107.12 FPS, all 92.03/93.46 FPS,
off 171.17/171.76 FPS. GPU p50 median of runs: 7.644/9.540/4.617 ms.
Authored GPU drift makes added cost roughly 1.5–2.3 ms; all versus off +4.924 ms.
See `artifacts/npr/all-shadows-20261117/README.md` for limits and raw evidence.
Final state restored 38/38 light flags, animation=1, v-sync=1, frame limit=-1
and prior benchmark control environment. No new rendering error markers.

## Later continuation: retained geometry and MSAA seams

Completed and live-tested native retained-scene handles plus managed frozen
query entry points. Two queries reused the same BLAS/TLAS; a fresh rebuild
produced matching depth/mask counts and near-identical screenshots. AS timing
was 0.001–0.002 ms on reuse versus 40.175 ms for the fresh build. These are
diagnostic intervals, not FPS or continuous-renderer results.

The user reported bright polygon seams. They persist under forced occlusion
(`testMask=7`, no ray intersections) at 8x MSAA, and disappear in the single-
sample control. Fix the MSAA receiver/visibility contract before promoting
the ray path. Animated geometry and pre-shading scheduling remain unfinished.
See `tools/README.retained-ray-scene.md` and
`artifacts/npr/retained-ray-20261117` for evidence and API usage.

Final live check: PID 16404, map001, accepted RecoveryLighting8 combined bundle,
470 overrides, Far sun shadows on, timeScale=1, MSAA=8; native diagnostic has
zero pending/inflight requests and scene handles. The sandbox hid this process
and denied its pipe; explicit PID plus escalated execution connected successfully.
Startup installation was not changed.

The user restarted after a GPU stability problem following hibernation, then
authorized autonomous continuation. Live PID was 16404 in the isolated game;
verify it again next session. The prepared scene is map001 at 2560x1440.

## Clothing correction and active state

The active runtime is `AL_NPR_RecoveryLighting8`, now using
`artifacts/npr/cloth-20261117/combined.unity3d`. It combines a clothing-only
aggregate extra-light cap with removal of the stock extra-light material-color
gain/floor. Hair, skin and supporting shader objects remain byte-identical to
the previous raster checkpoint. Both changes are separate opt-in builder flags.

Same-pose captures of stock, previous baseline, aggregate-only, color-only and
combined variants are in `artifacts/npr/cloth-20261117`. Captures completed
before any subsequent state mutation. The color correction restored the shirt's
dark appearance; aggregate-only had little visible effect in this daylight view.
White waist clothing remained white, with lower extra illumination. This was a
live black/white clothing test, not validation of every costume or night scene.

Saved ready-to-load pair: `artifacts/npr/checkpoint-20261117/AL_NPR.dll` and
`al-skin-lighting.unity3d`. DLL SHA256 remains
`1c38e76007e6aefcc53123e624cf3234b4c3e2549af4ece47422269744d65811`;
bundle SHA256 is
`eff057297a9860aa354b2c5c906e1876c3ed0f4f41345f63dc6e58f721595266`.
The startup installation has not been replaced. Previous checkpoints remain.
Final runtime state: 119 material overrides, Far sun soft shadows on, animation
time scale 1, original v-sync 1 and frame limit restored. The temporary
AL_PERF_CONTROL environment setting was restored after the reset completed.

All three candidates passed exact-patch checks for 640 edited cloth variants,
FXC for all 768 surface variants, unchanged noncloth object checks and untouched
program/metadata/resource/parameter checks. Numerical tests passed. See
`tools/README.surface-overexposure.md` and the per-candidate validation JSONs.

## Measured sun shadow cost

The focused A/B/B/A comparison uses the combined clothing bundle, fixed pose,
same camera, same sun routing and caster masks, and unchanged punctual shadows.
Conditions: map001, D3D12, RTX 5070 Ti, 2560x1440, scale 1, 8x MSAA,
4096 main/additional atlases, three cascades, shadow distance 300, uncapped.
Each run used six seconds warmup and fifteen seconds sampling.

| Measurement | Sun map off | Sun map on |
| --- | ---: | ---: |
| Mean FPS, two separate runs | 161.93 / 161.61 | 137.58 / 137.28 |
| Median GPU time, median of run percentiles | 6.047 ms | 7.142 ms |
| p95 GPU time, median of run percentiles | 6.575 ms | 7.674 ms |
| Median wall-frame interval | 6.236 ms | 7.190 ms |

The incremental median GPU cost is 1.094 ms; this is whole-frame GPU timing,
not an isolated atlas pass timestamp. Recorded start/end state matched. The log
range covering setup/warmups/measurements contained no FlockGPUComputation,
CSMain, exception, error or device-loss markers. Files and full analysis are in
`artifacts/npr/shadow-20261117`, especially `comparison.txt` and `log-review.json`.
The earlier unfocused `off-a1` probe is excluded. The final reset recorded
restored frame limits and animation; focus changed after measurement, not inside
the recorded endpoints. This one directional-light test does not establish
many-light scaling, animation cost, other-scene performance or ray equivalence.

Next: verify the clothing correction in the previously overlit map002 scene,
exercise route restoration across scene transitions, then extend comparable
shadow coverage and continuous ray updates before a map-versus-ray benchmark.
No ray result or benchmark was added in this session.

# Historical night checkpoint — 2026-11-16

The user likes the overall aesthetic, confirmed live environmental shadows,
and asked to wrap up for the night. Preserve this version before further trials.
White clothing clips badly and even a black T-shirt becomes pale; this is a
known unresolved material response problem, not an accepted correctness claim.

## Saved and active version

- Ready-to-load pair: `artifacts/npr/checkpoint-20261116/AL_NPR.dll` and
  `al-skin-lighting.unity3d`. These were saved locally, not installed over the
  game's startup plugin or bundle.
- DLL SHA256: `1c38e76007e6aefcc53123e624cf3234b4c3e2549af4ece47422269744d65811`.
- Bundle SHA256: `22d5c48af7fd57845f436d708a7c9a7a97d35a345c76e8634b2a3cd8a6a90bda`.
- Canonical source is `AL_NPR/`; the running hot-loaded copy is namespace
  `AL_NPR_RecoveryLighting8`, from
  `artifacts/npr/recovery-lighting8/bin/Release/net6.0/AL_NPR_RecoveryLighting8.dll`.
- Running bundle: `artifacts/npr/cap-comparison/character-map-raster.unity3d`.
- Final verified status: Far/Sky/Ground authored directionals, raster sun
  `Directional Light Far`, soft shadows on, 504 overridden materials,
  no suppressed character-only lights, time scale 1, run-in-background true.
- Game is the isolated `artifacts/npr/4k/native-capture-game` copy. Do not
  assume process ID or current scene remains unchanged next session.

The latest controller owns sun routing. It follows eligible map suns through
scene scans and restores routing on F7 off or Stop. Live verification through
the same Set(false,false) path restored `Directional Light Camera`; turning
sharing back on selected Far. SetRasterShadows(false/true) retained Far in both
cases. A scene transition with this final lifecycle revision was not tested.
The earlier manual stage7 `rasterRoute` was disposed before stage8 activation.

Scope: one shadowed environmental directional, plus existing punctual shadow
maps. Sky/Ground remain unshadowed. Hair/clothing retain their accepted surface
patch; choosing a different main light also changes their stock main-light
response. No authored light transform, intensity or color was changed.

## Evidence and remaining work

- Managed build passed with zero warnings/errors. All 128 raster skin variants
  passed FXC disassembly. Hair/clothing/support objects match the accepted
  surface bundle; other programs and metadata are unchanged. See
  `artifacts/npr/cap-comparison/raster-validation/validation.json`.
- User screenshots confirmed visible shadows in outdoor views. Final screenshot
  `artifacts/npr/cap-comparison/night-checkpoint.png` was requested without a
  same-call mode mutation.
- **Capture ordering correction:** ScreenCapture.CaptureScreenshot queues an
  end-of-frame capture. Wait for completion before changing mode or clearing
  visibility. Earlier `raster-before/off/on` and the first ray-reprojection
  comparison mixed captures with same-call mutations and cannot establish A/B
  image differences. Corrected controlled comparisons remain pending.
- No fresh shadow performance measurements were completed tonight. The harness
  and matched-state analyzer are ready in `AL_Performance/tools/README.shadows.md`.
  The running performance plugin had no AL_PERF_CONTROL set; it was not activated.
- Ray work remains a frozen diagnostic. All stage5/stage6 requests were retired
  and visibility cleared. Receiver reprojection and native AS/trace/copy GPU
  timestamps are implemented but need correctly ordered live validation; they
  are not a continuous ray shadow implementation or a comparable performance
  result. See `tools/README.ray-receiver-reprojection.md`.
- The clothing diagnosis is in `tools/README.surface-overexposure.md`: per-light
  caps do not bound the sum, and the stock cloth extra-light response has a dark
  color floor. Test an aggregate bound and material-color preservation separately.
  Do not assume shadows alone can fix it.

Next session: verify the saved shadow version across scenes, address the clothing
response while preserving the liked overall look, then collect controlled map
off/on timings. Compare rays only after geometry coverage and update behavior
are comparable. Do not report historical 4K optimization numbers as results for
this newer material/shadow revision.

The repository already contained uncommitted VR changes and untracked AL_NPR,
AL_DevRepl and AL_Performance trees. No commits were made and unrelated work was
preserved. No game restart or startup installation was performed tonight.
