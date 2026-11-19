#include <Windows.h>
#include <d3d11.h>
#include <d3d11_4.h>
#include <wrl/client.h>
#include <openvr_capi.h>

#include <cstdio>
#include <cmath>
#include <cstring>
#include <limits>
#include <mutex>
#include <array>
#include <algorithm>
#include <optional>

using Microsoft::WRL::ComPtr;

namespace
{
    struct EyeInfo
    {
        HmdMatrix34_t eyeToHead;
        float left;
        float right;
        float top;
        float bottom;
    };

    struct DisplayInfo
    {
        uint32_t width;
        uint32_t height;
        EyeInfo left;
        EyeInfo right;
    };

    enum ControllerButtons : uint32_t { Trigger = 1, Secondary = 2, Menu = 4, Grip = 8, Mode = 16 };

    struct ControllerInput
    {
        uint32_t device;
        uint32_t buttons, clicked;
        float scroll;
        float panelX, panelY;
        uint32_t pointsAtPanel;
        uint32_t hasInput;
        HmdMatrix34_t gripPose, aimPose;
        float rayLength;
    };

    static_assert(sizeof(HmdMatrix34_t) == 48);
    static_assert(sizeof(EyeInfo) == 64);
    static_assert(sizeof(DisplayInfo) == 136);
    static_assert(sizeof(ControllerInput) == 132);

    using Init = intptr_t(__cdecl*)(EVRInitError*, EVRApplicationType);
    using Shutdown = void(__cdecl*)();
    using IsHmdPresent = bool(__cdecl*)();
    using GetInterface = intptr_t(__cdecl*)(const char*, EVRInitError*);
    using DescribeError = const char*(__cdecl*)(EVRInitError);

    constexpr auto noError = EVRCompositorError_VRCompositorError_None;
    constexpr auto noFocus = EVRCompositorError_VRCompositorError_DoNotHaveFocus;
    constexpr auto sceneApp = EVRApplicationType_VRApplication_Scene;

    std::mutex sessionMutex;
    HMODULE openVr;
    Shutdown shutdown;
    VR_IVRSystem_FnTable* vrSystem;
    VR_IVRCompositor_FnTable* compositor;
    GetInterface getInterface;
    VR_IVROverlay_FnTable* overlay;
    VR_IVRRenderModels_FnTable* renderModels;
    VROverlayHandle_t panel;
    HmdMatrix34_t panelTransform;
    constexpr float panelWidth = 0.9f;
    TrackedDeviceIndex_t panelGrabDevice = k_unTrackedDeviceIndexInvalid;
    HmdMatrix34_t panelFromGrip;
    float panelHeight;
    ComPtr<ID3D11Texture2D> panelTexture;
    int pendingPanelEvent;
    EVROverlayError panelError;
    TrackedDeviceIndex_t activeController = k_unTrackedDeviceIndexInvalid;
    std::array<std::optional<uint32_t>, k_unMaxTrackedDeviceCount> previousControllerButtons;
    std::array<std::array<char, 256>, k_unMaxTrackedDeviceCount> controllerModels;
    bool initialized;
    ComPtr<ID3D11Texture2D> textures[2];
    ComPtr<ID3D11Multithread> immediateContext;
    BOOL previousMultithreadProtection;
    int nextEvent;
    int pendingEvent;
    uint64_t submittedFrames;
    char lastError[256];

    void SetError(const char* message)
    {
        std::snprintf(lastError, sizeof(lastError), "%s", message);
    }

    void SetError(const char* operation, int result)
    {
        std::snprintf(lastError, sizeof(lastError), "%s failed (%d)", operation, result);
    }

    template <typename Function>
    Function LoadExport(const char* name)
    {
        // Windows FARPROC can represent any function pointer exported by GetProcAddress.
        auto address = GetProcAddress(openVr, name);
        static_assert(sizeof(address) == sizeof(Function));
        Function function;
        std::memcpy(&function, &address, sizeof(function));
        return function;
    }

    template <typename Interface>
    Interface* GetFunctionTable(const char* version, bool required = true)
    {
        char name[64];
        std::snprintf(name, sizeof(name), "FnTable:%s", version);
        EVRInitError result = EVRInitError_VRInitError_None;
        auto table = getInterface(name, &result);
        if (result != EVRInitError_VRInitError_None || !table)
        {
            if (required)
                SetError(name, result);
            return nullptr;
        }
        return reinterpret_cast<Interface*>(table);
    }

