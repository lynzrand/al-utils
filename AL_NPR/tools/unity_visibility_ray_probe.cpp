// Independent Unity D3D12 mesh-buffer ray probe; no dependency on the write smoke.
#define NOMINMAX
#include <windows.h>
#include <d3d12.h>
#include <dxgi.h>
#include <wrl/client.h>
#include <IUnityInterface.h>
#include <IUnityGraphics.h>
#include <IUnityGraphicsD3D12.h>
#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <deque>
#include <mutex>
#include <memory>
#include <unordered_map>
#include <stdexcept>
#include <string>
#include <vector>
using Microsoft::WRL::ComPtr;
#define API extern "C" __declspec(dllexport)

// Explicit 8-byte ABI packing, Windows x64. Original GPU vertex/index buffers,
// not Unity objects or CPU array pointers. Position format must be float32 xyz.
#pragma pack(push,8)
struct MeshRequest {
    ID3D12Resource* vertices;
    ID3D12Resource* indices;
    ID3D12Resource* output;
    uint64_t positionByteOffset, indexByteOffset;
    uint32_t positionStride, vertexCount, indexCount, indexBits;
    float objectToWorld[12];
    uint64_t reserved;
};
struct ProbeRay { float origin[3], tMin, direction[3], tMax; };
struct DepthFrame {
    float clipToWorld[16], directions[32][4];
    uint32_t width, height, lightCount, testMask;
};
#pragma pack(pop)
static_assert(sizeof(MeshRequest)==112 && offsetof(MeshRequest,objectToWorld)==56
    && offsetof(MeshRequest,reserved)==104 && sizeof(ProbeRay)==32 && sizeof(DepthFrame)==592);

static void Check(HRESULT hr, const char* operation)
{
    if (FAILED(hr)) {
        char text[192]; sprintf_s(text,"%s HRESULT=0x%08lx",operation,hr);
        throw std::runtime_error(text);
    }
}
struct MeshInput {
    MeshRequest descriptor{};
    ComPtr<ID3D12Resource> vertices,indices;
};
// A handle owns an explicitly captured immutable scene, not a pointer-keyed
// cache. Requests retain it independently so release cannot free GPU-live AS.
struct RetainedScene {
    std::vector<ComPtr<ID3D12Resource>> structures;
    ComPtr<ID3D12Resource> tlas;
    uint64_t fence=0;
    bool failed=false;
};
struct Request {
    std::vector<MeshInput> meshes;
    ComPtr<ID3D12Resource> output;
    uint64_t allocatedBytes=0;
    std::shared_ptr<RetainedScene> scene;
    bool buildOnly=false,diagnostic=true;
#ifdef AL_DEPTH_RAYS
    ComPtr<ID3D12Resource> depth;
    ComPtr<ID3D12Resource> readback;
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint{};
    uint64_t readbackBytes=0;
    ComPtr<ID3D12DescriptorHeap> descriptors;
    DepthFrame frame{};
#else
    std::vector<ProbeRay> rays;
#endif
    std::vector<ComPtr<ID3D12Resource>> owned;
    ComPtr<ID3D12CommandAllocator> allocator;
    ComPtr<ID3D12GraphicsCommandList4> commands;
    ComPtr<ID3D12QueryHeap> timestamps;
    ComPtr<ID3D12Resource> timestampReadback;
    uint64_t ticket=0,fence=0;
};
struct State {
    std::mutex mutex;
    IUnityGraphics* graphics=nullptr;
    IUnityGraphicsD3D12v7* v7=nullptr;
    IUnityGraphicsD3D12v6* v6=nullptr;
    int eventId=-1;
    std::vector<unsigned char> shader;
    ComPtr<ID3D12Device5> device;
    ComPtr<ID3D12Fence> fence;
    ComPtr<ID3D12RootSignature> root;
    ComPtr<ID3D12PipelineState> pipeline;
    uint64_t timestampFrequency=0;
    std::deque<Request> pending,inflight;
    std::unordered_map<uint64_t,std::shared_ptr<RetainedScene>> scenes;
    uint64_t next=1,submitted=0,retired=0,failed=0;
    std::string message="awaiting UnityPluginLoad";
};
static State* state=new State;

