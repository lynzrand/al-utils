// CPU-built smoke: submit native compute against a Unity-owned UAV buffer.
// No direct queue submission, CPU GPU-wait, device creation, or game hooks.
#define NOMINMAX
#include <windows.h>
#include <d3d12.h>
#include <dxgi.h>
#include <wrl/client.h>
#include <IUnityInterface.h>
#include <IUnityGraphics.h>
#include <IUnityGraphicsD3D12.h>
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <deque>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>

using Microsoft::WRL::ComPtr;
#define API extern "C" __declspec(dllexport)
static void Check(HRESULT hr, const char* operation)
{
    if (FAILED(hr)) {
        char message[192]; sprintf_s(message,"%s HRESULT=0x%08lx",operation,hr);
        throw std::runtime_error(message);
    }
}
struct Write {
    ComPtr<ID3D12Resource> buffer;
    uint32_t count = 0, seed = 0;
    uint64_t ticket = 0, fence = 0;
    ComPtr<ID3D12CommandAllocator> allocator;
    ComPtr<ID3D12GraphicsCommandList> commands;
};
struct State {
    std::mutex mutex;
    IUnityGraphics* graphics = nullptr;
    IUnityGraphicsD3D12v7* v7 = nullptr;
    IUnityGraphicsD3D12v6* v6 = nullptr;
    int eventId = -1;
    std::vector<unsigned char> shader;
    ComPtr<ID3D12Device> device;
    ComPtr<ID3D12Fence> frameFence;
    ComPtr<ID3D12RootSignature> root;
    ComPtr<ID3D12PipelineState> pipeline;
    std::deque<Write> pending, inflight;
    uint64_t next = 1, submitted = 0, retired = 0, failed = 0;
    std::string message = "awaiting UnityPluginLoad";
};
// Kept allocated if an unsafe unload occurs, so COM resources still in GPU use
// are not released by module-static destruction. Normal unload deletes it.
static State* state = new State;

static void Initialize(State& s)
{
    if (s.device) return;
    if (!s.graphics || s.graphics->GetRenderer() != kUnityGfxRendererD3D12)
        throw std::runtime_error("Active Unity renderer is not D3D12");
    auto* device = s.v7 ? s.v7->GetDevice() : s.v6 ? s.v6->GetDevice() : nullptr;
    auto* fence = s.v7 ? s.v7->GetFrameFence() : s.v6 ? s.v6->GetFrameFence() : nullptr;
    if (!device || !fence) throw std::runtime_error("Unity D3D12 device/fence unavailable");
    if (s.shader.empty()) throw std::runtime_error("Call ALVIS_SetShader before issuing write events");
    D3D12_FEATURE_DATA_SHADER_MODEL model{D3D_SHADER_MODEL_6_0};
    Check(device->CheckFeatureSupport(D3D12_FEATURE_SHADER_MODEL,&model,sizeof(model)),"Query SM6");
    if (model.HighestShaderModel < D3D_SHADER_MODEL_6_0) throw std::runtime_error("SM6 unavailable");
    D3D12_ROOT_PARAMETER parameters[2]{};
    parameters[0].ParameterType = D3D12_ROOT_PARAMETER_TYPE_UAV;
    parameters[0].Descriptor = {0,0};
    parameters[1].ParameterType = D3D12_ROOT_PARAMETER_TYPE_32BIT_CONSTANTS;
    parameters[1].Constants = {0,0,2};
    D3D12_ROOT_SIGNATURE_DESC desc{2,parameters,0,nullptr,D3D12_ROOT_SIGNATURE_FLAG_NONE};
    ComPtr<ID3DBlob> serialized, errors;
    Check(D3D12SerializeRootSignature(&desc,D3D_ROOT_SIGNATURE_VERSION_1,&serialized,&errors),"Serialize root");
    ComPtr<ID3D12RootSignature> root;
    Check(device->CreateRootSignature(0,serialized->GetBufferPointer(),serialized->GetBufferSize(),
        IID_PPV_ARGS(&root)),"Create root");
    D3D12_COMPUTE_PIPELINE_STATE_DESC pso{};
    pso.pRootSignature = root.Get(); pso.CS = {s.shader.data(),s.shader.size()};
    ComPtr<ID3D12PipelineState> pipeline;
    Check(device->CreateComputePipelineState(&pso,IID_PPV_ARGS(&pipeline)),"Create compute PSO");
    // ExecuteCommandList owns submission ordering. We do not ask for raw queue
    // access, nor for a CPU/GPU flush. No active render texture is needed.
    UnityD3D12PluginEventConfig config{};
    config.graphicsQueueAccess = kUnityD3D12GraphicsQueueAccess_DontCare;
    config.flags = 0; config.ensureActiveRenderTextureIsBound = false;
    if (s.v7) s.v7->ConfigureEvent(s.eventId,&config);
    else s.v6->ConfigureEvent(s.eventId,&config);
    s.device = device; s.frameFence = fence; s.root = root; s.pipeline = pipeline;
}

