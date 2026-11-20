// Synthetic GPU proof for MapLightVisibility.hlsl. No Unity/game interaction.
#define NOMINMAX
#include <windows.h>
#include <d3d12.h>
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <array>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <vector>

using Microsoft::WRL::ComPtr;
static void Check(HRESULT result, const char* operation)
{
    if (FAILED(result)) {
        char text[256];
        sprintf_s(text, "%s: HRESULT 0x%08lx", operation, result);
        throw std::runtime_error(text);
    }
}

struct Light {
    float direction[3]; UINT type;
    float position[3]; UINT valid;
    UINT culling, lightingLayers, shadowLayers, enabled;
};
struct Frame {
    UINT width, height, selected, lightCount;
    float boundsMin[3], normalBias;
    float boundsMax[3], rayBias;
    UINT valid, casterCount, reserved[2];
};
static_assert(sizeof(Light) == 48 && sizeof(Frame) == 64);

struct Receiver { float position[4], normal[4]; UINT flags[4]; };
struct CasterRange { UINT first, count, gameObjectLayer, renderingLayers; };
static_assert(sizeof(Receiver) == 48 && sizeof(CasterRange) == 16);
struct Snapshot {
    std::vector<std::array<float, 3>> vertices;
    std::vector<UINT> indices;
    std::vector<CasterRange> ranges;
    std::vector<Receiver> receivers;
    std::vector<Light> lights;
    std::array<float, 3> minimum{}, maximum{};
};

static Snapshot LoadSnapshot(const std::filesystem::path& path)
{
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file) throw std::runtime_error("Cannot open snapshot");
    auto size = file.tellg();
    if (size < 28 || size > 1024LL * 1024 * 1024)
        throw std::runtime_error("Snapshot size outside supported 28-byte to 1-GiB bound");
    file.seekg(0);
    char magic[8]; UINT count[5];
    file.read(magic, sizeof(magic)); file.read(reinterpret_cast<char*>(count), sizeof(count));
    if (memcmp(magic, "ALVIS001", 8)) throw std::runtime_error("Invalid snapshot magic");
    const UINT64 expected = 28 + UINT64(count[0])*12 + UINT64(count[1])*4
        + UINT64(count[2])*16 + UINT64(count[3])*48 + UINT64(count[4])*48;
    if (expected != UINT64(size) || !count[0] || !count[1] || count[1]%3
        || !count[2] || count[2] > 0x1000000 || !count[3] || count[3] > 16384u*16384u || !count[4])
        throw std::runtime_error("Invalid snapshot counts/length");
    Snapshot s;
    auto read = [&file](auto& values, UINT length) {
        values.resize(length);
        file.read(reinterpret_cast<char*>(values.data()), std::streamsize(values.size()*sizeof(values[0])));
        if (!file) throw std::runtime_error("Truncated snapshot");
    };
    read(s.vertices,count[0]); read(s.indices,count[1]); read(s.ranges,count[2]);
    read(s.receivers,count[3]); read(s.lights,count[4]);
    s.minimum = s.maximum = s.vertices[0];
    for (const auto& v : s.vertices) for (UINT axis = 0; axis < 3; ++axis) {
        if (!std::isfinite(v[axis])) throw std::runtime_error("Nonfinite caster vertex");
        s.minimum[axis] = (std::min)(s.minimum[axis],v[axis]);
        s.maximum[axis] = (std::max)(s.maximum[axis],v[axis]);
    }
    for (UINT index : s.indices) if (index >= s.vertices.size())
        throw std::runtime_error("Caster vertex index out of range");
    UINT64 end = 0;
    for (const auto& r : s.ranges) {
        if (r.first != end || !r.count || r.count%3 || !r.gameObjectLayer
            || (r.gameObjectLayer & (r.gameObjectLayer-1)))
            throw std::runtime_error("Ranges must cover indices contiguously with one-hot GameObject layers");
        end += r.count;
        if (end > s.indices.size()) throw std::runtime_error("Caster range overrun");
    }
    if (end != s.indices.size()) throw std::runtime_error("Caster ranges do not cover all indices");
    for (const auto& r : s.receivers) {
        if (r.flags[3] > 1 || r.flags[2] > 1 || !r.flags[0] || (r.flags[0] & (r.flags[0]-1)))
            throw std::runtime_error("Invalid receiver flags/layer");
        // Invalid receiver payloads deliberately reach the kernel's validity checks.
        if (r.flags[3] == 1 && r.position[3] == 1) {
            for (UINT axis = 0; axis < 3; ++axis)
                if (!std::isfinite(r.position[axis]) || !std::isfinite(r.normal[axis]))
                    throw std::runtime_error("Nonfinite valid receiver");
        }
    }
    for (const auto& light : s.lights) {
        if (light.type > 1 || light.valid > 1 || light.enabled > 1)
            throw std::runtime_error("Invalid light flags/type");
        if (light.valid) for (UINT axis = 0; axis < 3; ++axis)
            if (!std::isfinite(light.direction[axis]) || !std::isfinite(light.position[axis]))
                throw std::runtime_error("Nonfinite valid light");
    }
    for (UINT axis = 0; axis < 3; ++axis) {
        float pad = (std::max)(0.001f, (s.maximum[axis]-s.minimum[axis])*1e-5f);
        s.minimum[axis] -= pad; s.maximum[axis] += pad;
        if (!std::isfinite(s.minimum[axis]) || !std::isfinite(s.maximum[axis]))
            throw std::runtime_error("Caster bounds overflow");
    }
    printf("Validated opaque snapshot: %u vertices, %u triangles, %u ranges, %u receivers, %u lights.\n",
        count[0],count[1]/3,count[2],count[3],count[4]);
    return s;
}