    void ClosePanel()
    {
        panelGrabDevice = k_unTrackedDeviceIndexInvalid;
        pendingPanelEvent = 0;
        if (panel)
            overlay->DestroyOverlay(panel);
        panel = 0;
        panelTexture.Reset();
        panelHeight = 0;
        panelError = EVROverlayError_VROverlayError_None;
    }

    void CloseSession()
    {
        // An event queued before stop may still run after restart. Its ID will no
        // longer match any armed submission, and the bridge itself stays loaded.
        pendingEvent = 0;
        ClosePanel();
        overlay = nullptr;
        renderModels = nullptr;
        activeController = k_unTrackedDeviceIndexInvalid;
        previousControllerButtons = {};
        controllerModels = {};
        if (compositor)
            compositor->ClearLastSubmittedFrame();
        if (initialized)
            shutdown();
        initialized = false;
        compositor = nullptr;
        vrSystem = nullptr;
        getInterface = nullptr;
        shutdown = nullptr;
        for (auto& texture : textures)
            texture.Reset();
        if (immediateContext)
        {
            immediateContext->SetMultithreadProtected(previousMultithreadProtection);
            immediateContext.Reset();
        }
        if (openVr)
            FreeLibrary(openVr);
        openVr = nullptr;
    }

    EyeInfo ReadEye(EVREye eye)
    {
        EyeInfo info{};
        info.eyeToHead = vrSystem->GetEyeToHeadTransform(eye);
        vrSystem->GetProjectionRaw(eye, &info.left, &info.right, &info.top, &info.bottom);
        return info;
    }

    HmdMatrix34_t Compose(const HmdMatrix34_t& device, const HmdMatrix34_t& component)
    {
        HmdMatrix34_t result{};
        for (int row = 0; row < 3; ++row)
        {
            result.m[row][3] = device.m[row][3];
            for (int column = 0; column < 4; ++column)
                for (int axis = 0; axis < 3; ++axis)
                    result.m[row][column] += device.m[row][axis] * component.m[axis][column];
        }
        return result;
    }

    HmdMatrix34_t InverseRigid(const HmdMatrix34_t& pose)
    {
        HmdMatrix34_t result{};
        for (int row = 0; row < 3; ++row)
        {
            for (int column = 0; column < 3; ++column)
            {
                result.m[row][column] = pose.m[column][row];
                result.m[row][3] -= pose.m[column][row] * pose.m[column][3];
            }
        }
        return result;
    }

    char* ControllerModelName(TrackedDeviceIndex_t device)
    {
        auto& name = controllerModels[device];
        if (!name[0])
        {
            ETrackedPropertyError error{};
            vrSystem->GetStringTrackedDeviceProperty(device, ETrackedDeviceProperty_Prop_RenderModelName_String,
                name.data(), static_cast<uint32_t>(name.size()), &error);
            if (error != ETrackedPropertyError_TrackedProp_Success)
                name[0] = '\0';
        }
        return name.data();
    }

    HmdMatrix34_t AimPose(TrackedDeviceIndex_t device, VRControllerState_t& state, const HmdMatrix34_t& grip)
    {
        if (renderModels)
        {
            char tip[] = "tip";
            RenderModel_ControllerMode_State_t mode{};
            RenderModel_ComponentState_t component{};
            auto name = ControllerModelName(device);
            if (*name && renderModels->GetComponentState(name, tip, &state, &mode, &component))
                return Compose(grip, component.mTrackingToComponentLocal);
        }
        return grip;
    }

