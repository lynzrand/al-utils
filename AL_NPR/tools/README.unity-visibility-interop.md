# Unity D3D12 visibility interop smoke

Build only with `build_unity_visibility_interop.cmd`. Outputs are
`artifacts/npr/unity-visibility-interop/ALVisibilityInterop.dll` and
`UnityInteropWrite.dxil`. The build does not load the DLL, create a device or run
GPU commands. The installed Unity 2022.3.22f1 PluginAPI headers define the ABI.

This milestone tests Unity-owned resource access and ordered native compute
submission. It deliberately has no RayQuery, BLAS/TLAS or shadow shading yet.
Unity's reported inline-ray capability is not queried or relied upon here.

## Exported ABI (Windows x64)

```cpp
void UnityPluginLoad(IUnityInterfaces* registry);
void UnityPluginUnload();
int ALVIS_SetShader(const void* dxilBytes, uint32_t length);
uint64_t ALVIS_QueueWrite(ID3D12Resource* buffer, uint32_t count, uint32_t seed);
UnityRenderingEvent ALVIS_GetRenderEventFunc(); // callback void(int eventId)
int ALVIS_GetEventId();
uint32_t ALVIS_GetStatus(char* utf8Output, uint32_t capacityIncludingNul);
int ALVIS_CanUnload();
```

Native `ALVIS_*` exports use C linkage/cdecl; Unity entry points and render
callback use UNITY_INTERFACE_API. These conventions share the Windows x64 ABI.
SetShader returns 1 on accepted copied input, 0 on rejection. QueueWrite returns
a nonzero ticket on acceptance, 0 on rejection; acceptance is not submission or
GPU success. Status reports submitted/retired/failed ticket values and messages.

Unity normally invokes UnityPluginLoad when registering a native rendering plugin.
If manually invoking it, its argument must be the actual live **IUnityInterfaces
registry pointer**, not a device, graphics-interface or managed-object pointer.
This smoke does not discover or infer that address. Load queries v7, then v6,
and reserves one event ID through IUnityGraphics. Device access and GPU object
creation occur only on the render callback. Supplying an invalid pointer cannot
be made safe by this ABI; do not probe guessed addresses.

## Managed acceptance sequence

1. Register/load the DLL and supply the compiled DXIL bytes to SetShader before
   the first queued write. Keep the DLL loaded throughout queued/rendered events.
2. Create a Unity ComputeBuffer with structured uint elements (stride 4), UAV
   support, and sufficient count. Pass its genuine GetNativeBufferPtr result.
   Native code checks buffer/default-heap/UAV roles, capacity and owning-device
   identity. Stride/structured semantics are a managed-side contract.
3. Initialize the buffer with known uint values. QueueWrite(buffer,count,seed).
4. Record CommandBuffer.IssuePluginEvent(GetRenderEventFunc(),GetEventId()) before
   a Unity consumer or command-buffer asynchronous readback. Submit that command
   buffer in the intended render phase. One event consumes at most one queued
   request; order queued requests and events explicitly.
5. Verify every output against `input[i] ^ seed ^ (0x9e3779b9u * i)` with uint32
   wraparound. Zero input produces the basic known pattern. A preceding Unity
   GPU producer with a different nonzero input, followed by native event and
   Unity consumer/readback in one command stream, is the stronger ordering test.
   Status text alone is insufficient evidence. Do not read before submission.
6. On a later frame, issue an additional event without a new request. This polls
   Unity's frame fence and retires completed resources; there is no CPU wait or
   explicit queue flush. Retain the managed buffer until the ticket is retired
   and its Unity consumers/readback are complete.

Submission calls Unity's ExecuteCommandList with expected and final resource
state UNORDERED_ACCESS. Unity owns surrounding transitions; the native list ends
with a UAV barrier. It does not submit to a raw queue, alter Unity's active
command list, or signal/wait on a private fence. Allocators, command lists and
the buffer COM reference remain alive until the returned Unity frame-fence value
completes. A zero returned fence retains the resources indefinitely for diagnosis.
At most eight queued/inflight writes are admitted; this is a smoke, not a
per-frame allocation strategy for the production shadow path.

Stop issuing events and stop concurrent ABI calls before explicit unload.
ALVIS_CanUnload must return 1; issue retirement events as needed. No device-reset
or renderer-switch recovery is implemented. An unsafe unload intentionally leaks
retained COM references instead of releasing resources possibly still in GPU use;
it is not a supported teardown path. Never unload while Unity has a callback
queued, even when CanUnload is 1 (that flag only reports native request ownership).

Compilation proves ABI/type/link consistency only. A successful runtime pattern
test would establish ordered compute access to this Unity buffer on the tested
device. It would not establish inline-ray support, shadow receiver extraction,
scene geometry completeness, animated/alpha-aware casters or frame-time cost.