class Smoke {
    ComPtr<ID3D12Device5> device;
    ComPtr<ID3D12CommandQueue> queue;
    ComPtr<ID3D12CommandAllocator> allocator;
    ComPtr<ID3D12GraphicsCommandList4> list;
    ComPtr<ID3D12DescriptorHeap> descriptors;
    std::vector<ComPtr<ID3D12Resource>> resources;
    UINT descriptorSize = 0;
    UINT width = 4, height = 1;

    ComPtr<ID3D12Resource> Buffer(UINT64 bytes, D3D12_HEAP_TYPE heap,
        D3D12_RESOURCE_STATES state, D3D12_RESOURCE_FLAGS flags = D3D12_RESOURCE_FLAG_NONE)
    {
        D3D12_HEAP_PROPERTIES properties{}; properties.Type = heap;
        D3D12_RESOURCE_DESC desc{};
        desc.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
        desc.Width = bytes; desc.Height = 1; desc.DepthOrArraySize = 1;
        desc.MipLevels = 1; desc.SampleDesc.Count = 1;
        desc.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR; desc.Flags = flags;
        ComPtr<ID3D12Resource> result;
        Check(device->CreateCommittedResource(&properties, D3D12_HEAP_FLAG_NONE,
            &desc, state, nullptr, IID_PPV_ARGS(&result)), "Create buffer");
        resources.push_back(result);
        return result;
    }
    ComPtr<ID3D12Resource> Upload(const void* bytes, size_t size)
    {
        auto resource = Buffer(size, D3D12_HEAP_TYPE_UPLOAD, D3D12_RESOURCE_STATE_GENERIC_READ);
        void* mapped = nullptr; D3D12_RANGE empty{0, 0};
        Check(resource->Map(0, &empty, &mapped), "Map upload");
        memcpy(mapped, bytes, size); resource->Unmap(0, nullptr);
        return resource;
    }
    void Transition(ID3D12Resource* resource, D3D12_RESOURCE_STATES before,
        D3D12_RESOURCE_STATES after)
    {
        D3D12_RESOURCE_BARRIER barrier{};
        barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
        barrier.Transition = {resource, D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES, before, after};
        list->ResourceBarrier(1, &barrier);
    }
    void UavBarrier(ID3D12Resource* resource)
    {
        D3D12_RESOURCE_BARRIER barrier{};
        barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_UAV; barrier.UAV.pResource = resource;
        list->ResourceBarrier(1, &barrier);
    }
    D3D12_CPU_DESCRIPTOR_HANDLE Cpu(UINT index)
    {
        auto handle = descriptors->GetCPUDescriptorHandleForHeapStart();
        handle.ptr += SIZE_T(index) * descriptorSize; return handle;
    }
    ComPtr<ID3D12Resource> Texture(DXGI_FORMAT format, const void* data, UINT stride, UINT slot)
    {
        D3D12_HEAP_PROPERTIES heap{}; heap.Type = D3D12_HEAP_TYPE_DEFAULT;
        D3D12_RESOURCE_DESC desc{};
        desc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
        desc.Width = width; desc.Height = height; desc.DepthOrArraySize = 1;
        desc.MipLevels = 1; desc.Format = format; desc.SampleDesc.Count = 1;
        desc.Flags = data ? D3D12_RESOURCE_FLAG_NONE : D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS;
        ComPtr<ID3D12Resource> texture;
        Check(device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE, &desc,
            data ? D3D12_RESOURCE_STATE_COPY_DEST : D3D12_RESOURCE_STATE_UNORDERED_ACCESS,
            nullptr, IID_PPV_ARGS(&texture)), "Create texture");
        resources.push_back(texture);
        if (data) {
            D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint{}; UINT64 bytes = 0;
            device->GetCopyableFootprints(&desc, 0, 1, 0, &footprint, nullptr, nullptr, &bytes);
            std::vector<unsigned char> padded(static_cast<size_t>(bytes));
            for (UINT row = 0; row < height; ++row)
                memcpy(padded.data() + size_t(row)*footprint.Footprint.RowPitch,
                    static_cast<const unsigned char*>(data) + size_t(row)*width*stride, size_t(width)*stride);
            auto upload = Upload(padded.data(), padded.size());
            D3D12_TEXTURE_COPY_LOCATION source{}, target{};
            source.pResource = upload.Get(); source.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
            source.PlacedFootprint = footprint;
            target.pResource = texture.Get(); target.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
            list->CopyTextureRegion(&target, 0, 0, 0, &source, nullptr);
            Transition(texture.Get(), D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
            D3D12_SHADER_RESOURCE_VIEW_DESC srv{};
            srv.Format = format; srv.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE2D;
            srv.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
            srv.Texture2D.MipLevels = 1;
            device->CreateShaderResourceView(texture.Get(), &srv, Cpu(slot));
        } else {
            D3D12_UNORDERED_ACCESS_VIEW_DESC uav{};
            uav.Format = format; uav.ViewDimension = D3D12_UAV_DIMENSION_TEXTURE2D;
            device->CreateUnorderedAccessView(texture.Get(), nullptr, &uav, Cpu(slot));
        }
        return texture;
    }
    void Structured(ID3D12Resource* resource, UINT count, UINT stride, UINT slot)
    {
        D3D12_SHADER_RESOURCE_VIEW_DESC srv{};
        srv.ViewDimension = D3D12_SRV_DIMENSION_BUFFER;
        srv.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
        srv.Buffer.NumElements = count; srv.Buffer.StructureByteStride = stride;
        device->CreateShaderResourceView(resource, &srv, Cpu(slot));
    }
    ComPtr<ID3D12Resource> Build(const D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_INPUTS& inputs)
    {
        D3D12_RAYTRACING_ACCELERATION_STRUCTURE_PREBUILD_INFO size{};
        device->GetRaytracingAccelerationStructurePrebuildInfo(&inputs, &size);
        if (!size.ResultDataMaxSizeInBytes || !size.ScratchDataSizeInBytes)
            throw std::runtime_error("Invalid AS prebuild size");
        auto scratch = Buffer(size.ScratchDataSizeInBytes, D3D12_HEAP_TYPE_DEFAULT,
            D3D12_RESOURCE_STATE_UNORDERED_ACCESS, D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS);
        auto result = Buffer(size.ResultDataMaxSizeInBytes, D3D12_HEAP_TYPE_DEFAULT,
            D3D12_RESOURCE_STATE_RAYTRACING_ACCELERATION_STRUCTURE,
            D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS);
        D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_DESC desc{};
        desc.Inputs = inputs; desc.ScratchAccelerationStructureData = scratch->GetGPUVirtualAddress();
        desc.DestAccelerationStructureData = result->GetGPUVirtualAddress();
        list->BuildRaytracingAccelerationStructure(&desc, 0, nullptr);
        UavBarrier(result.Get()); return result;
    }
public:
    int Run(const std::filesystem::path& shader, const Snapshot* scene = nullptr,
        UINT selected = 0, const std::filesystem::path& outputPath = {})
    {
        if (scene) {
            if (selected >= scene->lights.size()) throw std::runtime_error("Selected light out of range");
            width = (std::min)(UINT(scene->receivers.size()),16384u);
            height = (UINT(scene->receivers.size())+width-1)/width;
        }
        std::ifstream stream(shader, std::ios::binary);
        if (!stream) throw std::runtime_error("Cannot open DXIL file");
        std::vector<char> code((std::istreambuf_iterator<char>(stream)), {});
        ComPtr<ID3D12Debug> debug;
        if (SUCCEEDED(D3D12GetDebugInterface(IID_PPV_ARGS(&debug)))) debug->EnableDebugLayer();
        ComPtr<IDXGIFactory6> factory;
        Check(CreateDXGIFactory2(0, IID_PPV_ARGS(&factory)), "Create DXGI factory");
        for (UINT index = 0; ; ++index) {
            ComPtr<IDXGIAdapter1> adapter;
            if (factory->EnumAdapterByGpuPreference(index, DXGI_GPU_PREFERENCE_HIGH_PERFORMANCE,
                IID_PPV_ARGS(&adapter)) == DXGI_ERROR_NOT_FOUND) break;
            ComPtr<ID3D12Device5> candidate;
            if (FAILED(D3D12CreateDevice(adapter.Get(), D3D_FEATURE_LEVEL_12_0,
                IID_PPV_ARGS(&candidate)))) continue;
            D3D12_FEATURE_DATA_D3D12_OPTIONS5 options{};
            if (FAILED(candidate->CheckFeatureSupport(D3D12_FEATURE_D3D12_OPTIONS5,
                &options, sizeof(options))) || options.RaytracingTier < D3D12_RAYTRACING_TIER_1_1) continue;
            D3D12_FEATURE_DATA_SHADER_MODEL model{D3D_SHADER_MODEL_6_5};
            if (FAILED(candidate->CheckFeatureSupport(D3D12_FEATURE_SHADER_MODEL,
                &model, sizeof(model))) || model.HighestShaderModel < D3D_SHADER_MODEL_6_5) continue;
            DXGI_ADAPTER_DESC1 desc{}; adapter->GetDesc1(&desc);
            wprintf(L"Adapter: %s\n", desc.Description);
            device = candidate; break;
        }
        if (!device) throw std::runtime_error("No DXR 1.1 / SM6.5 adapter");
        D3D12_COMMAND_QUEUE_DESC q{};
        Check(device->CreateCommandQueue(&q, IID_PPV_ARGS(&queue)), "Create queue");
        Check(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,
            IID_PPV_ARGS(&allocator)), "Create allocator");
        Check(device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, allocator.Get(),
            nullptr, IID_PPV_ARGS(&list)), "Create list");
        D3D12_DESCRIPTOR_HEAP_DESC hd{};
        hd.NumDescriptors = 7; hd.Type = D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV;
        hd.Flags = D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE;
        Check(device->CreateDescriptorHeap(&hd, IID_PPV_ARGS(&descriptors)), "Create descriptor heap");
        descriptorSize = device->GetDescriptorHandleIncrementSize(hd.Type);

        // Complete synthetic scene: one two-triangle square at z=2, no other geometry.
        const float vertices[][3] = {{-2,-2,2}, {2,-2,2}, {2,2,2}, {-2,-2,2}, {2,2,2}, {-2,2,2}};
        auto vb = scene ? Upload(scene->vertices.data(),scene->vertices.size()*sizeof(scene->vertices[0]))
            : Upload(vertices, sizeof(vertices));
        ComPtr<ID3D12Resource> ib;
        if (scene) ib = Upload(scene->indices.data(),scene->indices.size()*sizeof(UINT));
        D3D12_RAYTRACING_GEOMETRY_DESC geometry{};
        geometry.Type = D3D12_RAYTRACING_GEOMETRY_TYPE_TRIANGLES;
        geometry.Flags = D3D12_RAYTRACING_GEOMETRY_FLAG_OPAQUE;
        geometry.Triangles.VertexBuffer = {vb->GetGPUVirtualAddress(), sizeof(vertices[0])};
        geometry.Triangles.VertexCount = 6; geometry.Triangles.VertexFormat = DXGI_FORMAT_R32G32B32_FLOAT;
        D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_INPUTS input{};
        input.Type = D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL;
        input.DescsLayout = D3D12_ELEMENTS_LAYOUT_ARRAY; input.NumDescs = 1;
        input.pGeometryDescs = &geometry;
        input.Flags = D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAG_PREFER_FAST_TRACE;
        const UINT rangeCount = scene ? UINT(scene->ranges.size()) : 1;
        std::vector<D3D12_RAYTRACING_INSTANCE_DESC> instanceData(rangeCount);
        std::vector<std::array<UINT,4>> casterData(rangeCount);
        for (UINT index = 0; index < rangeCount; ++index) {
            if (scene) {
                const auto& r = scene->ranges[index];
                geometry.Triangles.VertexCount = UINT(scene->vertices.size());
                geometry.Triangles.IndexFormat = DXGI_FORMAT_R32_UINT;
                geometry.Triangles.IndexCount = r.count;
                geometry.Triangles.IndexBuffer = ib->GetGPUVirtualAddress() + UINT64(r.first)*sizeof(UINT);
                casterData[index] = {r.gameObjectLayer,r.renderingLayers,0,0};
            } else casterData[index] = {1,2,0,0};
            auto blas = Build(input);
            auto& instance = instanceData[index];
            instance.Transform[0][0] = instance.Transform[1][1] = instance.Transform[2][2] = 1;
            instance.InstanceID = index;
            instance.InstanceMask = 0xff; instance.AccelerationStructure = blas->GetGPUVirtualAddress();
        }
        auto instances = Upload(instanceData.data(),instanceData.size()*sizeof(instanceData[0]));
        input.Type = D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL;
        input.NumDescs = rangeCount;
        input.InstanceDescs = instances->GetGPUVirtualAddress();
        auto tlas = Build(input);
        D3D12_SHADER_RESOURCE_VIEW_DESC asView{};
        asView.ViewDimension = D3D12_SRV_DIMENSION_RAYTRACING_ACCELERATION_STRUCTURE;
        asView.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
        asView.RaytracingAccelerationStructure.Location = tlas->GetGPUVirtualAddress();
        device->CreateShaderResourceView(nullptr, &asView, Cpu(0));

        const float positions[][4] = {{0,0,0,1}, {0,0,0,0}, {0,0,0,1}, {10,0,0,1}};
        const float normals[][4] = {{0,0,1,0}, {0,0,1,0}, {0,0,1,0}, {0,0,1,0}};
        const UINT receivers[][4] = {{1,2,1,1}, {1,2,1,1}, {4,2,1,1}, {1,2,1,1}};
        std::vector<std::array<float,4>> scenePositions, sceneNormals;
        std::vector<std::array<UINT,4>> sceneFlags;
        if (scene) {
            size_t pixels = size_t(width)*height;
            scenePositions.resize(pixels); sceneNormals.resize(pixels); sceneFlags.resize(pixels);
            for (size_t i = 0; i < scene->receivers.size(); ++i) {
                memcpy(scenePositions[i].data(),scene->receivers[i].position,16);
                memcpy(sceneNormals[i].data(),scene->receivers[i].normal,16);
                memcpy(sceneFlags[i].data(),scene->receivers[i].flags,16);
            }
        }
        Texture(DXGI_FORMAT_R32G32B32A32_FLOAT, scene ? scenePositions.data() : static_cast<const void*>(positions), 16, 1);
        Texture(DXGI_FORMAT_R32G32B32A32_FLOAT, scene ? sceneNormals.data() : static_cast<const void*>(normals), 16, 2);
        Texture(DXGI_FORMAT_R32G32B32A32_UINT, scene ? sceneFlags.data() : static_cast<const void*>(receivers), 16, 3);
        auto flags = Upload(casterData.data(),casterData.size()*16); Structured(flags.Get(), rangeCount, 16, 4);
        std::vector<Light> lights(6);
        for (auto& light : lights) light = {{0,0,1},0,{0,0,4},1,1,2,2,1};
        lights[1].type = 1;                    // z=4: square lies before light.
        lights[2].type = 1; lights[2].position[2] = 1; // z=1: square behind light.
        lights[3].shadowLayers = 4;            // Caster filtered, receiver still affected.
        lights[4].lightingLayers = 4;          // Receiver filtered.
        lights[5].direction[2] = 0;            // Invalid zero directional vector.
        if (scene) lights = scene->lights;
        auto lightBuffer = Upload(lights.data(), lights.size()*sizeof(Light));
        Structured(lightBuffer.Get(), UINT(lights.size()), sizeof(Light), 5);
        auto output = Texture(DXGI_FORMAT_R32G32_FLOAT, nullptr, 8, 6);
        UINT dispatchCount = scene ? 1 : UINT(lights.size());
        std::vector<unsigned char> constants(size_t(256)*dispatchCount);
        for (UINT i = 0; i < dispatchCount; ++i) {
            Frame frame{width,height,scene ? selected : i,UINT(lights.size()),{-2,-2,1.99f},0.001f,
                {2,2,2.01f},0.001f,1,rangeCount,{0,0}};
            if (scene) {
                memcpy(frame.boundsMin,scene->minimum.data(),12);
                memcpy(frame.boundsMax,scene->maximum.data(),12);
            }
            memcpy(constants.data() + i * 256, &frame, sizeof(frame));
        }
        auto cb = Upload(constants.data(), constants.size());
        auto outputDesc = output->GetDesc();
        D3D12_PLACED_SUBRESOURCE_FOOTPRINT outputFootprint{}; UINT64 outputBytes = 0;
        device->GetCopyableFootprints(&outputDesc,0,1,0,&outputFootprint,nullptr,nullptr,&outputBytes);
        UINT64 outputStride = (outputBytes + 511) & ~UINT64(511);
        auto readback = Buffer(outputStride * dispatchCount, D3D12_HEAP_TYPE_READBACK, D3D12_RESOURCE_STATE_COPY_DEST);

        D3D12_DESCRIPTOR_RANGE ranges[2]{};
        ranges[0] = {D3D12_DESCRIPTOR_RANGE_TYPE_SRV,6,0,0,0};
        ranges[1] = {D3D12_DESCRIPTOR_RANGE_TYPE_UAV,1,0,0,6};
        D3D12_ROOT_PARAMETER roots[2]{};
        roots[0].ParameterType = D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
        roots[0].DescriptorTable = {2,ranges};
        roots[1].ParameterType = D3D12_ROOT_PARAMETER_TYPE_CBV;
        roots[1].Descriptor = {0,0};
        D3D12_ROOT_SIGNATURE_DESC rootDesc{2,roots,0,nullptr,D3D12_ROOT_SIGNATURE_FLAG_NONE};
        ComPtr<ID3DBlob> serialized, errors;
        HRESULT result = D3D12SerializeRootSignature(&rootDesc, D3D_ROOT_SIGNATURE_VERSION_1,
            &serialized, &errors);
        if (errors) fprintf(stderr, "%s\n", static_cast<const char*>(errors->GetBufferPointer()));
        Check(result, "Serialize root signature");
        ComPtr<ID3D12RootSignature> root;
        Check(device->CreateRootSignature(0, serialized->GetBufferPointer(), serialized->GetBufferSize(),
            IID_PPV_ARGS(&root)), "Create root signature");
        D3D12_COMPUTE_PIPELINE_STATE_DESC pipeline{};
        pipeline.pRootSignature = root.Get(); pipeline.CS = {code.data(),code.size()};
        ComPtr<ID3D12PipelineState> pso;
        Check(device->CreateComputePipelineState(&pipeline, IID_PPV_ARGS(&pso)), "Create compute PSO");
        ID3D12DescriptorHeap* heaps[] = {descriptors.Get()};
        list->SetDescriptorHeaps(1, heaps); list->SetPipelineState(pso.Get());
        list->SetComputeRootSignature(root.Get());
        list->SetComputeRootDescriptorTable(0, descriptors->GetGPUDescriptorHandleForHeapStart());
        for (UINT i = 0; i < dispatchCount; ++i) {
            list->SetComputeRootConstantBufferView(1, cb->GetGPUVirtualAddress() + i * 256);
            list->Dispatch((width+7)/8, (height+7)/8, 1);
            Transition(output.Get(), D3D12_RESOURCE_STATE_UNORDERED_ACCESS, D3D12_RESOURCE_STATE_COPY_SOURCE);
            D3D12_TEXTURE_COPY_LOCATION source{}, target{};
            source.pResource = output.Get(); source.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
            target.pResource = readback.Get(); target.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
            target.PlacedFootprint = outputFootprint;
            target.PlacedFootprint.Offset = UINT64(i) * outputStride;
            list->CopyTextureRegion(&target, 0, 0, 0, &source, nullptr);
            Transition(output.Get(), D3D12_RESOURCE_STATE_COPY_SOURCE, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
        }
        Check(list->Close(), "Close command list");
        ComPtr<ID3D12Fence> fence;
        Check(device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&fence)), "Create fence");
        HANDLE event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
        if (!event) throw std::runtime_error("CreateEvent failed");
        ID3D12CommandList* lists[] = {list.Get()}; queue->ExecuteCommandLists(1, lists);
        Check(queue->Signal(fence.Get(), 1), "Signal fence");
        Check(fence->SetEventOnCompletion(1, event), "Set fence event");
        DWORD waited = WaitForSingleObject(event, 30000); CloseHandle(event);
        if (waited != WAIT_OBJECT_0) {
            fprintf(stderr, "GPU wait failed/timed out; terminating without releasing in-flight resources.\n");
            ExitProcess(2);
        }
        Check(device->GetDeviceRemovedReason(), "Device status");
        void* mappedData = nullptr;
        D3D12_RANGE range{0,SIZE_T(outputStride * dispatchCount)};
        Check(readback->Map(0, &range, &mappedData), "Map readback");
        const auto* mapped = static_cast<const unsigned char*>(mappedData);
        if (scene) {
            std::ofstream file(outputPath,std::ios::binary | std::ios::trunc);
            if (!file) throw std::runtime_error("Cannot open visibility output");
            file.write("ALVOUT01",8);
            UINT count = UINT(scene->receivers.size());
            file.write(reinterpret_cast<const char*>(&count),4);
            file.write(reinterpret_cast<const char*>(&selected),4);
            UINT invalid = 0, unaffected = 0, visible = 0, occluded = 0, malformed = 0;
            for (UINT i = 0; i < count; ++i) {
                auto pair = reinterpret_cast<const float*>(mapped + size_t(i/width)*outputFootprint.Footprint.RowPitch + size_t(i%width)*8);
                file.write(reinterpret_cast<const char*>(pair),8);
                if (pair[1] == 0 && pair[0] == 1) ++invalid;
                else if (pair[1] == 2 && pair[0] == 1) ++unaffected;
                else if (pair[1] == 1 && pair[0] == 1) ++visible;
                else if (pair[1] == 1 && pair[0] == 0) ++occluded;
                else ++malformed;
            }
            file.close();
            if (!file) throw std::runtime_error("Visibility output write failed");
            D3D12_RANGE empty{0,0}; readback->Unmap(0,&empty);
            printf("selected=%u receivers=%u visible=%u occluded=%u unaffected=%u invalid=%u malformed=%u\n",
                selected,count,visible,occluded,unaffected,invalid,malformed);
            printf("Opaque frozen snapshot only; counts do not prove geometry completeness or visual fidelity.\n");
            return malformed ? 1 : 0;
        }
        const char* names[] = {"directional blocked", "punctual beyond caster", "punctual before caster",
            "caster rendering mask", "receiver rendering mask", "invalid directional"};
        unsigned failures = 0;
        for (UINT i = 0; i < lights.size(); ++i) {
            auto values = reinterpret_cast<const float*>(mapped + i * outputStride);
            for (UINT pixel = 0; pixel < 4; ++pixel) {
                float expectedVisibility = (i < 2 && pixel == 0) ? 0.0f : 1.0f;
                float expectedStatus = pixel == 1 ? 0.0f : (pixel == 2 || i == 4) ? 2.0f : i == 5 ? 0.0f : 1.0f;
                bool pass = values[pixel*2] == expectedVisibility && values[pixel*2+1] == expectedStatus;
                printf("%s pixel%u: (%g,%g), expected (%g,%g) %s\n", names[i],pixel,
                    values[pixel*2],values[pixel*2+1],expectedVisibility,expectedStatus,pass ? "PASS" : "FAIL");
                failures += !pass;
            }
        }
        D3D12_RANGE empty{0,0}; readback->Unmap(0, &empty);
        printf("%u/24 checks passed. Synthetic visibility only; no AL integration or performance claim.\n",24-failures);
        return failures ? 1 : 0;
    }
};