    void ProjectPanelPointer(const HmdMatrix34_t& controller, ControllerInput& input)
    {
        if (!panelHeight)
            return;

        // Intersect the controller's -Z ray with the same plane given to SteamVR.
        // Return top-left coordinates so the point maps directly to the game window.
        const auto& p = panelTransform.m;
        const auto& c = controller.m;
        float direction = -c[0][2] * p[0][2] - c[1][2] * p[1][2] - c[2][2] * p[2][2];
        if (!(direction < -0.001f))
            return;
        float distance = ((p[0][3] - c[0][3]) * p[0][2] + (p[1][3] - c[1][3]) * p[1][2] +
            (p[2][3] - c[2][3]) * p[2][2]) / direction;
        if (!(distance > 0))
            return;
        float x = c[0][3] - c[0][2] * distance - p[0][3];
        float y = c[1][3] - c[1][2] * distance - p[1][3];
        float z = c[2][3] - c[2][2] * distance - p[2][3];
        input.panelX = 0.5f + (x * p[0][0] + y * p[1][0] + z * p[2][0]) / panelWidth;
        input.panelY = 0.5f - (x * p[0][1] + y * p[1][1] + z * p[2][1]) / panelHeight;
        input.pointsAtPanel = input.panelX >= 0 && input.panelX < 1 && input.panelY >= 0 && input.panelY < 1;
        if (input.pointsAtPanel)
            input.rayLength = distance;
    }

    ControllerInput ReadControllerInput(TrackedDeviceIndex_t device, const TrackedDevicePose_t& pose, bool canReadButtons)
    {
        ControllerInput input{};
        input.device = device;
        input.gripPose = pose.mDeviceToAbsoluteTracking;
        input.panelX = input.panelY = std::numeric_limits<float>::quiet_NaN();
        input.rayLength = 1.5f;
        VRControllerState_t state{};
        input.hasInput = canReadButtons && vrSystem->GetControllerState(device, &state, sizeof(state));
        input.aimPose = AimPose(device, state, input.gripPose);
        ProjectPanelPointer(input.aimPose, input);
        auto& previous = previousControllerButtons[device];
        if (!input.hasInput)
        {
            previous.reset();
            return input;
        }

        auto pressed = [&](EVRButtonId button) { return (state.ulButtonPressed & (uint64_t{1} << button)) != 0; };
        if (pressed(EVRButtonId_k_EButton_SteamVR_Trigger)) input.buttons |= Trigger;
        if (pressed(EVRButtonId_k_EButton_Grip)) input.buttons |= Grip;
        if (pressed(EVRButtonId_k_EButton_A)) input.buttons |= Secondary;
        if (pressed(EVRButtonId_k_EButton_ApplicationMenu)) input.buttons |= Menu;

        float trigger = 0;
        float touchpadY = 0;
        bool hasStick = false;
        for (int axis = 0; axis < static_cast<int>(_countof(state.rAxis)); ++axis)
        {
            auto property = static_cast<ETrackedDeviceProperty>(ETrackedDeviceProperty_Prop_Axis0Type_Int32 + axis);
            auto type = vrSystem->GetInt32TrackedDeviceProperty(device, property, nullptr);
            auto button = static_cast<EVRButtonId>(EVRButtonId_k_EButton_Axis0 + axis);
            if (type == EVRControllerAxisType_k_eControllerAxis_Trigger)
            {
                if (button == EVRButtonId_k_EButton_Axis2)
                {
                    float threshold = (previous.value_or(0) & Grip) ? 0.4f : 0.65f;
                    if (pressed(button) || state.rAxis[axis].x >= threshold) input.buttons |= Grip;
                }
                else
                    trigger = std::max(trigger, state.rAxis[axis].x);
            }
            else if (type == EVRControllerAxisType_k_eControllerAxis_Joystick)
            {
                hasStick = true;
                input.scroll = state.rAxis[axis].y;
                if (pressed(button)) input.buttons |= Mode;
            }
            else if (type == EVRControllerAxisType_k_eControllerAxis_TrackPad)
            {
                if (state.ulButtonTouched & (uint64_t{1} << button))
                    touchpadY = state.rAxis[axis].y;
                if (pressed(button)) input.buttons |= Mode;
            }
        }
        if (!hasStick)
            input.scroll = touchpadY;

        float triggerThreshold = (previous.value_or(0) & Trigger) ? 0.4f : 0.65f;
        if (trigger >= triggerThreshold)
            input.buttons |= Trigger;
        // A hand that just became available may already be holding a button.
        if (previous)
            input.clicked = input.buttons & ~*previous;
        previous = input.buttons;
        return input;
    }

    int NextRenderEvent()
    {
        if (nextEvent == std::numeric_limits<int>::max())
            nextEvent = 0;
        return ++nextEvent;
    }