static void Initialize(State& s)
{
    if (s.device) return;
    if (!s.graphics || s.graphics->GetRenderer()!=kUnityGfxRendererD3D12)
        throw std::runtime_error("Unity renderer is not D3D12");
    auto* base=s.v7?s.v7->GetDevice():s.v6?s.v6->GetDevice():nullptr;
    auto* fence=s.v7?s.v7->GetFrameFence():s.v6?s.v6->GetFrameFence():nullptr;
    if (!base || !fence || s.shader.empty()) throw std::runtime_error("Missing device/fence/DXIL");
    ComPtr<ID3D12Device5> device; Check(base->QueryInterface(IID_PPV_ARGS(&device)),"Query Device5");
    D3D12_FEATURE_DATA_D3D12_OPTIONS5 options{};
    Check(device->CheckFeatureSupport(D3D12_FEATURE_D3D12_OPTIONS5,&options,sizeof(options)),"DXR options");
    if (options.RaytracingTier<D3D12_RAYTRACING_TIER_1_1) throw std::runtime_error("DXR1.1 required");
    D3D12_FEATURE_DATA_SHADER_MODEL model{D3D_SHADER_MODEL_6_5};
    Check(device->CheckFeatureSupport(D3D12_FEATURE_SHADER_MODEL,&model,sizeof(model)),"Shader model");
    if (model.HighestShaderModel<D3D_SHADER_MODEL_6_5) throw std::runtime_error("SM6.5 required");
    auto* queue=s.v7?s.v7->GetCommandQueue():s.v6->GetCommandQueue();
    if (!queue) throw std::runtime_error("Unity graphics queue unavailable");
    Check(queue->GetTimestampFrequency(&s.timestampFrequency),"Graphics timestamp frequency");
    if (!s.timestampFrequency) throw std::runtime_error("Zero graphics timestamp frequency");
    D3D12_ROOT_PARAMETER parameters[4]{};
    parameters[0].ParameterType=D3D12_ROOT_PARAMETER_TYPE_SRV; parameters[0].Descriptor={0,0};
#ifdef AL_DEPTH_RAYS
    D3D12_DESCRIPTOR_RANGE ranges[2]{
        {D3D12_DESCRIPTOR_RANGE_TYPE_SRV,1,1,0,0},
        {D3D12_DESCRIPTOR_RANGE_TYPE_UAV,1,0,0,1}};
    parameters[1].ParameterType=D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
    parameters[1].DescriptorTable={2,ranges};
    parameters[2].ParameterType=D3D12_ROOT_PARAMETER_TYPE_CBV; parameters[2].Descriptor={0,0};
    D3D12_ROOT_SIGNATURE_DESC desc{3,parameters,0,nullptr,D3D12_ROOT_SIGNATURE_FLAG_NONE};
#else
    parameters[1].ParameterType=D3D12_ROOT_PARAMETER_TYPE_SRV; parameters[1].Descriptor={1,0};
    parameters[2].ParameterType=D3D12_ROOT_PARAMETER_TYPE_UAV; parameters[2].Descriptor={0,0};
    parameters[3].ParameterType=D3D12_ROOT_PARAMETER_TYPE_32BIT_CONSTANTS; parameters[3].Constants={0,0,1};
    D3D12_ROOT_SIGNATURE_DESC desc{4,parameters,0,nullptr,D3D12_ROOT_SIGNATURE_FLAG_NONE};
#endif
    ComPtr<ID3DBlob> bytes,errors;
    Check(D3D12SerializeRootSignature(&desc,D3D_ROOT_SIGNATURE_VERSION_1,&bytes,&errors),"Serialize root");
    ComPtr<ID3D12RootSignature> root;
    Check(device->CreateRootSignature(0,bytes->GetBufferPointer(),bytes->GetBufferSize(),IID_PPV_ARGS(&root)),"Create root");
    D3D12_COMPUTE_PIPELINE_STATE_DESC descPso{};
    descPso.pRootSignature=root.Get(); descPso.CS={s.shader.data(),s.shader.size()};
    ComPtr<ID3D12PipelineState> pipeline;
    Check(device->CreateComputePipelineState(&descPso,IID_PPV_ARGS(&pipeline)),"Create inline-ray PSO");
    UnityD3D12PluginEventConfig config{};
    config.graphicsQueueAccess=kUnityD3D12GraphicsQueueAccess_DontCare;
    // Split/submit Unity's existing producer commands before this callback.
    // This is not a GPU completion wait. A separate warm-up event must install
    // the configuration before any measured request is queued.
    config.flags=kUnityD3D12EventConfigFlag_FlushCommandBuffers
        | kUnityD3D12EventConfigFlag_SyncWorkerThreads;
    if (s.v7) s.v7->ConfigureEvent(s.eventId,&config); else s.v6->ConfigureEvent(s.eventId,&config);
    s.device=device; s.fence=fence; s.root=root; s.pipeline=pipeline;
}

