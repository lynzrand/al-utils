# Retained ray scene diagnostic, 2026-11-17

The depth native probe now exposes `ALRAY_CreateScene`, `ALRAY_SceneReady`,
`ALRAY_ReleaseScene`, `ALRAY_QueueRetainedDepth` and `ALRAY_RequestsIdle`.
Scene descriptors use null output pointers. Creation queues an immutable BLAS/
TLAS build; readiness is fence checked. Requests retain the scene independently
of its public handle, so releasing that handle cannot destroy GPU-live structures.
Source geometry must remain unchanged until the build completes. Changed poses,
transforms or topology require a new capture. This is not an animation cache.

Managed sequence after `WarmUpDepth`, with animation paused and the ray consumer
active: `PrepareDepthScene(true)`, wait for the render event/build, then
`TraceDepthScene(0,true)` and `CompleteDepth()` on a later frame. To repeat,
call `ClearDepthQuery()` until native requests are idle, then trace again.
`ClearDepth()` also releases the scene; repeat until native requests are idle
to release the managed capture and target. Keep the scene frozen throughout.
The native nondiagnostic query mode skips timestamps and texture readback; it
has compiled but has not been live tested or scheduled before shading.

## Live comparison

Evidence: `artifacts/npr/retained-ray-20261117`. map001, 2560x1440,
8x MSAA, three directional rays, receiver-reprojection shader. Captured 320
opaque-approximation submeshes (9 baked character submeshes), 145,105 triangles;
790 alpha/missing-material submeshes omitted. These omissions remain material.

| Query | AS interval | Trace | Diagnostic output copy |
| --- | ---: | ---: | ---: |
| Retained 1 | 0.001 ms | 0.945 ms | 2.141 ms |
| Retained 2 | 0.002 ms | 1.124 ms | 2.188 ms |
| Fresh rebuild | 40.175 ms | 0.933 ms | 2.316 ms |

All three returned 3,535,902 valid pixels and 3,535,894 pixels with at least one
occluded directional. That count does not mean every light is blocked. Full
screenshots differed at only 17 pixels between repeats and 6 pixels between
retained 1 and fresh; mean absolute channel differences were 0.00000317 and
0.000000723 respectively. This supports reuse equivalence in this frozen test,
not shadow correctness, animated updates, or real-time frame performance.

Both native variants built with `/W4 /WX`, both DXIL shaders compiled with
warnings as errors, managed builds passed without warnings/errors, and extended
CPU ABI/preinitialization checks passed. Live retirement reached zero pending,
inflight and scene handles after the reuse comparison.

## Polygon seam diagnosis

The user observed bright triangle edges on neck, chest and fingers. They are
also visible in the captured ray result. A control with `testMask=7` bypasses
all ray intersections and forces all three directional bits: the seams remain
with 8x MSAA. Repeating that control with MSAA=1 removes the visible seams.
See `forced7.png` and `forced7-msaa1.png`. The pose was frozen for both controls;
depth resolution and valid-pixel counts change with MSAA.

This isolates the visible seam problem to the MSAA depth/consumer path rather
than acceleration-structure reuse or ray intersections. The half-pixel plane
depth bound is not sufficient at triangle boundaries. A production solution
needs a coherent MSAA receiver/visibility design; simply widening the depth
tolerance risks accepting unrelated overlapping surfaces. No such fix or
continuous pre-shading render schedule has been implemented in this pass.

After controls, restored the accepted combined clothing/raster bundle,
animation time scale 1, and MSAA=8. Startup installation is unchanged.