static void Submit(State& s, Write& write)
{
    const auto desc = write.buffer->GetDesc();
    D3D12_HEAP_PROPERTIES heap{}; D3D12_HEAP_FLAGS heapFlags{};
    Check(write.buffer->GetHeapProperties(&heap,&heapFlags),"Get buffer heap");
    if (desc.Dimension != D3D12_RESOURCE_DIMENSION_BUFFER
        || !(desc.Flags & D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS)
        || heap.Type != D3D12_HEAP_TYPE_DEFAULT || desc.Width < uint64_t(write.count)*4
        || !write.buffer->GetGPUVirtualAddress())
        throw std::runtime_error("Expected default-heap UAV buffer with count*4 available bytes");
    ComPtr<ID3D12Device> owner;
    Check(write.buffer->GetDevice(IID_PPV_ARGS(&owner)),"Get resource device");
    ComPtr<IUnknown> a,b; Check(owner.As(&a),"Buffer device identity");
    Check(s.device.As(&b),"Unity device identity");
    if (a.Get() != b.Get()) throw std::runtime_error("Buffer belongs to another device");
    Check(s.device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,
        IID_PPV_ARGS(&write.allocator)),"Create allocator");
    Check(s.device->CreateCommandList(0,D3D12_COMMAND_LIST_TYPE_DIRECT,write.allocator.Get(),
        s.pipeline.Get(),IID_PPV_ARGS(&write.commands)),"Create command list");
    write.commands->SetComputeRootSignature(s.root.Get());
    write.commands->SetComputeRootUnorderedAccessView(0,write.buffer->GetGPUVirtualAddress());
    const uint32_t constants[] = {write.count,write.seed};
    write.commands->SetComputeRoot32BitConstants(1,2,constants,0);
    write.commands->Dispatch((write.count+63)/64,1,1);
    D3D12_RESOURCE_BARRIER barrier{};
    barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_UAV; barrier.UAV.pResource = write.buffer.Get();
    write.commands->ResourceBarrier(1,&barrier);
    Check(write.commands->Close(),"Close commands");
    UnityGraphicsD3D12ResourceState usage{write.buffer.Get(),D3D12_RESOURCE_STATE_UNORDERED_ACCESS,
        D3D12_RESOURCE_STATE_UNORDERED_ACCESS};
    write.fence = s.v7 ? s.v7->ExecuteCommandList(write.commands.Get(),1,&usage)
        : s.v6->ExecuteCommandList(write.commands.Get(),1,&usage);
    // A zero result cannot safely authorize releasing submitted resources. Keep
    // them until unload if Unity does not return a usable completion fence.
    if (!write.fence) write.fence = UINT64_MAX;
}

