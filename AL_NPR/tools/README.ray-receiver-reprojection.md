# Frozen ray receiver reprojection diagnostic

This experiment tests one possible source of self-shadow acne: a resolved
camera-depth sample may come from an off-center MSAA location, while the ray
shader reconstructs its receiver at the pixel center. On a sloped triangle the
result can lie inside the triangle. This is a hypothesis, not an established
explanation for the remaining character artifacts.

`UnityDepthRayVisibility.hlsl` keeps its original behavior by default. Defining
`AL_RAY_REPROJECT_RECEIVER` adds a closest-hit query along the camera-center ray.
The hit must fall inside a local half-pixel depth footprint, estimated from
neighboring depths. An accepted hit replaces the original receiver position.
A rejected hit retains the original position and still traces the light rays;
rejection does not silently turn off shadows. The existing shadow-ray `TMin`
of 0.01 is unchanged. The extra receiver query has its own cost.

This remains a paused, captured-scene diagnostic. Missing cutout geometry,
shader-specific deformation, body discard rules, and the face shadow proxy can
make the captured scene differ from the visible depth. Neighbor depth changes
also do not uniquely identify a surface at silhouettes or overlaps.

## Build variants

All variants use the existing 592-byte `DepthFrame` ABI and compile with DXC
`-T cs_6_5 -E Main -WX -Ges -Gis`:

| Output in `artifacts/npr/ray-receiver-reprojection` | Defines |
| --- | --- |
| `SunBaseline.dxil` | `AL_RAY_OUTPUT_MASK=1` |
| `SunReprojected.dxil` | `AL_RAY_OUTPUT_MASK=1`, `AL_RAY_REPROJECT_RECEIVER=1` |
| `ReceiverAccepted.dxil` | `AL_RAY_REPROJECT_RECEIVER=1`, `AL_RAY_DIAG_ACCEPTED=1` |
| `ReceiverRejected.dxil` | `AL_RAY_REPROJECT_RECEIVER=1`, `AL_RAY_DIAG_REJECTED=1` |
| `AllDirectionalsBaseline.dxil` | none |
| `AllDirectionalsReprojected.dxil` | `AL_RAY_REPROJECT_RECEIVER=1` |

The sun variants emit only bit 0 but still trace every supplied light. Slot 0
was the authored far/sun directional in the tested map001 scene; this ordering
must be checked for another scene. The accepted/rejected variants emit bit 0
as a receiver-classification mask, not a geometric sun-shadow result. A nonzero
runtime `testMask` bypasses reprojection and geometry tracing, as before.

The native module fixes its shader at initialization. Test another variant with
a fresh DLL copy and session, after clearing the published texture and retiring
the prior request. Keep the same paused camera, pose, light list and consumer
bundle when comparing. Poll `CompleteDepth()` after the fence; do not issue a
retirement event before reading the diagnostic result.

## Preliminary live diagnostic on 2026-11-16

The parent task submitted the baseline and reprojection variants in the same
frozen map001 pose using the bounded-depth skin consumer. Native readbacks
reported:

- 323 captured submeshes, including 12 baked character submeshes; 152,871
  triangles.
- 2,929,599 valid depth pixels for both variants.
- Nonzero sun-mask pixels fell from 1,848,306 to 242,257.

The parent saved `off.png`, `baseline.png`, `reprojected.png` and `restored.png`
in the variant output directory. **These preliminary screenshots are invalid
for comparing the shader variants.** `ScreenCapture.CaptureScreenshot` queues
capture for the end of the frame; clearing the visibility texture in the same
REPL operation could remove the effect before capture. Their visual appearance
and image-difference measurements cannot establish whether reprojection helps
the character artifacts. A rerun must separate screenshot requests from state
changes by completed frames and verify capture completion before clearing.

The native mask counts above are separate from this screenshot-ordering flaw;
they establish a changed raw visibility mask, not a visible skin improvement or
failure. The parent retired the diagnostic and restored animation. This
candidate has not been promoted to the normal lighting path; its visual outcome
awaits a correctly ordered comparison.

A useful next discriminator is the same bounded consumer with runtime
`testMask=1`. Faceting that persists under forced occlusion would implicate
receiver acceptance or shading integration rather than the geometric ray query.
The accepted/rejected shader variants can separately expose where reprojection
actually applies; they have been compiled but were not part of the above live
comparison.

## GPU diagnostic timing export

Both native probe variants now export:

```cpp
int ALRAY_ReadTimings(uint64_t ticket, double* buildMs,
                     double* traceMs, double* copyMs);
```

Poll before retiring the request. Return values are `0` for pending, `1` for
available measurements, and `-1` for an invalid, retired, failed, or unreadable
request. Output arguments are unchanged on `0` or `-1`. Four timestamps on
Unity's graphics queue measure these GPU command-stream intervals:

1. All BLAS and TLAS builds, including their UAV barriers.
2. Visibility shader dispatch and its output UAV barrier, including the extra
   receiver query when enabled.
3. The depth diagnostic's output copy and resource transitions. The mesh probe
   has no output copy stage and reports zero here.

The intervals exclude CPU caster collection, baking, allocation, Unity producer
flushes, waiting before the first timestamp, visibility publication, and the
timestamp-query resolve/readback itself. GPU contention during each interval
can still affect the measurements. These are one-shot diagnostic costs, not
whole-frame or steady-state renderer costs. Every request still rebuilds its
acceleration structures; no persistent geometry cache or current-frame
pre-shading depth schedule has been implemented.

`NativeMapRayProbe.CompleteDepth()` optionally reports these timings when the
loaded DLL exposes them, preserving compatibility with earlier probe builds.
Fresh native outputs are in `artifacts/npr/ray-timestamps`. Both compiled with
`/W4 /WX`, the managed project built with zero warnings/errors, and the CPU-only
`check_ray_scene_abi.py --directory artifacts/npr/ray-timestamps` checks passed.
The timing export was not live-measured in the preliminary diagnostic above.
