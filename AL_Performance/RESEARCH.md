# Amanatsu Location rendering study

Tested game version 1.0.4, Unity 6000.0.65f1, URP Forward+ compatibility mode, GeForce RTX 5070 Ti, and a 2560×1440 output. The main test scene loads `map002` with two stock actors through the game's Free H loader. The camera pose stayed fixed across the in-process runs. The initial map and character-maker runs used their own fixed cameras. Benchmark CSVs and RenderDoc captures are local in `artifacts/bench`. The capture files contain game assets and imagery and should stay local.

## Shader changes

The warm D3D12 `map002` capture contained 1,744 draws and 20 dispatches. A 4096² D16 shadow atlas received 1,370 draws with a summed replay duration of 4.32 ms. The 2560×1440 8× MSAA scene color target received 118 draws totaling 10.02 ms, and the SSAO estimation draw took about 0.71 ms. Target sums can overlap when a draw binds color and depth together. RenderDoc replay numbers characterize the captured workload. Live frame time is in the next section. [RenderDoc timing and capture tool](https://github.com/baldurk/renderdoc)

| Edit | Stock before / edited / stock after | Pixel comparison on the captured frame |
| --- | --- | --- |
| `AL/Map` shadow caster and depth-only shader, skip dither at full fade | 2.112 / 2.146 / 2.020 ms across 618 draws | Final output exact |
| `AL/Map` shadow caster and depth-only shader, omit alpha test for audited stock textures | 2.141 / **1.872** / 2.042 ms across the same 618 draws | 0 of 16,777,216 shadow-atlas texels and 0 of 3,686,400 final pixels changed |
| URP SSAO, branch around nine taps when their existing contribution mask is zero | 0.708 / 0.720 / 0.713 ms for the SSAO estimation draw | SSAO target and final output exact |

The useful shader change removes the alpha texture fetch, dither arithmetic, and `discard` from the audited `AL/Map` depth program. The same bytecode serves both ShadowCaster and DepthOnly. The 31 stock map materials use a 0.5 cutoff, a 1.0 alpha multiplier, and full fade. A decoded mip-chain audit found a minimum texture alpha of 243/255. The replay result shows a 0.17–0.27 ms saving in the sum of the affected draw durations, with approximately 8–13% less time across those draws. The alpha assumption limits the candidate to audited materials. Runtime textures, property blocks, fades, and other scenes need separate coverage before a permanent patch. A uniform-guard variant that retains the original test under other parameter values is available for further testing.

The game loaded the temporary bundle in `map002` and emitted a second RenderDoc capture at stock 8× MSAA and internal scale. The game installation's original bundle and `globalgamemanagers` were restored and verified by SHA-256 after the run. The saved game files and game graphics configuration also matched their earlier hashes. Build and audit instructions are in [the map shader tools guide](tools/README.shader-patch.md).

The SSAO HLSL reconstruction changed 113 of 3,686,400 intermediate texels, with a maximum byte-component difference of 24, so it was excluded from the speed comparison. A direct DXBC edit preserved the stock estimator and its 12 taps. The edit produced identical output and the added branches made the draw slightly slower. [Unity URP 17 SSAO shader source](https://raw.githubusercontent.com/Unity-Technologies/Graphics/6000.0/staging/Packages/com.unity.render-pipelines.universal/ShaderLibrary/SSAO.hlsl)

The shadow atlas draw count makes shadow tile reuse worth investigating. It would require tracking light transforms, caster movement, material state and map transitions, then invalidating stale tiles before shading reads the atlas. The warm capture puts more time in main color draws than atlas generation. The largest warm color draws use `AL/cloth`, `AL/skin_body`, URP Lit and `AL/Map` Forward+, with dynamic lighting and shadow-comparison loops. Future shader work can target those variants using the exported binding data and replay checks.

## Live frame timing

The game used D3D12 and split graphics jobs by default. In the stock `map002` test, a fish compute asset lacked a D3D12 kernel variant and logged a finite burst of missing-kernel errors at scene load. D3D11 used client-worker graphics jobs and did not log those errors. Treat the API runs as two complete configurations with different workloads. A hash-checked temporary Unity `enableFrameTimingStats` edit supplied the GPU timestamps. Nonpositive GPU timings were excluded from GPU percentiles. [Unity frame timing setup](https://docs.unity3d.com/6000.0/Documentation/Manual/frame-timing-manager-enable.html)

| D3D12 `map002` at 2560×1440 | Average FPS | Frame p50 / p95 | GPU p50 |
| --- | ---: | ---: | ---: |
| Stock 8× MSAA, start / end baseline | 79.8 / 80.2 | 12.00 / 17.11 ms, 12.01 / 17.08 ms | 11.77 / 11.80 ms |
| 4× MSAA | 82.8 | 11.46 / 16.52 ms | 11.16 ms |
| 2× MSAA | 87.6 | 10.96 / 15.92 ms | 10.70 ms |
| 85% internal scale with FSR | 96.0 | 9.91 / 15.25 ms | 9.09 ms |
| 75% internal scale with FSR | 102.4 | 9.50 / 14.20 ms | 7.50 ms |
| Camera shadows off | 107.7 | 8.98 / 12.22 ms | 8.80 ms |
| SSAO renderer feature off | 86.8 | 11.04 / 16.00 ms | 10.82 ms |

Changing shadow distance from 300 m to 100 m, the main atlas from 4096 to 2048, or three main cascades to two changed median GPU time by less than 0.1 ms in this view. The shadow, scale, MSAA and SSAO toggles above change image quality and were diagnostic. The installed configuration uses the game's values.

PresentMon cross-checked DXGI present intervals with display and GPU tracking disabled. The RenderDoc preloader successfully captured the modded game after the direct injector conflicted with Doorstop. [PresentMon](https://github.com/GameTechDev/PresentMon) · [Unity Doorstop injection conflict](https://github.com/NeighTools/UnityDoorstop/issues/24)

## Native 4K character lighting follow-up

The [AL_NPR startup plugin](../AL_NPR/README.md) shares the three skin-light accumulation paths' Forward+ light evaluation, rejects zero contributions before filtering shadows, and selects the map's authored additional lights directly in the shader. The skin uses per-renderer scene SH for the broad shaping response and keeps the original material palette. Cloth and hair also use full fusion in regular non-instanced variants.

The fixed-frame A/B/A replay used native 3840×2160 with stock 8× MSAA and replaced each shader separately. All 8,294,400 presented pixels matched after each substitution. Event sums describe the affected draws in each replay.

| Captured stock variant | Stock / full fusion / restored |
| --- | ---: |
| Body, 4 draws | 3.664 / **1.782** / 3.667 ms |
| Cloth, 5 draws | 3.694 / **1.800** / 3.689 ms |
| Hair, 6 draws | 1.183 / **0.519** / 1.180 ms |

The integrated map-lighting plugin was timed in two alternating stock and override windows each after warmup in a single isolated D3D12 process. The camera and game time were fixed, the window stayed focused, and native runs kept 8× MSAA, HDR, shadows, and postprocessing. A material probe before each window confirmed the active head and body shader names.

| Full pipeline at 3840×2160 output | Average FPS | Frame p95 | GPU p95 |
| --- | ---: | ---: | ---: |
| Stock native, both samples | 42.0–42.1 | 26.79–26.84 ms | 26.57–26.59 ms |
| Override native, both samples | 51.1–51.2 | 19.84–19.86 ms | 19.56–19.61 ms |
| Override, 85% internal scale with FSR and 2× MSAA | 67.0 | 16.55 ms | 13.72 ms |
| Override, 75% internal scale with FSR and 2× MSAA | 71.8 | 15.72 ms | 11.14 ms |

The internal-scale runs are diagnostics. None reached the 11.11 ms whole-frame budget for sustained 90 FPS. Timing CSVs and metadata are local in `artifacts/npr/4k` with the `full-map-` prefix. Earlier runs with uncertain process counts and startup shader binding are excluded.

The `full-map-` samples used map light selection on skin, hair, and cloth. A later roaming comparison at Waterfront Cottage showed that the stock cloth response washed out the pink jacket when it received those extra lights. The revised build limits map light selection to skin and retains traversal optimization on the original hair and cloth inputs. The nighttime one-on-one preview used the revised build. The revised build needs its own native 4K timing run.

In the daytime comparison, disabling the camera face light changed the directional that URP placed in its main slot. The replacement skin missed the map directional there, while the stock hair and clothing responded to the stronger source. Leaving the world light selection intact recovered the stock hair color and clothing detail. The selected renderer had screen-space ambient occlusion off in both stock and preview.

The HDR replay comparison reads sample zero of the selected 4K color target before postprocessing. In the tested body draw, the number of pixels at or above a linear RGB peak of 0.75 increased from 56,759 at the captured light level to 59,786 when the shader's map-light inputs were multiplied by 100 before the per-light cap. None of the 2,003,668 affected pixels reached 1.0 in that color target in either replay. These measurements describe one draw and its input stress test. They do not establish a display clipping threshold for every scene.
