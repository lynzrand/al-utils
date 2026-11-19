#include <Windows.h>
#include <d3d11.h>
#include <openvr_capi.h>

#include <cstdio>
#include <cstring>

namespace
{
    bool initialized;
    uint32_t acceptedEyes;
    uint32_t eyeMask;
    void* leftEye;
    char mode[32];
    uint32_t connectedControllers, trackedControllers;
    uint64_t controllerButtons[2];
    float controllerTriggers[2];
    bool inputAvailable, panelVisible;
    bool panelAlpha, panelPremultiplied, panelBounds;
    uint32_t panelFrames;
    int modelLoads;
    HmdMatrix34_t controllerPoses[2], lastPanelTransform;

    bool HasMode(const char* name)
    {
        return std::strcmp(mode, name) == 0;
    }

    HmdMatrix34_t Transform(float x, float y, float z)
    {
        return {{{1, 0, 0, x}, {0, 1, 0, y}, {0, 0, 1, z}}};
    }

    void __stdcall TargetSize(uint32_t* width, uint32_t* height)
    {
        *width = 640;
        *height = 480;
    }

    void __stdcall Projection(EVREye eye, float* left, float* right, float* top, float* bottom)
    {
        *left = eye == EVREye_Eye_Left ? -1.2f : -0.9f;
        *right = eye == EVREye_Eye_Left ? 0.9f : 1.2f;
        *top = -1.0f;
        *bottom = 0.85f;
    }

    HmdMatrix34_t __stdcall EyeTransform(EVREye eye)
    {
        return Transform(eye == EVREye_Eye_Left ? -0.031f : 0.031f, 0, 0);
    }

    bool __stdcall NextEvent(VREvent_t*, uint32_t)
    {
        return false;
    }

    void __stdcall SetTrackingSpace(ETrackingUniverseOrigin) {}
    void __stdcall ClearFrame() {}

    void __stdcall AbsolutePose(ETrackingUniverseOrigin, float, TrackedDevicePose_t* poses, uint32_t count)
    {
        if (count > 0)
        {
            poses[0].mDeviceToAbsoluteTracking = Transform(0.1f, 0.2f, -0.3f);
            poses[0].bDeviceIsConnected = poses[0].bPoseIsValid = true;
        }
        for (uint32_t device = 1; device < count && device <= 3; ++device)
        {
            poses[device].bDeviceIsConnected = (connectedControllers & (1u << device)) != 0;
            poses[device].bPoseIsValid = (trackedControllers & (1u << device)) != 0;
            poses[device].mDeviceToAbsoluteTracking = controllerPoses[device == 1 ? 0 : 1];
        }
    }

    bool __stdcall IsInputAvailable() { return inputAvailable; }
    ETrackedDeviceClass __stdcall DeviceClass(TrackedDeviceIndex_t device)
    {
        return device == 3 ? ETrackedDeviceClass_TrackedDeviceClass_GenericTracker :
            ETrackedDeviceClass_TrackedDeviceClass_Controller;
    }

    int32_t __stdcall AxisType(TrackedDeviceIndex_t device, ETrackedDeviceProperty property, ETrackedPropertyError*)
    {
        if (property == ETrackedDeviceProperty_Prop_Axis0Type_Int32) return EVRControllerAxisType_k_eControllerAxis_TrackPad;
        if (property == ETrackedDeviceProperty_Prop_Axis1Type_Int32) return EVRControllerAxisType_k_eControllerAxis_Trigger;
        if (property == ETrackedDeviceProperty_Prop_Axis2Type_Int32) return EVRControllerAxisType_k_eControllerAxis_Trigger;
        if (device == 2 && property == ETrackedDeviceProperty_Prop_Axis3Type_Int32) return EVRControllerAxisType_k_eControllerAxis_Joystick;
        return EVRControllerAxisType_k_eControllerAxis_None;
    }