static ComPtr<ID3D12Resource> Buffer(State& s,Request& r,uint64_t size,D3D12_HEAP_TYPE type,
    D3D12_RESOURCE_STATES initial,const void* upload=nullptr)
{
    // A scene can contain thousands of small BLAS allocations. Bound the
    // whole request as well as each individual AS before allocating memory.
    constexpr uint64_t budget=2ull*1024*1024*1024;
    if (size>budget-r.allocatedBytes) throw std::runtime_error("Scene probe exceeds 2GiB request budget");
    D3D12_HEAP_PROPERTIES heap{}; heap.Type=type;
    D3D12_RESOURCE_DESC desc{}; desc.Dimension=D3D12_RESOURCE_DIMENSION_BUFFER;
    desc.Width=size; desc.Height=1; desc.DepthOrArraySize=1; desc.MipLevels=1;
    desc.SampleDesc.Count=1; desc.Layout=D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    if (type==D3D12_HEAP_TYPE_DEFAULT) desc.Flags=D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS;
    ComPtr<ID3D12Resource> resource;
    Check(s.device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&desc,initial,nullptr,
        IID_PPV_ARGS(&resource)),"Create probe buffer");
    r.owned.push_back(resource); r.allocatedBytes+=size;
    if (upload) {
        void* data=nullptr; D3D12_RANGE empty{0,0}; Check(resource->Map(0,&empty,&data),"Map upload");
        memcpy(data,upload,size_t(size)); resource->Unmap(0,nullptr);
    }
    return resource;
}
static void UavBarrier(Request& r,ID3D12Resource* resource)
{
    D3D12_RESOURCE_BARRIER barrier{}; barrier.Type=D3D12_RESOURCE_BARRIER_TYPE_UAV;
    barrier.UAV.pResource=resource; r.commands->ResourceBarrier(1,&barrier);
}
static ComPtr<ID3D12Resource> Build(State& s,Request& r,
    const D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_INPUTS& input)
{
    D3D12_RAYTRACING_ACCELERATION_STRUCTURE_PREBUILD_INFO info{};
    s.device->GetRaytracingAccelerationStructurePrebuildInfo(&input,&info);
    if (!info.ResultDataMaxSizeInBytes || !info.ScratchDataSizeInBytes
        || info.ResultDataMaxSizeInBytes>512ull*1024*1024 || info.ScratchDataSizeInBytes>512ull*1024*1024)
        throw std::runtime_error("Probe AS size outside 512MiB safety bound");
    auto scratch=Buffer(s,r,info.ScratchDataSizeInBytes,D3D12_HEAP_TYPE_DEFAULT,D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    auto result=Buffer(s,r,info.ResultDataMaxSizeInBytes,D3D12_HEAP_TYPE_DEFAULT,D3D12_RESOURCE_STATE_RAYTRACING_ACCELERATION_STRUCTURE);
    D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_DESC desc{};
    desc.Inputs=input; desc.ScratchAccelerationStructureData=scratch->GetGPUVirtualAddress();
    desc.DestAccelerationStructureData=result->GetGPUVirtualAddress();
    r.commands->BuildRaytracingAccelerationStructure(&desc,0,nullptr); UavBarrier(r,result.Get());
    return result;
}
static void ValidateOwner(State& s, ID3D12Resource* resource)
{
    ComPtr<ID3D12Device> resourceDevice;
    ComPtr<IUnknown> owner,device;
    Check(resource->GetDevice(IID_PPV_ARGS(&resourceDevice)),"Get resource device");
    Check(resourceDevice.As(&owner),"Resource device identity");
    Check(s.device.As(&device),"Unity device identity");
    if (owner.Get()!=device.Get()) throw std::runtime_error("Resource belongs to another device");
}

static void ValidateResource(State& s,ID3D12Resource* resource,uint64_t required,bool output)
{
    auto desc=resource->GetDesc(); D3D12_HEAP_PROPERTIES heap{}; D3D12_HEAP_FLAGS flags{};
    Check(resource->GetHeapProperties(&heap,&flags),"Get Unity buffer heap");
    if (desc.Dimension!=D3D12_RESOURCE_DIMENSION_BUFFER || desc.Width<required
        || heap.Type!=D3D12_HEAP_TYPE_DEFAULT || !resource->GetGPUVirtualAddress()
        || output && !(desc.Flags&D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS))
        throw std::runtime_error("Wrong Unity buffer role/capacity/heap");
    ValidateOwner(s,resource);
}

#ifdef AL_DEPTH_RAYS
static void RecordDepthDispatch(State& s,Request& r,ID3D12Resource* tlas)
{
    const auto depth=r.depth->GetDesc();
    const auto output=r.output->GetDesc();
    const auto& frame=r.frame;
    const auto matches=[&](const D3D12_RESOURCE_DESC& resource) {
        return resource.Dimension==D3D12_RESOURCE_DIMENSION_TEXTURE2D
            && resource.SampleDesc.Count==1 && resource.DepthOrArraySize==1
            && resource.Width==frame.width && resource.Height==frame.height;
    };
    DXGI_FORMAT depthView=DXGI_FORMAT_UNKNOWN;
    if (depth.Format==DXGI_FORMAT_R32G8X24_TYPELESS || depth.Format==DXGI_FORMAT_D32_FLOAT_S8X24_UINT)
        depthView=DXGI_FORMAT_R32_FLOAT_X8X24_TYPELESS;
    else if (depth.Format==DXGI_FORMAT_R32_TYPELESS || depth.Format==DXGI_FORMAT_R32_FLOAT)
        depthView=DXGI_FORMAT_R32_FLOAT;
    if (!matches(depth) || !matches(output) || depthView==DXGI_FORMAT_UNKNOWN
        || depth.Flags&D3D12_RESOURCE_FLAG_DENY_SHADER_RESOURCE
        || output.Format!=DXGI_FORMAT_R32G32_UINT || !(output.Flags&D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS))
        throw std::runtime_error("Unexpected Unity camera depth or uint2 visibility texture format");
    ValidateOwner(s,r.depth.Get());
    ValidateOwner(s,r.output.Get());
    D3D12_DESCRIPTOR_HEAP_DESC heap{D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV,2,
        D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE,0};
    Check(s.device->CreateDescriptorHeap(&heap,IID_PPV_ARGS(&r.descriptors)),"Create visibility descriptors");
    auto handle=r.descriptors->GetCPUDescriptorHandleForHeapStart();
    D3D12_SHADER_RESOURCE_VIEW_DESC srv{};
    srv.Format=depthView; srv.ViewDimension=D3D12_SRV_DIMENSION_TEXTURE2D;
    srv.Shader4ComponentMapping=D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING; srv.Texture2D.MipLevels=1;
    s.device->CreateShaderResourceView(r.depth.Get(),&srv,handle);
    handle.ptr+=s.device->GetDescriptorHandleIncrementSize(heap.Type);
    D3D12_UNORDERED_ACCESS_VIEW_DESC uav{};
    uav.Format=DXGI_FORMAT_R32G32_UINT; uav.ViewDimension=D3D12_UAV_DIMENSION_TEXTURE2D;
    s.device->CreateUnorderedAccessView(r.output.Get(),nullptr,&uav,handle);
    auto parameters=Buffer(s,r,sizeof(frame),D3D12_HEAP_TYPE_UPLOAD,D3D12_RESOURCE_STATE_GENERIC_READ,&frame);
    ID3D12DescriptorHeap* heaps[]={r.descriptors.Get()};
    r.commands->SetDescriptorHeaps(1,heaps);
    r.commands->SetPipelineState(s.pipeline.Get());
    r.commands->SetComputeRootSignature(s.root.Get());
    r.commands->SetComputeRootShaderResourceView(0,tlas->GetGPUVirtualAddress());
    r.commands->SetComputeRootDescriptorTable(1,r.descriptors->GetGPUDescriptorHandleForHeapStart());
    r.commands->SetComputeRootConstantBufferView(2,parameters->GetGPUVirtualAddress());
    r.commands->Dispatch((frame.width+7)/8,(frame.height+7)/8,1);
    UavBarrier(r,r.output.Get());
    if (!r.diagnostic) return;
    r.commands->EndQuery(r.timestamps.Get(),D3D12_QUERY_TYPE_TIMESTAMP,2);
    // Unity's async texture readback rejects RG32 UInt in this player. Keep
    // this diagnostic copy native, with the exact uint2 bytes and row pitch.
    s.device->GetCopyableFootprints(&output,0,1,0,&r.footprint,nullptr,nullptr,&r.readbackBytes);
    r.readback=Buffer(s,r,r.readbackBytes,D3D12_HEAP_TYPE_READBACK,D3D12_RESOURCE_STATE_COPY_DEST);
    D3D12_RESOURCE_BARRIER barrier{};
    barrier.Type=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Transition={r.output.Get(),D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
        D3D12_RESOURCE_STATE_UNORDERED_ACCESS,D3D12_RESOURCE_STATE_COPY_SOURCE};
    r.commands->ResourceBarrier(1,&barrier);
    D3D12_TEXTURE_COPY_LOCATION source{};
    source.pResource=r.output.Get(); source.Type=D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    D3D12_TEXTURE_COPY_LOCATION destination{};
    destination.pResource=r.readback.Get(); destination.Type=D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
    destination.PlacedFootprint=r.footprint;
    r.commands->CopyTextureRegion(&destination,0,0,0,&source,nullptr);
    std::swap(barrier.Transition.StateBefore,barrier.Transition.StateAfter);
    r.commands->ResourceBarrier(1,&barrier);
    r.commands->EndQuery(r.timestamps.Get(),D3D12_QUERY_TYPE_TIMESTAMP,3);
}
#endif
static void Submit(State& s,Request& r)
{
    for (const auto& mesh:r.meshes) {
        const auto& m=mesh.descriptor;
        ValidateResource(s,mesh.vertices.Get(),m.positionByteOffset+uint64_t(m.vertexCount-1)*m.positionStride+12,false);
        ValidateResource(s,mesh.indices.Get(),m.indexByteOffset+uint64_t(m.indexCount)*(m.indexBits/8),false);
    }
#ifndef AL_DEPTH_RAYS
    ValidateResource(s,r.output.Get(),r.rays.size()*4,true);
#endif
    Check(s.device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,IID_PPV_ARGS(&r.allocator)),"Create allocator");
    Check(s.device->CreateCommandList(0,D3D12_COMMAND_LIST_TYPE_DIRECT,r.allocator.Get(),nullptr,
        IID_PPV_ARGS(&r.commands)),"Create ray command list");
    if (r.diagnostic) {
    D3D12_QUERY_HEAP_DESC timestamps{D3D12_QUERY_HEAP_TYPE_TIMESTAMP,4,0};
    Check(s.device->CreateQueryHeap(&timestamps,IID_PPV_ARGS(&r.timestamps)),"Create diagnostic timestamps");
    r.timestampReadback=Buffer(s,r,4*sizeof(uint64_t),D3D12_HEAP_TYPE_READBACK,D3D12_RESOURCE_STATE_COPY_DEST);
    r.commands->EndQuery(r.timestamps.Get(),D3D12_QUERY_TYPE_TIMESTAMP,0);
    }
    ComPtr<ID3D12Resource> tlas=r.scene?r.scene->tlas:nullptr;
    if (!tlas) {
    std::vector<D3D12_RAYTRACING_INSTANCE_DESC> instances;
    instances.reserve(r.meshes.size());
    for (const auto& mesh:r.meshes) {
        const auto& m=mesh.descriptor;
        D3D12_RAYTRACING_GEOMETRY_DESC geometry{};
        geometry.Type=D3D12_RAYTRACING_GEOMETRY_TYPE_TRIANGLES;
        geometry.Flags=D3D12_RAYTRACING_GEOMETRY_FLAG_OPAQUE;
        geometry.Triangles.VertexBuffer={mesh.vertices->GetGPUVirtualAddress()+m.positionByteOffset,m.positionStride};
        geometry.Triangles.VertexCount=m.vertexCount; geometry.Triangles.VertexFormat=DXGI_FORMAT_R32G32B32_FLOAT;
        geometry.Triangles.IndexBuffer=mesh.indices->GetGPUVirtualAddress()+m.indexByteOffset;
        geometry.Triangles.IndexCount=m.indexCount;
        geometry.Triangles.IndexFormat=m.indexBits==16?DXGI_FORMAT_R16_UINT:DXGI_FORMAT_R32_UINT;
        D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_INPUTS input{};
        input.Type=D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL;
        input.Flags=D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAG_PREFER_FAST_TRACE;
        input.NumDescs=1; input.DescsLayout=D3D12_ELEMENTS_LAYOUT_ARRAY; input.pGeometryDescs=&geometry;
        auto blas=Build(s,r,input);
        if (r.scene) r.scene->structures.push_back(blas);
        D3D12_RAYTRACING_INSTANCE_DESC instance{};
        memcpy(instance.Transform,m.objectToWorld,sizeof(instance.Transform));
        instance.InstanceID=UINT(instances.size());
        instance.InstanceMask=0xff; instance.AccelerationStructure=blas->GetGPUVirtualAddress();
        instances.push_back(instance);
    }
    auto instanceBuffer=Buffer(s,r,instances.size()*sizeof(instances[0]),D3D12_HEAP_TYPE_UPLOAD,
        D3D12_RESOURCE_STATE_GENERIC_READ,instances.data());
    D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_INPUTS input{};
    input.Type=D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL;
    input.Flags=D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAG_PREFER_FAST_TRACE;
    input.NumDescs=UINT(instances.size()); input.DescsLayout=D3D12_ELEMENTS_LAYOUT_ARRAY;
    input.InstanceDescs=instanceBuffer->GetGPUVirtualAddress();
    tlas=Build(s,r,input);
    if (r.scene) r.scene->tlas=tlas;
    }
    if (r.diagnostic) r.commands->EndQuery(r.timestamps.Get(),D3D12_QUERY_TYPE_TIMESTAMP,1);
#ifdef AL_DEPTH_RAYS
    if (!r.buildOnly) RecordDepthDispatch(s,r,tlas.Get());
    else if (r.diagnostic) {
        r.commands->EndQuery(r.timestamps.Get(),D3D12_QUERY_TYPE_TIMESTAMP,2);
        r.commands->EndQuery(r.timestamps.Get(),D3D12_QUERY_TYPE_TIMESTAMP,3);
    }
#else
    auto rays=Buffer(s,r,r.rays.size()*sizeof(ProbeRay),D3D12_HEAP_TYPE_UPLOAD,D3D12_RESOURCE_STATE_GENERIC_READ,r.rays.data());
    r.commands->SetPipelineState(s.pipeline.Get()); r.commands->SetComputeRootSignature(s.root.Get());
    r.commands->SetComputeRootShaderResourceView(0,tlas->GetGPUVirtualAddress());
    r.commands->SetComputeRootShaderResourceView(1,rays->GetGPUVirtualAddress());
    r.commands->SetComputeRootUnorderedAccessView(2,r.output->GetGPUVirtualAddress());
    r.commands->SetComputeRoot32BitConstant(3,UINT(r.rays.size()),0);
    r.commands->Dispatch((UINT(r.rays.size())+63)/64,1,1); UavBarrier(r,r.output.Get());
    r.commands->EndQuery(r.timestamps.Get(),D3D12_QUERY_TYPE_TIMESTAMP,2);
    r.commands->EndQuery(r.timestamps.Get(),D3D12_QUERY_TYPE_TIMESTAMP,3);
#endif
    if (r.diagnostic) r.commands->ResolveQueryData(r.timestamps.Get(),D3D12_QUERY_TYPE_TIMESTAMP,0,4,r.timestampReadback.Get(),0);
    Check(r.commands->Close(),"Close ray commands");
    std::vector<UnityGraphicsD3D12ResourceState> states;
    if (r.output) states.push_back({r.output.Get(),D3D12_RESOURCE_STATE_UNORDERED_ACCESS,D3D12_RESOURCE_STATE_UNORDERED_ACCESS});
    auto inputState=[&](ID3D12Resource* resource) {
        if (std::none_of(states.begin(),states.end(),[&](const auto& entry){return entry.resource==resource;}))
            states.push_back({resource,D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE,
                D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE});
    };
    for (const auto& mesh:r.meshes) { inputState(mesh.vertices.Get()); inputState(mesh.indices.Get()); }
#ifdef AL_DEPTH_RAYS
    if (r.depth) inputState(r.depth.Get());
#endif
    r.fence=s.v7?s.v7->ExecuteCommandList(r.commands.Get(),int(states.size()),states.data())
        :s.v6->ExecuteCommandList(r.commands.Get(),int(states.size()),states.data());
    if (!r.fence) r.fence=UINT64_MAX;
    if (r.buildOnly) r.scene->fence=r.fence;
}

