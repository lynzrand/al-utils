#include <d3d12.h>
#include <wrl/client.h>

extern "C" __declspec(dllexport) unsigned AL_QueryDxr(ID3D12Resource* resource)
{
    // Query the device that owns the supplied Unity buffer.
    if (!resource) return 0;
    Microsoft::WRL::ComPtr<ID3D12Device> device;
    if (FAILED(resource->GetDevice(IID_PPV_ARGS(&device)))) return 0;
    D3D12_FEATURE_DATA_D3D12_OPTIONS5 options{};
    if (FAILED(device->CheckFeatureSupport(D3D12_FEATURE_D3D12_OPTIONS5, &options, sizeof(options)))) return 0;

    D3D12_FEATURE_DATA_SHADER_MODEL shaderModel{D3D_SHADER_MODEL_6_5};
    if (FAILED(device->CheckFeatureSupport(D3D12_FEATURE_SHADER_MODEL, &shaderModel, sizeof(shaderModel))))
        shaderModel.HighestShaderModel = D3D_SHADER_MODEL_5_1;
    return static_cast<unsigned>(options.RaytracingTier) |
        (static_cast<unsigned>(shaderModel.HighestShaderModel) << 16);
}