    bool __stdcall ControllerState(TrackedDeviceIndex_t device, VRControllerState_t* state, uint32_t size)
    {
        if (size != sizeof(*state))
            return false;
        state->ulButtonPressed = controllerButtons[device - 1];
        state->ulButtonTouched = uint64_t{1} << EVRButtonId_k_EButton_Axis0;
        state->rAxis[0].y = 0.7f;
        state->rAxis[1].x = controllerTriggers[device - 1];
        state->rAxis[2].x = 0.2f;
        state->rAxis[3].y = -0.5f;
        return true;
    }

    uint32_t __stdcall StringProperty(TrackedDeviceIndex_t device, ETrackedDeviceProperty property, char* value,
        uint32_t size, ETrackedPropertyError* error)
    {
        const char* name = device == 1 ? "mock-left" : "mock-right";
        if (property != ETrackedDeviceProperty_Prop_RenderModelName_String || strcpy_s(value, size, name) != 0)
        {
            *error = ETrackedPropertyError_TrackedProp_UnknownProperty;
            return 0;
        }
        *error = ETrackedPropertyError_TrackedProp_Success;
        return static_cast<uint32_t>(std::strlen(name) + 1);
    }

    bool __stdcall ComponentState(char* name, char* component, VRControllerState_t*, RenderModel_ControllerMode_State_t*,
        RenderModel_ComponentState_t* state)
    {
        if (std::strcmp(component, "tip") != 0 || std::strcmp(name, "mock-right") != 0)
            return false;
        state->mTrackingToComponentLocal = Transform(-0.15f, -0.05f, -0.1f);
        return true;
    }

    EVRRenderModelError __stdcall LoadModel(char*, RenderModel_t** model)
    {
        if (++modelLoads == 1)
            return EVRRenderModelError_VRRenderModelError_Loading;
        static RenderModel_Vertex_t vertices[] = {{{{0, 0, 0}}, {}, {}}, {{{0.04f, 0, 0}}, {}, {}}, {{{0, 0.04f, 0}}, {}, {}}};
        static uint16_t indices[] = {0, 1, 2};
        static RenderModel_t controller{vertices, 3, indices, 1, -1};
        *model = &controller;
        return EVRRenderModelError_VRRenderModelError_None;
    }

    void __stdcall FreeModel(RenderModel_t*) {}

    constexpr auto overlayOk = EVROverlayError_VROverlayError_None;

    EVROverlayError __stdcall CreateOverlay(char*, char*, VROverlayHandle_t* handle)
    {
        panelAlpha = panelPremultiplied = panelBounds = false;
        *handle = 1;
        return overlayOk;
    }
    EVROverlayError __stdcall DestroyOverlay(VROverlayHandle_t) { panelVisible = false; return overlayOk; }
    EVROverlayError __stdcall SetWidth(VROverlayHandle_t, float) { return overlayOk; }
    EVROverlayError __stdcall SetFlag(VROverlayHandle_t, VROverlayFlags flag, bool enabled)
    {
        if (flag == VROverlayFlags_IgnoreTextureAlpha) panelAlpha = !enabled;
        if (flag == VROverlayFlags_IsPremultiplied) panelPremultiplied = enabled;
        if ((flag == VROverlayFlags_IgnoreTextureAlpha && enabled) ||
            (flag == VROverlayFlags_IsPremultiplied && !enabled))
            return EVROverlayError_VROverlayError_InvalidParameter;
        return overlayOk;
    }
    EVROverlayError __stdcall SetBounds(VROverlayHandle_t, VRTextureBounds_t* bounds)
    {
        panelBounds = bounds && bounds->uMin == 0 && bounds->uMax == 1 && bounds->vMin == 1 && bounds->vMax == 0;
        return panelBounds ? overlayOk : EVROverlayError_VROverlayError_InvalidParameter;
    }
    EVROverlayError __stdcall SetTransform(VROverlayHandle_t, ETrackingUniverseOrigin, HmdMatrix34_t* pose)
    {
        lastPanelTransform = *pose;
        return overlayOk;
    }
    bool __stdcall IsOverlayVisible(VROverlayHandle_t) { return panelVisible; }
    EVROverlayError __stdcall ShowOverlay(VROverlayHandle_t) { panelVisible = true; return overlayOk; }
    EVROverlayError __stdcall SetOverlayTexture(VROverlayHandle_t, Texture_t* texture)
    {
        if (!texture || !texture->handle || texture->eType != ETextureType_TextureType_DirectX || HasMode("failPanel") ||
            !panelAlpha || !panelPremultiplied || !panelBounds)
            return EVROverlayError_VROverlayError_InvalidTexture;
        ++panelFrames;
        return overlayOk;
    }