    void __stdcall SubmitFrame(int eventId)
    {
        std::lock_guard lock(sessionMutex);
        if (pendingPanelEvent && pendingPanelEvent == eventId)
        {
            pendingPanelEvent = 0;
            Texture_t texture{panelTexture.Get(), ETextureType_TextureType_DirectX, EColorSpace_ColorSpace_Auto};
            panelError = overlay->SetOverlayTexture(panel, &texture);
            if (panelError == EVROverlayError_VROverlayError_None)
            {
                D3D11_TEXTURE2D_DESC description{};
                panelTexture->GetDesc(&description);
                panelHeight = panelWidth * static_cast<float>(description.Height) / static_cast<float>(description.Width);
                if (!overlay->IsOverlayVisible(panel))
                    panelError = overlay->ShowOverlay(panel);
            }
            return;
        }
        if (!compositor || pendingEvent != eventId)
            return;

        constexpr EVREye eyes[] = {EVREye_Eye_Left, EVREye_Eye_Right};
        bool submitted = true;
        for (size_t i = 0; i < _countof(eyes); ++i)
        {
            Texture_t texture{textures[i].Get(), ETextureType_TextureType_DirectX, EColorSpace_ColorSpace_Auto};
            // Unity's D3D11 camera targets are vertically flipped in the
            // compositor. The UI camera has its own overlay texture bounds.
            VRTextureBounds_t bounds{0.0f, 1.0f, 1.0f, 0.0f};
            auto result = compositor->Submit(eyes[i], &texture, &bounds, EVRSubmitFlags_Submit_Default);
            if (result != noError)
            {
                if (result != noFocus)
                    SetError(i == 0 ? "OpenVR left eye submission" : "OpenVR right eye submission", result);
                submitted = false;
                break;
            }
        }
        if (submitted)
            ++submittedFrames;
        pendingEvent = 0;
    }
}

#define AL_VR_EXPORT extern "C" __declspec(dllexport)

