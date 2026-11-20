# Unity original-mesh inline-ray probe

## Multi-mesh scene submission

The native module also exports `ALRAY_QueueScene(meshes, meshCount, rays,
rayCount)`. The depth build exports `ALRAY_QueueDepthScene(meshes, meshCount,
depth, frame)`. Both return a uint64 ticket, accept a contiguous array of the
112-byte `MeshRequest` below, and accept 1 through 4096 descriptors. Every
descriptor must name the same output resource. The original `QueueMesh` and
`QueueDepth` entry points are preserved as single-descriptor wrappers.

The request copies all descriptors and retains their vertex/index/output
resources before returning. Each mesh becomes an opaque BLAS and a transformed
TLAS instance. Mesh resources shared between descriptors receive one Unity
resource-state entry. Resources are retained until the existing frame-fence
retirement path releases the complete request. Each AS remains bounded to
512 MiB and all owned allocations combined are bounded to 2 GiB per request.
Up to four requests may be queued or in flight, as before.

This is a frozen-scene correctness foundation. It rebuilds all BLAS structures
on every request, including identical meshes, and is not a production per-frame
path. The host still selects opaque casters and supplies current deformation
buffers for animated meshes. Cutout/transparency filtering and light-specific
caster masks are not implemented. The depth shader still traces only its
directional list; punctual light distances and spot cones are separate work.
Clothing and map receivers still need their own shader integration.

Both native variants compile with `/W4 /WX`. Run
`python AL_NPR/tools/check_ray_scene_abi.py` for CPU-only ABI/export and rejection
checks. These checks cover the new entry points and original wrappers, but do
not establish GPU state ordering, multi-mesh occlusion, or visual correctness.
The recovered live checks below demonstrate transformed-instance occlusion
and compare the single-mesh wrapper with a one-element scene request.

This is a separate module from `ALVisibilityInterop.dll`. Build only with
`build_unity_visibility_ray_probe.cmd`. Outputs:

- `artifacts/npr/unity-ray-probe/ALVisibilityRayProbe.dll`
- `artifacts/npr/unity-ray-probe/UnityRayProbe.dxil`

No game/device/GPU execution occurs during the build. The module queries native
DXR 1.1 and SM6.5 capabilities on Unity's actual device. It does not use or change
Unity's managed inline-ray capability flag.

## Exact Windows x64 ABI

```cpp
void UnityPluginLoad(IUnityInterfaces* actualLiveRegistry);
void UnityPluginUnload();
int ALRAY_SetShader(const void* dxilBytes, uint32_t length);
uint64_t ALRAY_QueueMesh(const MeshRequest*, const ProbeRay*, uint32_t rayCount);
UnityRenderingEvent ALRAY_GetRenderEventFunc(); // callback void(int)
int ALRAY_GetEventId();
uint32_t ALRAY_GetStatus(char* output, uint32_t capacityIncludingNul);
uint32_t ALRAY_CancelPending();
int ALRAY_CanUnload();
```

Exports use C linkage; ALRAY functions are cdecl. Unity entry points/callback use
UNITY_INTERFACE_API (the conventions coincide on Windows x64). The request is
**112 bytes**, explicitly packed to 8-byte alignment:

| Offset | Type | Field |
|---:|---|---|
| 0 | pointer | Original `ID3D12Resource*` vertex buffer |
| 8 | pointer | Original `ID3D12Resource*` index buffer |
| 16 | pointer | Unity output buffer resource |
| 24 | uint64 | Position byte offset in vertex resource |
| 32 | uint64 | First triangle index byte offset |
| 40 | uint32 | Position stride, bytes |
| 44 | uint32 | Vertex count addressable from position offset |
| 48 | uint32 | Triangle index count, multiple of 3 |
| 52 | uint32 | Index bits: 16 or 32 |
| 56 | float[12] | Object-to-world row-major affine 3x4 |
| 104 | uint64 | Reserved; must be zero |

Transform order is `m00,m01,m02,m03,m10,m11,m12,m13,m20,m21,m22,m23`.
Each `ProbeRay` is 32 bytes: float3 world origin at 0, float tMin at 12,
float3 world direction at 16, float tMax at 28. QueueMesh copies request/rays
synchronously and AddRefs resources; those CPU arrays need not remain pinned.
Returns a nonzero ticket on accepted request, zero on rejection. Count is 2..4096.

Output must be a Unity UAV structured buffer of uint, stride 4, with at least
rayCount elements. Results are `0=miss`, `1=opaque triangle hit`, `2=invalid ray`.
Directions must be unit length (squared-length tolerance 0.001). Origins and ray
intervals must be finite, tMin>=0, tMax>tMin; invalid rays return 2.