    EVRCompositorError __stdcall WaitForPose(TrackedDevicePose_t* poses, uint32_t count,
        TrackedDevicePose_t*, uint32_t)
    {
        if (!initialized || count != 1)
            return EVRCompositorError_VRCompositorError_RequestFailed;
        eyeMask = 0;
        leftEye = nullptr;
        poses[0].mDeviceToAbsoluteTracking = Transform(0.1f, 0.2f, -0.3f);
        poses[0].bDeviceIsConnected = true;
        poses[0].bPoseIsValid = true;
        return EVRCompositorError_VRCompositorError_None;
    }

    EVRCompositorError __stdcall Submit(EVREye eye, Texture_t* texture, VRTextureBounds_t* bounds,
        EVRSubmitFlags flags)
    {
        if (!initialized || !texture || !texture->handle || texture->eType != ETextureType_TextureType_DirectX ||
            !bounds || bounds->uMin != 0 || bounds->uMax != 1 || bounds->vMin != 1 || bounds->vMax != 0 ||
            flags != EVRSubmitFlags_Submit_Default)
            return EVRCompositorError_VRCompositorError_InvalidTexture;

        const uint32_t mask = 1u << eye;
        if ((eyeMask & mask) != 0)
            return EVRCompositorError_VRCompositorError_AlreadySubmitted;
        if (eye == EVREye_Eye_Left)
            leftEye = texture->handle;
        else if (texture->handle == leftEye || HasMode("failRight"))
            return EVRCompositorError_VRCompositorError_InvalidTexture;

        auto* eyeTexture = static_cast<ID3D11Texture2D*>(texture->handle);
        D3D11_TEXTURE2D_DESC description{};
        eyeTexture->GetDesc(&description);
        if (description.Width == 0 || description.Height == 0 || description.SampleDesc.Count != 1)
            return EVRCompositorError_VRCompositorError_InvalidTexture;
        eyeMask |= mask;
        ++acceptedEyes;
        return EVRCompositorError_VRCompositorError_None;
    }

    VR_IVRSystem_FnTable MakeSystem()
    {
        VR_IVRSystem_FnTable table{};
        table.GetRecommendedRenderTargetSize = TargetSize;
        table.GetProjectionRaw = Projection;
        table.GetEyeToHeadTransform = EyeTransform;
        table.PollNextEvent = NextEvent;
        table.GetDeviceToAbsoluteTrackingPose = AbsolutePose;
        table.IsInputAvailable = IsInputAvailable;
        table.GetTrackedDeviceClass = DeviceClass;
        table.GetInt32TrackedDeviceProperty = AxisType;
        table.GetStringTrackedDeviceProperty = StringProperty;
        table.GetControllerState = ControllerState;
        return table;
    }

    VR_IVRCompositor_FnTable MakeCompositor()
    {
        VR_IVRCompositor_FnTable table{};
        table.SetTrackingSpace = SetTrackingSpace;
        table.WaitGetPoses = WaitForPose;
        table.Submit = Submit;
        table.ClearLastSubmittedFrame = ClearFrame;
        return table;
    }

    auto systemTable = MakeSystem();
    auto compositorTable = MakeCompositor();

    VR_IVROverlay_FnTable MakeOverlay()
    {
        VR_IVROverlay_FnTable table{};
        table.CreateOverlay = CreateOverlay;
        table.DestroyOverlay = DestroyOverlay;
        table.SetOverlayWidthInMeters = SetWidth;
        table.SetOverlayFlag = SetFlag;
        table.SetOverlayTextureBounds = SetBounds;
        table.SetOverlayTransformAbsolute = SetTransform;
        table.IsOverlayVisible = IsOverlayVisible;
        table.ShowOverlay = ShowOverlay;
        table.SetOverlayTexture = SetOverlayTexture;
        return table;
    }

