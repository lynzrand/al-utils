# Map light visibility smoke test

`build_map_visibility_smoke.cmd` compiles the standalone harness and
`Visibility/MapLightVisibility.slang` using CMake, Slang and the Windows SDK DXIL compiler.
It does not run either artifact. Paths in the build script are machine-specific.

From the repository root, when GPU execution is scheduled explicitly:

```powershell
& .\AL_NPR\tools\build_map_visibility_smoke.cmd
& .\artifacts\npr\map-visibility\map_visibility_smoke.exe --run .\artifacts\npr\map-visibility\MapLightVisibility.dxil
```

The GPU modes select the first high-performance DXR 1.1 / SM6.5 adapter,
enable the D3D12 debug layer if installed, and create their own device. The
harness runs outside Unity and reads exported files in scene mode.

The complete synthetic scene is a square made of two opaque triangles at z=2.
All six light tests use the same BLAS/TLAS and receiver resources:

- Directional +Z: the receiver at the origin is occluded.
- Punctual at z=4: occluded by the same square.
- Punctual at z=1: visible because the finite ray stops before the square.
- Directional with a disjoint caster rendering mask: visible.
- Directional with a disjoint receiver rendering mask: unaffected status.
- A zero directional vector: invalid status, not certified visible.

Each dispatch also checks an invalid receiver, an excluded receiver GameObject
layer, and a receiver at x=10 whose ray misses the square. The 24 output pairs are
compared exactly to expected visibility/status values. Exit code 0 means all
checks passed; 1 means a result mismatch; 2 means setup/execution failed. A GPU
timeout terminates without releasing in-flight resources. The debug layer can
report API issues to a debugger; output-pair assertions do not certify that its
message queue is empty.

This proves only the synthetic opaque visibility and binding path when run.
Compilation alone does not prove GPU execution. It does not establish AL device
interop, real receiver extraction, animated or alpha-aware casters, complete map
geometry, per-frame synchronization, visual parity, or a frame-time budget.

## Frozen scene snapshots

The executable also accepts the exporter's little-endian `ALVIS001` format:

1. Eight ASCII magic bytes, followed by five uint32 counts: vertices, indices,
   ranges, receivers, lights.
2. Packed float3 world vertices; global uint32 triangle indices.
3. Packed uint4 ranges: first index, index count, one-hot GameObject layer,
   rendering layers. Ranges must cover the index array consecutively.
4. Packed 48-byte receivers: float4 world position, float4 world geometric normal,
   uint4 flags matching the kernel contract.
5. Packed 48-byte `MapLight` records matching the kernel contract.

```powershell
# CPU-only structure validation; no graphics device is created.
& .\artifacts\npr\map-visibility\map_visibility_smoke.exe --validate-scene snapshot.bin

# Explicitly scheduled GPU execution for authored light index 0.
& .\artifacts\npr\map-visibility\map_visibility_smoke.exe --run-scene .\artifacts\npr\map-visibility\MapLightVisibility.dxil snapshot.bin 0 visibility.bin
```

Snapshot mode builds one BLAS and one identity-transform TLAS instance per mask
range. The range index becomes InstanceID. All instances use hardware mask 255;
the kernel checks the supplied GameObject/rendering masks independently. Bounds
derive from all world vertices, padded by max(0.001, axis extent * 0.00001).
The experiment uses 0.001 world-unit normal and ray biases; these are provisional,
not AL-calibrated shadow settings. It never treats camera pixels as caster geometry.

Receivers retain input order, tiled at width min(receiverCount, 16384). Padding
texels are invalid and excluded from output. Only the selected light is dispatched.
Input size is limited to 1 GiB, with nonempty arrays and at most 16384 squared
receivers. Structure, finite caster vertices, index bounds, contiguous ranges and
one-hot GameObject masks are checked before device creation. This validation does
not establish that the exporter captured every caster or current animation pose.

Output is eight ASCII bytes `ALVOUT01`, uint32 receiverCount, uint32 selectedLight,
then receiverCount packed float2 visibility/status pairs in original receiver
order. The console separately counts valid visible, valid occluded, unaffected,
invalid and malformed outputs. Invalid samples are reported, not silently counted
as visible. Exit 0 means structurally valid output, not zero invalid samples or a
visual correctness claim; malformed GPU pairs cause exit 1. Output is overwritten
when explicitly requested but may not alias either input file.
## Isolated AL map validation

`AL_NPR.VisibilitySnapshot.Save(path)` exports the scene on demand through the
development REPL. The diagnostic includes offscreen casters, bakes skinned
meshes at capture time, and reads the existing GPU vertex and index buffers
when an opaque-classified mesh has no CPU copy. It uses a synchronous readback
once per unique mesh during the snapshot.

In `map001` on the RTX 5070 Ti, two snapshots used the same map and receiver
positions with scaled time paused. The renderer's `_MainLightPosition` changed
from `Directional Light Far` to `Directional Light Chara`. The four authored
map light records, triangle indexes, masks, and receivers matched byte for
byte. Some vertex positions still moved between captures by up to 0.00365
world units on one component.

The scene contained 133,425 exported triangles from 315 casters, including
261 offscreen casters. Reading 13 unique GPU-only meshes recovered 207 casters.
The exporter skipped 864 submeshes based on render queue, alpha keyword, or
topology. The experiment traces the captured triangles as fully opaque and
two-sided.

| Authored light | Visible | Occluded |
| --- | ---: | ---: |
| Directional Light Far | 86 | 285 |
| Directional Light Sky | 66 | 305 |
| Directional Light Ground | 1 | 370 |
| Spot Light Sun Main | 91 | 280 |

Each pair of output buffers matched byte for byte, yielding 1,484 matching
light–receiver results with zero invalid outputs. The rays measure geometric
visibility. Shading still supplies incidence, light color, spot cones,
range attenuation, and artistic response. This test uses sparse samples on
map geometry and leaves live skin rendering and 4K frame times unmeasured.

The separate `AL_NPR.UnityRayTracing.Probe()` REPL diagnostic created a Unity
acceleration structure from one real `map001` house renderer. Unity reported
one instance and 393,216 bytes. On the same in-process D3D12 device, the
driver reported DXR 1.2 and support for shader model 6.5. Unity 6000.0.65f1
reported support for ray-tracing shaders and reported inline queries
unavailable. The probe tests acceleration-structure creation and does
not dispatch a Unity ray or change the renderer's lighting.

`AL_NPR.UnityRayTracing.ProbeDevice(path)` compares the Unity flags and
the underlying D3D12 capabilities. Pass the absolute path of
`dxr_device_probe.dll` from the build above.