int wmain(int argc, wchar_t** argv)
{
    try {
        if (argc == 3 && wcscmp(argv[1],L"--validate-scene") == 0) {
            LoadSnapshot(argv[2]); return 0;
        }
        if (argc == 6 && wcscmp(argv[1],L"--run-scene") == 0) {
            Snapshot scene = LoadSnapshot(argv[3]);
            std::wstring number(argv[4]);
            if (number.empty() || number.find_first_not_of(L"0123456789") != std::wstring::npos)
                throw std::runtime_error("Selected light must be a nonnegative integer");
            auto selected = std::stoull(number);
            if (selected >= scene.lights.size()) throw std::runtime_error("Selected light out of range");
            if (std::filesystem::exists(argv[5]) && (std::filesystem::equivalent(argv[5],argv[3])
                || std::filesystem::equivalent(argv[5],argv[2])))
                throw std::runtime_error("Output must not overwrite an input");
            Smoke smoke; return smoke.Run(argv[2],&scene,UINT(selected),argv[5]);
        }
        if (argc == 3 && wcscmp(argv[1],L"--run") == 0) {
            Smoke smoke; return smoke.Run(argv[2]);
        }
        fprintf(stderr, "Usage:\n  map_visibility_smoke.exe --run MapLightVisibility.dxil\n"
            "  map_visibility_smoke.exe --validate-scene snapshot.bin\n"
            "  map_visibility_smoke.exe --run-scene MapLightVisibility.dxil snapshot.bin lightIndex output.bin\n"
            "Only --run and --run-scene enable standalone GPU execution.\n");
        return 2;
    }
    catch (const std::exception& error) { fprintf(stderr, "%s\n", error.what()); return 2; }
}