## Mesh/resource contract

Use genuine original GPU buffer resources, not CPU arrays, Unity object pointers
or texture handles. Positions must be packed float32 xyz at the supplied offset
within each stride; interleaved attributes are allowed. Index values must lie
inside the supplied vertex domain. The host must audit index values/baseVertex:
the native code validates resource byte ranges but cannot certify GPU index
contents without a separate readback. A nonzero submesh baseVertex must be
represented consistently by the vertex offset/domain, not ignored. No topology
other than an indexed triangle list is accepted.

All resources must belong to the same actual Unity D3D12 device and use default
heaps. The output must allow unordered access and may not alias either mesh
resource. Vertex and index may share a buffer; its tracking entry is deduplicated.
The native code submits resource-state requirements through Unity:

- Vertex/index: expected and final `NON_PIXEL_SHADER_RESOURCE`, required for AS
  build inputs. The caller need not manually transition a Unity buffer to that
  state; Unity's ExecuteCommandList state tracking is being tested.
- Output: expected and final `UNORDERED_ACCESS`, followed by a native UAV barrier.

The probe builds one opaque BLAS and one TLAS instance with the supplied affine
transform. Rays are two-sided, without alpha tests or material/layer filtering.
No geometry is inferred from screen pixels. Original vertices must be finite and
represent the intended frozen pose. Ordinary mesh buffers do not automatically
contain a SkinnedMeshRenderer's deformed vertices. GPU producers of dynamic data
must precede the event correctly; this first experiment should use a static map
mesh. Each AS allocation is capped at 512 MiB and at most four requests can be
queued/inflight. This rebuild-per-request probe is not a production frame budget.

## Event ordering and acceptance

1. Register the DLL using the actual registry pointer and SetShader with DXIL.
2. Issue **one empty warm-up render event**. It initializes the native PSO/device
   and configures subsequent events with `FlushCommandBuffers | SyncWorkerThreads`.
   Wait for status `initialized=1` before QueueMesh; pre-warm-up requests reject.
3. QueueMesh, then issue its plugin event in the intended Unity command stream.
   Submit a Unity readback/consumer after it. Test at least a known hit and miss
   against a triangle whose position/transform were verified by the host. Add a
   short ray that stops before the triangle to verify finite-interval behavior.
4. Compare same-command-buffer consumption with a later-frame consumer. A prior
   write smoke showed ExecuteCommandList alone can execute before an unsubmitted
   Unity producer/consumer command list. The event's new submission-boundary flags
   are an experimental correction, **not verified ordering evidence yet**.
5. Issue a later empty event to retire resources by Unity frame-fence completion.
   Keep Unity mesh/output objects and their buffers stable until native retirement
   and all Unity consumers/readbacks complete. Releasing a GraphicsBuffer wrapper
   or modifying/uploading the mesh may invalidate the resource contract.

The configuration flushes/submits command buffers and synchronizes CPU recording
workers; it does not wait for GPU completion or perform a per-event readback.
Native commands are submitted only via ExecuteCommandList. All AS/input upload/
scratch/allocator resources remain retained until its returned Unity frame fence
completes. The installed v7 interface has no public RequestResourceState function;
direct recording into Unity's active command list is not attempted here.

One event consumes at most one request. Status alone proves neither GPU success
nor visibility correctness. CancelPending releases only unsubmitted requests.
Before unload, stop queuing callbacks and concurrent ABI calls, retire inflight
work, and require CanUnload=1. It does not track callbacks still queued by Unity.
Unsafe unload retains COM references instead of freeing GPU-live resources; no
device-reset/renderer-switch recovery is implemented.

A passing test establishes native inline queries against this mesh on Unity's
device and the tested ordering. It does not establish complete map shadows,
animated or alpha-aware casters, skin integration, graphics parity or performance.

## Isolated AL result

The AL 1.0.4 Unity player supplied both D3D12 interfaces. The diagnostic
used v7, created the native BLAS/TLAS from the original GPU buffers of
`o_al_m01_house00_00 (1)` submesh 0, and tested 58 triangles in `map001`.
Both the same-command readback and a later Unity readback returned
`[1, 1, 0, 2]` for two hits, an outside miss and an invalid ray. The
separate write smoke without a submission boundary returned only the input
values. Warm-up and the submission-boundary flags are part of the path
that passed.