static void UNITY_INTERFACE_API OnRender(int id)
{
    State* s=state; if (!s) return;
    std::lock_guard<std::mutex> lock(s->mutex);
    if (id!=s->eventId) return;
    try {
        Initialize(*s);
        uint64_t completed=s->fence->GetCompletedValue();
        if (completed==UINT64_MAX) throw std::runtime_error("Unity device/fence removed");
        while (!s->inflight.empty() && s->inflight.front().fence<=completed) {
            s->retired=s->inflight.front().ticket; s->inflight.pop_front();
        }
        if (!s->pending.empty()) {
            s->inflight.push_back(std::move(s->pending.front())); s->pending.pop_front();
            auto& request=s->inflight.back();
            try { Submit(*s,request); }
            catch (...) { s->failed=request.ticket; if (request.buildOnly) request.scene->failed=true; s->inflight.pop_back(); throw; }
            s->submitted=request.ticket;
        }
        s->message="ray event processed; validate output after its frame fence";
    } catch (const std::exception& e) { s->message=e.what(); }
}
API void UNITY_INTERFACE_API UnityPluginLoad(IUnityInterfaces* registry)
{
    if (!state) state=new State;
    std::lock_guard<std::mutex> lock(state->mutex);
    if (state->graphics || !registry) return;
    state->graphics=registry->Get<IUnityGraphics>(); state->v7=registry->Get<IUnityGraphicsD3D12v7>();
    if (!state->v7) state->v6=registry->Get<IUnityGraphicsD3D12v6>();
    if (!state->graphics || (!state->v7&&!state->v6)) {
        state->graphics=nullptr; state->message="Unity D3D12 v7/v6 unavailable"; return;
    }
    state->eventId=state->graphics->ReserveEventIDRange(1); state->message="registered; awaiting ray event";
}
API void UNITY_INTERFACE_API UnityPluginUnload()
{
    State* old=state; state=nullptr;
    if (old&&old->pending.empty()&&old->inflight.empty()&&old->scenes.empty()) delete old;
}
API int ALRAY_SetShader(const void* bytes,uint32_t length)
{
    if (!state||!bytes||length<32||length>16*1024*1024) return 0;
    std::lock_guard<std::mutex> lock(state->mutex);
    if (state->device||!state->pending.empty()||!state->inflight.empty()||memcmp(bytes,"DXBC",4)) return 0;
    const auto* data=static_cast<const unsigned char*>(bytes);
    state->shader.assign(data,data+length); return 1;
}
static void CaptureMeshes(Request& r,const MeshRequest* meshes,uint32_t meshCount)
{
        for (uint32_t i=0;i<meshCount;i++) {
            const auto& m=meshes[i];
            if ((r.buildOnly ? m.output!=nullptr : (!m.output || m.output!=r.output.Get())) || !m.vertices||!m.indices||m.output==m.vertices||m.output==m.indices
                || m.reserved||m.positionStride<12||m.positionStride>2048||m.positionStride%4
                || !m.vertexCount||!m.indexCount||m.indexCount%3||(m.indexBits!=16&&m.indexBits!=32)
                || m.positionByteOffset%4||m.indexByteOffset%(m.indexBits/8)
                || m.positionByteOffset>UINT64_MAX-uint64_t(m.vertexCount-1)*m.positionStride-12
                || m.indexByteOffset>UINT64_MAX-uint64_t(m.indexCount)*(m.indexBits/8))
                throw std::runtime_error("Rejected mesh descriptor/count/alignment/alias");
            for (float x:m.objectToWorld) if (!std::isfinite(x)) throw std::runtime_error("Nonfinite transform");
            const float* a=m.objectToWorld;
            double determinant=double(a[0])*(double(a[5])*a[10]-double(a[6])*a[9])
                -double(a[1])*(double(a[4])*a[10]-double(a[6])*a[8])
                +double(a[2])*(double(a[4])*a[9]-double(a[5])*a[8]);
            if (!std::isfinite(determinant)||determinant==0) throw std::runtime_error("Singular transform");
#ifdef AL_DEPTH_RAYS
            if (r.depth && (r.depth.Get()==m.vertices || r.depth.Get()==m.indices)) throw std::runtime_error("Depth aliases mesh input");
#endif
            MeshInput input; input.descriptor=m; input.vertices=m.vertices; input.indices=m.indices;
            r.meshes.push_back(std::move(input));
        }
}