    auto overlayTable = MakeOverlay();

    VR_IVRRenderModels_FnTable MakeRenderModels()
    {
        VR_IVRRenderModels_FnTable table{};
        table.GetComponentState = ComponentState;
        table.LoadRenderModel_Async = LoadModel;
        table.FreeRenderModel = FreeModel;
        return table;
    }

    auto renderModelTable = MakeRenderModels();
}

#define MOCK_EXPORT extern "C" __declspec(dllexport)

MOCK_EXPORT bool VR_IsHmdPresent()
{
    GetEnvironmentVariableA("AL_VR_TEST_MODE", mode, sizeof(mode));
    return !HasMode("noHeadset");
}

MOCK_EXPORT intptr_t VR_InitInternal(EVRInitError* error, EVRApplicationType type)
{
    initialized = type == EVRApplicationType_VRApplication_Scene;
    acceptedEyes = 0;
    connectedControllers = trackedControllers = panelFrames = 0;
    modelLoads = 0;
    controllerPoses[0] = Transform(0.1f, 0.2f, -0.5f);
    controllerPoses[1] = Transform(0.4f, 0.35f, -0.5f);
    if (HasMode("trackedController"))
        connectedControllers = trackedControllers = 1u << 2;
    controllerButtons[0] = controllerButtons[1] = 0;
    controllerTriggers[0] = controllerTriggers[1] = 0;
    panelVisible = false;
    inputAvailable = true;
    *error = initialized ? EVRInitError_VRInitError_None : EVRInitError_VRInitError_Unknown;
    return initialized ? 1 : 0;
}

MOCK_EXPORT void VR_ShutdownInternal()
{
    initialized = false;
}

MOCK_EXPORT intptr_t VR_GetGenericInterface(const char* name, EVRInitError* error)
{
    char systemName[64];
    char compositorName[64];
    char overlayName[64];
    char renderModelName[64];
    std::snprintf(systemName, sizeof(systemName), "FnTable:%s", IVRSystem_Version);
    std::snprintf(compositorName, sizeof(compositorName), "FnTable:%s", IVRCompositor_Version);
    std::snprintf(overlayName, sizeof(overlayName), "FnTable:%s", IVROverlay_Version);
    std::snprintf(renderModelName, sizeof(renderModelName), "FnTable:%s", IVRRenderModels_Version);

    *error = EVRInitError_VRInitError_None;
    if (initialized && std::strcmp(name, systemName) == 0)
        return reinterpret_cast<intptr_t>(&systemTable);
    if (initialized && !HasMode("noCompositor") && std::strcmp(name, compositorName) == 0)
        return reinterpret_cast<intptr_t>(&compositorTable);
    if (initialized && !HasMode("noOverlay") && std::strcmp(name, overlayName) == 0)
        return reinterpret_cast<intptr_t>(&overlayTable);
    if (initialized && std::strcmp(name, renderModelName) == 0)
        return reinterpret_cast<intptr_t>(&renderModelTable);
    *error = EVRInitError_VRInitError_Init_InterfaceNotFound;
    return 0;
}

MOCK_EXPORT uint32_t MockAcceptedEyes()
{
    return acceptedEyes;
}

MOCK_EXPORT void MockControllers(uint32_t connected, uint32_t tracked, bool available)
{
    connectedControllers = connected;
    trackedControllers = tracked;
    inputAvailable = available;
}

MOCK_EXPORT uint32_t MockPanelFrames() { return panelFrames; }

MOCK_EXPORT void MockControllerPose(uint32_t device, HmdMatrix34_t* pose) { controllerPoses[device - 1] = *pose; }
MOCK_EXPORT void MockPanelPose(HmdMatrix34_t* pose) { *pose = lastPanelTransform; }

MOCK_EXPORT void MockControllerButtons(uint32_t device, uint64_t buttons, float trigger)
{
    controllerButtons[device - 1] = buttons;
    controllerTriggers[device - 1] = trigger;
}