The same build emits `ALDepthVisibility.dll` and `UnityDepthRayVisibility.dxil`.
The on-demand `AL_NPR.NativeMapRayProbe.WarmUpDepth` and `TraceDepth` diagnostic
dispatches against a single opaque map submesh using paused MainCamera depth.
`TraceDepth(0)` selects geometric visibility and a nonzero value selects
an explicit binding-test bitmask. The skin shader consumes only samples
whose depth bits match its rasterized fragment. This is a frozen-camera
experiment with a single caster and a diagnostic readback.

## Recovered multi-mesh results, 2026-11-16

`TraceSceneComparison(includeSecond, legacyWrapper)` caches one verified map
surface across control runs. A second descriptor references the same original
GPU buffers with a translated transform outside the first renderer's bounds.
The probe checks two original hits, a hit at the translated instance, a short
ray stopping before that instance, and an invalid ray. The source mesh is not
moved in the game. Destroying the cached surface on a map transition rejects
the comparison rather than silently testing different geometry.

On `map002`, the two-descriptor test returned `[1, 1, 1, 0, 2]`; omitting only
the translated instance returned `[1, 1, 0, 0, 2]`. Both same-command-buffer and
later readbacks matched. A scene transition then destroyed the cached mesh
and correctly rejected the next control. On `map001`, the one-element scene
request and original wrapper both returned `[1, 1, 0, 0, 2]` using the same
`o_al_m01_house00_00 (1)` submesh 0, containing 58 triangles.

`TraceMapGeometry()` exercises the scene collector without shading bindings.
It audits GPU index ranges/positions, includes offscreen map renderers, keeps
their transforms and submits one descriptor per eligible submesh. Its first
`map001` run submitted 311 submeshes and 117,993 triangles, with 105 offscreen
submeshes. The known triangle hit from both sides, the outside ray missed,
and the invalid ray was rejected: `[1, 1, 0, 2]` in both readbacks. Native status
reported no failed requests. Logs are under `artifacts/npr/recovery-probe-map`.

The collector omitted 782 alpha or missing-material submeshes in this run.
It filters render queue and `_ALPHATEST_ON`; this does not prove texture
opacity or reproduce shader-specific discard/deformation. Collected triangles
are treated as opaque. That run used only rigid Map-layer renderers; the later
frozen-character test below extends this coverage. Cutouts, per-light caster
masks and continuous updates remain unfinished.
These results establish the tested GPU geometry path, not finished shadows
or a frame-time improvement. The diagnostic runtime copies use distinct
namespaces under `artifacts/npr/recovery-*` so they can be loaded through the
REPL without replacing the older running lighting DLL.

## Frozen character and depth readback, 2026-11-16

`TraceDepthScene(0, true)` includes a frozen character snapshot. The collector
uses `BakeMesh(false)` and retains the baked mesh and graphics buffers through
native retirement. It respects enabled state, `forceRenderingOff` and shadow
casting mode, includes the separate face shadow proxy, and permits the body's
queue-2450 skin material as an explicit opaque approximation. Alpha hair and
other rejected cutout materials remain omitted; this is not complete character
coverage.

The sun-only test submitted 323 submeshes, including 12 baked character
submeshes, and 152,871 triangles. Native readback reported 2,929,761 valid-depth
pixels and 1,848,159 pixels with the sun bit set, with no failed requests.
These are full-image counts, not skin-only shadow coverage. The bounded skin
receiver check produced visible head and hand self-shadowing, along with
unresolved triangle artifacts. See `README.skin-map-ray-visibility.md`.

Unity's `AsyncGPUReadback` rejected RG32 UInt in this player. The depth variant
therefore copies its output to a native READBACK heap after dispatch and polls
the existing Unity frame fence in `ALRAY_ReadDepthSummary`. It honors the placed
footprint's row pitch and never waits synchronously for the GPU. The request
owns the readback allocation; poll before retiring it. `CompleteDepth()` only
publishes a snapshot while time is paused and the captured camera matrices
still match. `ClearDepth()` disables publication and retires resources through
a later event before releasing Unity objects.

The readback layout follows Microsoft's [readback heap documentation](https://learn.microsoft.com/en-us/windows/win32/direct3d12/readback-data-using-heaps)
and [GetCopyableFootprints contract](https://learn.microsoft.com/en-us/windows/win32/api/d3d12/nf-d3d12-id3d12device-getcopyablefootprints).
This diagnostic readback and full AS rebuild are not a steady-state ray-shadow
benchmark. Both native variants compiled with `/W4 /WX`; the ABI checks include
the new readback export's invalid-ticket behavior.