#ifdef AL_DEPTH_RAYS
API uint64_t ALRAY_QueueDepthScene(const MeshRequest* meshes,uint32_t meshCount,ID3D12Resource* depth,const DepthFrame* frame)
{
    if (!frame || !depth || !meshes || meshCount==0 || meshCount>4096 || depth==meshes[0].output || frame->width==0 || frame->height==0
        || frame->width>16384 || frame->height>16384 || frame->lightCount>32) return 0;
#else
API uint64_t ALRAY_QueueScene(const MeshRequest* meshes,uint32_t meshCount,const ProbeRay* rays,uint32_t rayCount)
{
    if (!meshes||meshCount==0||meshCount>4096||!rays||rayCount<2||rayCount>4096) return 0;
#endif
    if (!state) return 0;
    std::lock_guard<std::mutex> lock(state->mutex);
    try {
        if (!state->graphics||!state->device||state->shader.empty()||state->pending.size()+state->inflight.size()>=4)
            throw std::runtime_error("Probe not initialized or request queue full");
        Request r; r.output=meshes[0].output; r.meshes.reserve(meshCount);
#ifdef AL_DEPTH_RAYS
        r.depth=depth;
#endif
        CaptureMeshes(r,meshes,meshCount);
#ifdef AL_DEPTH_RAYS
        r.depth=depth; r.frame=*frame;
#else
        r.rays.assign(rays,rays+rayCount);
#endif
        r.ticket=state->next++;
        uint64_t ticket=r.ticket; state->pending.push_back(std::move(r)); return ticket;
    } catch (const std::exception& e) { state->message=e.what(); return 0; }
}
// Preserve the original probe ABI through the same scene submission path.
#ifdef AL_DEPTH_RAYS
// Build an immutable snapshot. Descriptors must have null outputs. Callers
// keep source buffers unchanged until SceneReady returns 1, then may release
// them. A new pose, transform or topology requires a new snapshot.
API uint64_t ALRAY_CreateScene(const MeshRequest* meshes,uint32_t meshCount)
{
    if (!state || !meshes || !meshCount || meshCount>4096) return 0;
    std::lock_guard<std::mutex> lock(state->mutex);
    try {
        if (!state->device || state->pending.size()+state->inflight.size()>=4 || state->scenes.size()>=4)
            throw std::runtime_error("Scene creation requires a warmed probe and available capacity");
        Request r; r.buildOnly=true; r.scene=std::make_shared<RetainedScene>();
        CaptureMeshes(r,meshes,meshCount);
        r.ticket=state->next++;
        const auto handle=r.ticket;
        state->scenes.emplace(handle,r.scene);
        try { state->pending.push_back(std::move(r)); }
        catch (...) { state->scenes.erase(handle); throw; }
        return handle;
    } catch (const std::exception& e) { state->message=e.what(); return 0; }
}

// 0 pending, 1 GPU build completed, -1 invalid/failed/device removed.
API int ALRAY_SceneReady(uint64_t handle)
{
    if (!state || !handle) return -1;
    std::lock_guard<std::mutex> lock(state->mutex);
    const auto found=state->scenes.find(handle);
    if (found==state->scenes.end() || found->second->failed) return -1;
    const auto& scene=*found->second;
    if (!scene.fence) return 0;
    const auto completed=state->fence->GetCompletedValue();
    if (completed==UINT64_MAX) return -1;
    return completed>=scene.fence?1:0;
}

// Releases the public handle immediately. Submitted requests independently
// retain its acceleration structures until their GPU fence has completed.
API int ALRAY_ReleaseScene(uint64_t handle)
{
    if (!state || !handle) return 0;
    std::lock_guard<std::mutex> lock(state->mutex);
    return state->scenes.erase(handle)?1:0;
}

API uint64_t ALRAY_QueueRetainedDepth(uint64_t handle,ID3D12Resource* output,
    ID3D12Resource* depth,const DepthFrame* frame,uint32_t diagnostic)
{
    if (!state || !handle || !output || !depth || output==depth || !frame || diagnostic>1
        || !frame->width || !frame->height || frame->width>16384 || frame->height>16384
        || frame->lightCount>32) return 0;
    for (float x:frame->clipToWorld) if (!std::isfinite(x)) return 0;
    for (uint32_t i=0;i<frame->lightCount;i++)
        for (float x:frame->directions[i]) if (!std::isfinite(x)) return 0;
    std::lock_guard<std::mutex> lock(state->mutex);
    const auto found=state->scenes.find(handle);
    if (found==state->scenes.end() || found->second->failed || !found->second->fence
        || state->pending.size()+state->inflight.size()>=4) return 0;
    const auto completed=state->fence->GetCompletedValue();
    if (completed==UINT64_MAX || completed<found->second->fence) return 0;
    try {
        Request r; r.scene=found->second; r.output=output; r.depth=depth;
        r.frame=*frame; r.diagnostic=diagnostic!=0; r.ticket=state->next++;
        const auto ticket=r.ticket; state->pending.push_back(std::move(r)); return ticket;
    } catch (const std::exception& e) { state->message=e.what(); return 0; }
}

API uint64_t ALRAY_QueueDepth(const MeshRequest* mesh,ID3D12Resource* depth,const DepthFrame* frame)
{
    return ALRAY_QueueDepthScene(mesh,1,depth,frame);
}
#else
API uint64_t ALRAY_QueueMesh(const MeshRequest* mesh,const ProbeRay* rays,uint32_t rayCount)
{
    return ALRAY_QueueScene(mesh,1,rays,rayCount);
}
#endif
API UnityRenderingEvent ALRAY_GetRenderEventFunc() { return OnRender; }
API int ALRAY_GetEventId() { return state?state->eventId:-1; }
API int ALRAY_CanUnload()
{
    if (!state) return 1;
    std::lock_guard<std::mutex> lock(state->mutex); return state->pending.empty()&&state->inflight.empty()&&state->scenes.empty();
}
API int ALRAY_RequestsIdle()
{
    if (!state) return 1;
    std::lock_guard<std::mutex> lock(state->mutex);
    return state->pending.empty()&&state->inflight.empty();
}
API uint32_t ALRAY_CancelPending()
{
    if (!state) return 0;
    std::lock_guard<std::mutex> lock(state->mutex);
    uint32_t count=uint32_t(state->pending.size());
    for (auto& r:state->pending) if (r.buildOnly) r.scene->failed=true;
    state->pending.clear(); return count;
}
API uint32_t ALRAY_GetStatus(char* output,uint32_t capacity)
{
    if (!output||!capacity) return 0;
    if (!state) {output[0]=0;return 0;}
    std::lock_guard<std::mutex> lock(state->mutex);
    char text[1024]; int length=sprintf_s(text,
        "event=%d interface=%d initialized=%d pending=%zu inflight=%zu submitted=%llu retired=%llu failed=%llu scenes=%zu message=%s",
        state->eventId,state->v7?7:state->v6?6:0,state->device?1:0,state->pending.size(),state->inflight.size(),
        state->submitted,state->retired,state->failed,state->scenes.size(),state->message.c_str());
    uint32_t copied=(std::min)(uint32_t(length),capacity-1); memcpy(output,text,copied); output[copied]=0;return copied;
}

// Poll before retiring the request: 0 pending, 1 measured, -1 invalid/unavailable.
// GPU command-stream intervals in milliseconds, including each stage's barriers:
// all BLAS + TLAS builds; shader dispatch; output readback copy (depth only).
// Excludes CPU collection/baking/allocation, Unity producer flushes, queue waits,
// publication and this timestamp readback. This is one-shot diagnostic cost,
// not steady-frame renderer cost; the mesh probe has no output copy stage.
API int ALRAY_ReadTimings(uint64_t ticket,double* buildMs,double* traceMs,double* copyMs)
{
    if (!state || !ticket || !buildMs || !traceMs || !copyMs) return -1;
    std::lock_guard<std::mutex> lock(state->mutex);
    for (const auto& r:state->pending) if (r.ticket==ticket) return 0;
    for (auto& r:state->inflight) {
        if (r.ticket!=ticket) continue;
        const auto completed=state->fence->GetCompletedValue();
        if (completed==UINT64_MAX) return -1;
        if (completed<r.fence) return 0;
        void* pointer=nullptr; D3D12_RANGE range{0,4*sizeof(uint64_t)};
        if (!r.timestampReadback || FAILED(r.timestampReadback->Map(0,&range,&pointer))) return -1;
        uint64_t values[4]; memcpy(values,pointer,sizeof(values));
        D3D12_RANGE noWrites{0,0}; r.timestampReadback->Unmap(0,&noWrites);
        if (values[0]>values[1] || values[1]>values[2] || values[2]>values[3]) return -1;
        const double scale=1000.0/double(state->timestampFrequency);
        *buildMs=double(values[1]-values[0])*scale;
        *traceMs=double(values[2]-values[1])*scale;
#ifdef AL_DEPTH_RAYS
        *copyMs=double(values[3]-values[2])*scale;
#else
        *copyMs=0;
#endif
        return 1;
    }
    return -1;
}

#ifdef AL_DEPTH_RAYS
// Poll before retiring the request. 0 means pending, 1 returns counts, and
// -1 rejects an unknown/retired/failed ticket or a readback error. Never waits.
API int ALRAY_ReadDepthSummary(uint64_t ticket,uint32_t* valid,uint32_t* blocked)
{
    if (!state || !ticket || !valid || !blocked) return -1;
    std::lock_guard<std::mutex> lock(state->mutex);
    for (const auto& r:state->pending) if (r.ticket==ticket) return 0;
    for (auto& r:state->inflight) {
        if (r.ticket!=ticket) continue;
        const auto completed=state->fence->GetCompletedValue();
        if (completed==UINT64_MAX) return -1;
        if (completed<r.fence) return 0;
        void* pointer=nullptr;
        D3D12_RANGE range{0,size_t(r.readbackBytes)};
        if (!r.readback || FAILED(r.readback->Map(0,&range,&pointer))) return -1;
        uint32_t validCount=0,blockedCount=0,maskUnion=0;
        float minimumDepth=1,maximumDepth=0;
        for (uint32_t y=0;y<r.frame.height;y++) {
            auto* row=reinterpret_cast<const uint32_t*>(static_cast<const uint8_t*>(pointer)
                +r.footprint.Offset+uint64_t(y)*r.footprint.Footprint.RowPitch);
            for (uint32_t x=0;x<r.frame.width;x++) {
                float depth; memcpy(&depth,&row[2*x+1],sizeof(depth));
                if (!std::isfinite(depth) || depth<=0 || depth>1) continue;
                ++validCount; if (row[2*x]) ++blockedCount;
                maskUnion|=row[2*x];
                minimumDepth=(std::min)(minimumDepth,depth);
                maximumDepth=(std::max)(maximumDepth,depth);
            }
        }
        D3D12_RANGE noWrites{0,0}; r.readback->Unmap(0,&noWrites);
        char description[192];
        sprintf_s(description,"depth summary min=%.9g max=%.9g mask_union=0x%x",minimumDepth,maximumDepth,maskUnion);
        state->message=description;
        *valid=validCount; *blocked=blockedCount; return 1;
    }
    return -1;
}
#endif