static void UNITY_INTERFACE_API OnRender(int eventId)
{
    State* s = state;
    if (!s) return;
    std::lock_guard<std::mutex> lock(s->mutex);
    if (eventId != s->eventId) return;
    try {
        Initialize(*s);
        auto completed = s->frameFence->GetCompletedValue();
        if (completed == UINT64_MAX) throw std::runtime_error("Unity device/fence removed");
        while (!s->inflight.empty() && s->inflight.front().fence <= completed) {
            s->retired = s->inflight.front().ticket; s->inflight.pop_front();
        }
        if (!s->pending.empty()) {
            // Reserve lifetime ownership before calling Unity's submission API.
            s->inflight.push_back(std::move(s->pending.front())); s->pending.pop_front();
            auto& write = s->inflight.back();
            try { Submit(*s,write); }
            catch (...) { s->failed = write.ticket; s->inflight.pop_back(); throw; }
            s->submitted = write.ticket;
        }
        s->message = "event processed; readback must verify contents/order";
    } catch (const std::exception& e) { s->message = e.what(); }
}

API void UNITY_INTERFACE_API UnityPluginLoad(IUnityInterfaces* registry)
{
    if (!state) state = new State;
    std::lock_guard<std::mutex> lock(state->mutex);
    if (state->graphics) { state->message = "already registered"; return; }
    if (!registry) { state->message = "null Unity interface registry"; return; }
    state->graphics = registry->Get<IUnityGraphics>();
    state->v7 = registry->Get<IUnityGraphicsD3D12v7>();
    if (!state->v7) state->v6 = registry->Get<IUnityGraphicsD3D12v6>();
    if (!state->graphics || (!state->v7 && !state->v6)) {
        state->graphics = nullptr; state->message = "Unity graphics/D3D12 v7/v6 unavailable"; return;
    }
    state->eventId = state->graphics->ReserveEventIDRange(1);
    state->message = state->v7 ? "registered D3D12 v7; awaiting render event" : "registered D3D12 v6; awaiting render event";
}
API void UNITY_INTERFACE_API UnityPluginUnload()
{
    // Host must stop issuing events and call CanUnload before explicit unloading.
    // On an unsafe unload intentionally retain referenced resources, not a fence wait.
    State* old = state; state = nullptr;
    if (old && old->pending.empty() && old->inflight.empty()) delete old;
}
API int ALVIS_SetShader(const void* bytes, uint32_t length)
{
    if (!state || !bytes || length < 32 || length > 16*1024*1024) return 0;
    std::lock_guard<std::mutex> lock(state->mutex);
    if (state->device || !state->pending.empty() || !state->inflight.empty()) return 0;
    const auto* first = static_cast<const unsigned char*>(bytes);
    if (memcmp(first,"DXBC",4)) return 0;
    state->shader.assign(first,first+length); return 1;
}
API uint64_t ALVIS_QueueWrite(void* buffer, uint32_t count, uint32_t seed)
{
    if (!state || !buffer || !count || count > 65535u*64u) return 0;
    std::lock_guard<std::mutex> lock(state->mutex);
    if (!state->graphics || state->shader.empty() || state->pending.size()+state->inflight.size() >= 8) return 0;
    Write write; write.buffer = static_cast<ID3D12Resource*>(buffer);
    write.count = count; write.seed = seed; write.ticket = state->next++;
    uint64_t ticket = write.ticket; state->pending.push_back(std::move(write)); return ticket;
}
API UnityRenderingEvent ALVIS_GetRenderEventFunc() { return OnRender; }
API int ALVIS_GetEventId() { return state ? state->eventId : -1; }
API int ALVIS_CanUnload()
{
    if (!state) return 1;
    std::lock_guard<std::mutex> lock(state->mutex);
    return state->pending.empty() && state->inflight.empty();
}
API uint32_t ALVIS_GetStatus(char* output, uint32_t capacity)
{
    if (!output || !capacity) return 0;
    if (!state) { output[0] = 0; return 0; }
    std::lock_guard<std::mutex> lock(state->mutex);
    char text[1024];
    int length = sprintf_s(text,"event=%d interface=%d initialized=%d pending=%zu inflight=%zu submitted=%llu retired=%llu failed=%llu message=%s",
        state->eventId,state->v7 ? 7 : state->v6 ? 6 : 0,state->device ? 1 : 0,
        state->pending.size(),state->inflight.size(),state->submitted,state->retired,state->failed,state->message.c_str());
    uint32_t copied = (std::min)(uint32_t(length),capacity-1);
    memcpy(output,text,copied); output[copied] = 0; return copied;
}