AL_VR_EXPORT int AlVrStart(const wchar_t* libraryPath, DisplayInfo* info)
{
    std::lock_guard lock(sessionMutex);
    CloseSession();
    submittedFrames = 0;
    lastError[0] = '\0';
    openVr = LoadLibraryExW(libraryPath, nullptr, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
    if (!openVr)
    {
        SetError("Loading openvr_api.dll", static_cast<int>(GetLastError()));
        return 0;
    }

    auto init = LoadExport<Init>("VR_InitInternal");
    shutdown = LoadExport<Shutdown>("VR_ShutdownInternal");
    auto isHmdPresent = LoadExport<IsHmdPresent>("VR_IsHmdPresent");
    getInterface = LoadExport<GetInterface>("VR_GetGenericInterface");
    auto describeError = LoadExport<DescribeError>("VR_GetVRInitErrorAsEnglishDescription");
    if (!init || !shutdown || !isHmdPresent || !getInterface)
    {
        SetError("openvr_api.dll is missing required exports");
        CloseSession();
        return 0;
    }
    if (!isHmdPresent())
    {
        SetError("SteamVR did not report a connected headset");
        CloseSession();
        return 0;
    }

    EVRInitError result = EVRInitError_VRInitError_None;
    init(&result, sceneApp);
    if (result != EVRInitError_VRInitError_None)
    {
        const char* description = describeError ? describeError(result) : nullptr;
        if (description)
            SetError(description);
        else
            SetError("VR_InitInternal", result);
        CloseSession();
        return 0;
    }

    initialized = true;
    vrSystem = GetFunctionTable<VR_IVRSystem_FnTable>(IVRSystem_Version);
    if (vrSystem)
        compositor = GetFunctionTable<VR_IVRCompositor_FnTable>(IVRCompositor_Version);
    if (!vrSystem || !compositor)
    {
        CloseSession();
        return 0;
    }

    renderModels = GetFunctionTable<VR_IVRRenderModels_FnTable>(IVRRenderModels_Version, false);

    compositor->SetTrackingSpace(ETrackingUniverseOrigin_TrackingUniverseSeated);
    vrSystem->GetRecommendedRenderTargetSize(&info->width, &info->height);
    info->left = ReadEye(EVREye_Eye_Left);
    info->right = ReadEye(EVREye_Eye_Right);
    return 1;
}

AL_VR_EXPORT int AlVrSetTextures(ID3D11Resource* left, ID3D11Resource* right)
{
    std::lock_guard lock(sessionMutex);
    if (!compositor)
        return 0;

    ComPtr<ID3D11Texture2D> nextLeft, nextRight;
    if (!left || !right || FAILED(left->QueryInterface(IID_PPV_ARGS(&nextLeft))) ||
        FAILED(right->QueryInterface(IID_PPV_ARGS(&nextRight))))
    {
        SetError("Unity's VR targets must be D3D11 Texture2D resources");
        return 0;
    }

    D3D11_TEXTURE2D_DESC leftDesc{}, rightDesc{};
    nextLeft->GetDesc(&leftDesc);
    nextRight->GetDesc(&rightDesc);
    if (leftDesc.Width != rightDesc.Width || leftDesc.Height != rightDesc.Height ||
        leftDesc.SampleDesc.Count != 1 || rightDesc.SampleDesc.Count != 1 ||
        leftDesc.ArraySize != 1 || rightDesc.ArraySize != 1 ||
        leftDesc.MipLevels != 1 || rightDesc.MipLevels != 1 || leftDesc.Format != rightDesc.Format)
    {
        SetError("OpenVR eye textures must have matching dimensions and formats and be single-sampled 2D images");
        return 0;
    }

    ComPtr<ID3D11Device> leftDevice, rightDevice;
    nextLeft->GetDevice(&leftDevice);
    nextRight->GetDevice(&rightDevice);
    if (leftDevice.Get() != rightDevice.Get())
    {
        SetError("Both OpenVR eye textures must use the same D3D11 device");
        return 0;
    }

    ComPtr<ID3D11DeviceContext> context;
    ComPtr<ID3D11Multithread> protection;
    leftDevice->GetImmediateContext(&context);
    if (FAILED(context.As(&protection)))
    {
        SetError("Could not protect Unity's D3D11 immediate context for OpenVR");
        return 0;
    }

    if (immediateContext.Get() != protection.Get())
    {
        if (immediateContext)
            immediateContext->SetMultithreadProtected(previousMultithreadProtection);
        // SteamVR's main-thread WaitGetPoses can enqueue a D3D11 timestamp
        // while Unity is still processing companion-window commands.
        previousMultithreadProtection = protection->SetMultithreadProtected(TRUE);
        immediateContext.Swap(protection);
    }

    textures[0].Swap(nextLeft);
    textures[1].Swap(nextRight);
    return 1;
}

// 1 supplies a tracked pose, 0 skips this frame, and -1 ends the session.
AL_VR_EXPORT int AlVrBeginFrame(HmdMatrix34_t* headToTracking)
{
    std::lock_guard lock(sessionMutex);
    if (lastError[0] || !compositor)
        return -1;
    if (pendingEvent)
        return 0;

    VREvent_t event{};
    while (vrSystem->PollNextEvent(&event, sizeof(event)))
    {
        if (event.eventType == EVREventType_VREvent_Quit)
        {
            SetError("SteamVR requested that the scene application disconnect");
            return -1;
        }
    }

    TrackedDevicePose_t hmd{};
    auto result = compositor->WaitGetPoses(&hmd, 1, nullptr, 0);
    if (result == noFocus)
        return 0;
    if (result != noError)
    {
        SetError("OpenVR WaitGetPoses", result);
        return -1;
    }
    if (!hmd.bDeviceIsConnected)
    {
        SetError("SteamVR headset disconnected");
        return -1;
    }
    if (!hmd.bPoseIsValid)
        return 0;

    *headToTracking = hmd.mDeviceToAbsoluteTracking;
    return 1;
}

AL_VR_EXPORT int AlVrArmSubmit()
{
    std::lock_guard lock(sessionMutex);
    if (!compositor || pendingEvent || !textures[0] || !textures[1])
    {
        SetError("VR frame submission has no active session or eye targets");
        return 0;
    }
    pendingEvent = NextRenderEvent();
    return pendingEvent;
}

AL_VR_EXPORT auto AlVrRenderEvent() -> decltype(&SubmitFrame)
{
    return &SubmitFrame;
}

AL_VR_EXPORT int AlVrReadController(ControllerInput* input)
{
    std::lock_guard lock(sessionMutex);
    *input = {};
    if (!vrSystem)
        return 0;

    bool canReadButtons = vrSystem->IsInputAvailable();
    TrackedDevicePose_t poses[k_unMaxTrackedDeviceCount]{};
    vrSystem->GetDeviceToAbsoluteTrackingPose(ETrackingUniverseOrigin_TrackingUniverseSeated, 0, poses, _countof(poses));
    ControllerInput clicked{};
    for (TrackedDeviceIndex_t device = 1; device < k_unMaxTrackedDeviceCount; ++device)
    {
        const auto& pose = poses[device];
        if (!pose.bDeviceIsConnected || !pose.bPoseIsValid ||
            vrSystem->GetTrackedDeviceClass(device) != ETrackedDeviceClass_TrackedDeviceClass_Controller)
        {
            previousControllerButtons[device].reset();
            if (!pose.bDeviceIsConnected)
                controllerModels[device][0] = '\0';
            continue;
        }
        auto sample = ReadControllerInput(device, pose, canReadButtons);
        if (!input->device || sample.hasInput > input->hasInput ||
            (sample.hasInput == input->hasInput && device == activeController))
            *input = sample;
        // Polling cannot order two presses in the same frame. Prefer the
        // active hand if it clicked too, then the first tracked index.
        if (sample.clicked && (!clicked.device || device == activeController))
            clicked = sample;
    }

    if (clicked.device)
        *input = clicked;
    activeController = input->device ? input->device : k_unTrackedDeviceIndexInvalid;
    return input->device != 0;
}

// The runtime owns the model until the caller copies it and releases it.
// 0 means it is still loading, -1 means the device has no usable model.
AL_VR_EXPORT int AlVrLoadControllerModel(uint32_t device, RenderModel_t** model)
{
    std::lock_guard lock(sessionMutex);
    *model = nullptr;
    if (!renderModels || device >= k_unMaxTrackedDeviceCount)
        return -1;
    auto name = ControllerModelName(device);
    if (!*name)
        return -1;
    auto result = renderModels->LoadRenderModel_Async(name, model);
    if (result == EVRRenderModelError_VRRenderModelError_Loading)
        return 0;
    return result == EVRRenderModelError_VRRenderModelError_None && *model ? 1 : -1;
}

AL_VR_EXPORT void AlVrFreeControllerModel(RenderModel_t* model)
{
    std::lock_guard lock(sessionMutex);
    if (renderModels && model)
        renderModels->FreeRenderModel(model);
}

AL_VR_EXPORT void AlVrSuspendControllerInput()
{
    std::lock_guard lock(sessionMutex);
    previousControllerButtons = {};
    panelGrabDevice = k_unTrackedDeviceIndexInvalid;
}

// Opens beside the active controller, upright in the headset's heading.
// Wait for a tracked controller rather than spawning an unreachable panel.
AL_VR_EXPORT int AlVrOpenPanel()
{
    std::lock_guard lock(sessionMutex);
    if (!vrSystem)
        return -1;
    TrackedDevicePose_t poses[k_unMaxTrackedDeviceCount]{};
    vrSystem->GetDeviceToAbsoluteTrackingPose(ETrackingUniverseOrigin_TrackingUniverseSeated, 0, poses, _countof(poses));
    const auto& head = poses[0];
    if (!head.bDeviceIsConnected || !head.bPoseIsValid)
        return 0;

    if (!overlay)
        overlay = GetFunctionTable<VR_IVROverlay_FnTable>(IVROverlay_Version, false);
    if (!overlay)
        return -1;
    if (activeController >= k_unMaxTrackedDeviceCount || !poses[activeController].bDeviceIsConnected ||
        !poses[activeController].bPoseIsValid)
        return 0;
    if (!panel)
    {
        char key[] = "com.al-vr.steamvr.game-panel";
        char name[] = "Amanatsu Location";
        if (overlay->CreateOverlay(key, name, &panel) != EVROverlayError_VROverlayError_None)
        {
            panel = 0;
            return -1;
        }
        VRTextureBounds_t bounds{0.0f, 1.0f, 1.0f, 0.0f};
        if (overlay->SetOverlayWidthInMeters(panel, panelWidth) != EVROverlayError_VROverlayError_None ||
            overlay->SetOverlayTextureBounds(panel, &bounds) != EVROverlayError_VROverlayError_None ||
            overlay->SetOverlayFlag(panel, VROverlayFlags_IgnoreTextureAlpha, false) != EVROverlayError_VROverlayError_None ||
            overlay->SetOverlayFlag(panel, VROverlayFlags_IsPremultiplied, true) != EVROverlayError_VROverlayError_None)
        {
            ClosePanel();
            return -1;
        }
    }

    const auto& m = head.mDeviceToAbsoluteTracking.m;
    float length = std::hypot(m[0][2], m[2][2]);
    float x = length > 0.001f ? m[0][2] / length : 0;
    float z = length > 0.001f ? m[2][2] / length : 1;
    const auto& hand = poses[activeController].mDeviceToAbsoluteTracking.m;
    constexpr float distance = 0.55f;
    panelGrabDevice = k_unTrackedDeviceIndexInvalid;
    panelTransform = {{{z, 0, x, hand[0][3] - x * distance}, {0, 1, 0, hand[1][3]}, {-x, 0, z, hand[2][3] - z * distance}}};
    if (overlay->SetOverlayTransformAbsolute(panel, ETrackingUniverseOrigin_TrackingUniverseSeated, &panelTransform) !=
            EVROverlayError_VROverlayError_None)
    {
        ClosePanel();
        return -1;
    }
    return 1;
}

// Preserve the initial hand-to-panel offset while moving and rotating the hand.
AL_VR_EXPORT int AlVrDragPanel(uint32_t device, int held)
{
    std::lock_guard lock(sessionMutex);
    if (!held || !panel || !vrSystem || device >= k_unMaxTrackedDeviceCount)
    {
        panelGrabDevice = k_unTrackedDeviceIndexInvalid;
        return 0;
    }
    TrackedDevicePose_t poses[k_unMaxTrackedDeviceCount]{};
    vrSystem->GetDeviceToAbsoluteTrackingPose(ETrackingUniverseOrigin_TrackingUniverseSeated, 0, poses, _countof(poses));
    const auto& pose = poses[device];
    if (!pose.bDeviceIsConnected || !pose.bPoseIsValid || !vrSystem->IsInputAvailable())
    {
        panelGrabDevice = k_unTrackedDeviceIndexInvalid;
        return 0;
    }
    if (panelGrabDevice != device)
    {
        panelFromGrip = Compose(InverseRigid(pose.mDeviceToAbsoluteTracking), panelTransform);
        panelGrabDevice = device;
    }
    panelTransform = Compose(pose.mDeviceToAbsoluteTracking, panelFromGrip);
    panelError = overlay->SetOverlayTransformAbsolute(panel, ETrackingUniverseOrigin_TrackingUniverseSeated, &panelTransform);
    return panelError == EVROverlayError_VROverlayError_None ? 1 : -1;
}

AL_VR_EXPORT int AlVrQueuePanel(ID3D11Resource* resource)
{
    std::lock_guard lock(sessionMutex);
    if (!panel || panelError != EVROverlayError_VROverlayError_None)
        return -1;
    if (pendingPanelEvent)
        return 0;
    ComPtr<ID3D11Texture2D> texture;
    if (!resource || FAILED(resource->QueryInterface(IID_PPV_ARGS(&texture))))
        return -1;
    panelTexture.Swap(texture);
    pendingPanelEvent = NextRenderEvent();
    return pendingPanelEvent;
}

AL_VR_EXPORT void AlVrClosePanel()
{
    std::lock_guard lock(sessionMutex);
    ClosePanel();
}

AL_VR_EXPORT void AlVrStop()
{
    std::lock_guard lock(sessionMutex);
    CloseSession();
}

AL_VR_EXPORT uint64_t AlVrSubmittedFrames()
{
    std::lock_guard lock(sessionMutex);
    return submittedFrames;
}

AL_VR_EXPORT int AlVrPanelReady()
{
    std::lock_guard lock(sessionMutex);
    return panelHeight > 0 && panelError == EVROverlayError_VROverlayError_None;
}

AL_VR_EXPORT void AlVrGetLastError(char* destination, size_t capacity)
{
    std::lock_guard lock(sessionMutex);
    if (capacity)
        std::snprintf(destination, capacity, "%s", lastError);
}
