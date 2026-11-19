#include <Windows.h>
#include <d3d11.h>
#include <d3d11_4.h>
#include <wrl/client.h>
#include <openvr_capi.h>

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <thread>

using Microsoft::WRL::ComPtr;

namespace
{
    struct EyeInfo
    {
        float eyeToHead[12];
        float left, right, top, bottom;
    };

    struct DisplayInfo
    {
        uint32_t width, height;
        EyeInfo left, right;
    };

    struct ControllerInput
    {
        uint32_t device, buttons, clicked;
        float scroll, panelX, panelY;
        uint32_t pointsAtPanel;
        uint32_t hasInput;
        HmdMatrix34_t gripPose, aimPose;
        float rayLength;
    };

    void Check(bool passed, const char* description)
    {
        if (!passed)
        {
            std::fprintf(stderr, "FAIL: %s\n", description);
            std::exit(1);
        }
    }

    template <typename Function>
    Function Load(HMODULE library, const char* symbol)
    {
        auto address = GetProcAddress(library, symbol);
        Check(address != nullptr, symbol);
        Function function;
        static_assert(sizeof(address) == sizeof(function));
        std::memcpy(&function, &address, sizeof(function));
        return function;
    }

    bool Near(float a, float b)
    {
        return std::abs(a - b) < 0.00001f;
    }
}

int main()
{
    auto bridgePath = std::filesystem::absolute(L"AL_VR_Native.dll");
    auto mockPath = std::filesystem::absolute(L"MockOpenVr.dll");
    auto bridge = LoadLibraryW(bridgePath.c_str());
    auto mock = LoadLibraryW(mockPath.c_str());
    Check(bridge && mock, "load bridge and mock runtime");

    auto start = Load<int(*)(const wchar_t*, DisplayInfo*)>(bridge, "AlVrStart");
    auto stop = Load<void(*)()>(bridge, "AlVrStop");
    auto bind = Load<int(*)(ID3D11Resource*, ID3D11Resource*)>(bridge, "AlVrSetTextures");
    auto begin = Load<int(*)(float*)>(bridge, "AlVrBeginFrame");
    auto arm = Load<int(*)()>(bridge, "AlVrArmSubmit");
    auto controller = Load<int(*)(ControllerInput*)>(bridge, "AlVrReadController");
    auto suspend = Load<void(*)()>(bridge, "AlVrSuspendControllerInput");
    auto loadModel = Load<int(*)(uint32_t, RenderModel_t**)>(bridge, "AlVrLoadControllerModel");
    auto freeModel = Load<void(*)(RenderModel_t*)>(bridge, "AlVrFreeControllerModel");
    auto openPanel = Load<int(*)()>(bridge, "AlVrOpenPanel");
    auto dragPanel = Load<int(*)(uint32_t, int)>(bridge, "AlVrDragPanel");
    auto queuePanel = Load<int(*)(ID3D11Resource*)>(bridge, "AlVrQueuePanel");
    auto closePanel = Load<void(*)()>(bridge, "AlVrClosePanel");
    auto submitted = Load<uint64_t(*)()>(bridge, "AlVrSubmittedFrames");
    auto lastError = Load<void(*)(char*, size_t)>(bridge, "AlVrGetLastError");
    using RenderCallback = void(__stdcall*)(int);
    auto render = Load<RenderCallback(*)()>(bridge, "AlVrRenderEvent")();
    auto accepted = Load<uint32_t(*)()>(mock, "MockAcceptedEyes");
    auto setControllers = Load<void(*)(uint32_t, uint32_t, bool)>(mock, "MockControllers");
    auto setButtons = Load<void(*)(uint32_t, uint64_t, float)>(mock, "MockControllerButtons");
    auto setPose = Load<void(*)(uint32_t, HmdMatrix34_t*)>(mock, "MockControllerPose");
    auto panelPose = Load<void(*)(HmdMatrix34_t*)>(mock, "MockPanelPose");
    auto panelFrames = Load<uint32_t(*)()>(mock, "MockPanelFrames");

    DisplayInfo display{};
    char error[256];
    SetEnvironmentVariableA("AL_VR_TEST_MODE", "noHeadset");
    Check(start(mockPath.c_str(), &display) == 0, "reject absent headset");
    lastError(error, sizeof(error));
    Check(std::strstr(error, "connected headset") != nullptr, "identify absent headset");

    SetEnvironmentVariableA("AL_VR_TEST_MODE", "noCompositor");
    Check(start(mockPath.c_str(), &display) == 0, "reject missing compositor");
    lastError(error, sizeof(error));
    Check(std::strstr(error, "IVRCompositor") != nullptr, "identify missing compositor interface");

    SetEnvironmentVariableA("AL_VR_TEST_MODE", "stereo");
    Check(start(mockPath.c_str(), &display) == 1, "start after previous failures");
    Check(display.width == 640 && display.height == 480, "copy recommended resolution");
    Check(Near(display.left.eyeToHead[3], -0.031f) && Near(display.right.eyeToHead[3], 0.031f), "copy eye separation");
    Check(Near(display.left.left, -1.2f) && Near(display.right.right, 1.2f), "copy asymmetric eye frusta");

    ComPtr<ID3D11Device> device;
    Check(SUCCEEDED(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, 0, nullptr, 0,
        D3D11_SDK_VERSION, &device, nullptr, nullptr)), "create D3D11 WARP device");
    D3D11_TEXTURE2D_DESC description{};
    description.Width = display.width;
    description.Height = display.height;
    description.MipLevels = 1;
    description.ArraySize = 1;
    description.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    description.SampleDesc.Count = 1;
    description.Usage = D3D11_USAGE_DEFAULT;
    description.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;

    ComPtr<ID3D11Texture2D> left, right;
    Check(SUCCEEDED(device->CreateTexture2D(&description, nullptr, &left)), "create left eye target");
    Check(SUCCEEDED(device->CreateTexture2D(&description, nullptr, &right)), "create right eye target");
    Check(bind(left.Get(), right.Get()) == 1, "bind D3D11 eye resources");
    ComPtr<ID3D11DeviceContext> context;
    ComPtr<ID3D11Multithread> multithread;
    device->GetImmediateContext(&context);
    Check(SUCCEEDED(context.As(&multithread)) && multithread->GetMultithreadProtected(),
        "protect immediate context across Unity and OpenVR threads");
    float pose[12]{};
    Check(begin(pose) == 1 && Near(pose[3], 0.1f) && Near(pose[7], 0.2f) && Near(pose[11], -0.3f), "copy tracked pose");
    int firstEvent = arm();
    Check(firstEvent != 0 && begin(pose) == 0, "wait for pending submit callback");
    std::thread(render, firstEvent).join();
    Check(submitted() == 1 && accepted() == 2, "submit both eyes from graphics callback thread");
    Check(begin(pose) == 1, "acquire next pose");
    int oldEvent = arm();
    stop();
    Check(!multithread->GetMultithreadProtected(), "restore D3D11 threading state on stop");

    Check(start(mockPath.c_str(), &display) == 1, "restart after a queued submission");
    Check(bind(left.Get(), right.Get()) == 1 && begin(pose) == 1, "bind and pose after restart");
    int newEvent = arm();
    render(oldEvent);
    Check(submitted() == 0 && accepted() == 0, "discard stale render callback across restart");
    render(newEvent);
    Check(submitted() == 1 && accepted() == 2, "submit stereo after restart");

    ControllerInput input{};
    constexpr uint32_t leftHand = 1u << 1, rightHand = 1u << 2, tracker = 1u << 3;
    constexpr uint64_t grip = uint64_t{1} << EVRButtonId_k_EButton_Grip;
    constexpr uint64_t stick = uint64_t{1} << EVRButtonId_k_EButton_Axis3;
    setControllers(tracker, tracker, true);
    Check(controller(&input) == 0, "ignore connected non-controller tracker");
    setControllers(rightHand, rightHand, true);
    setButtons(2, stick, 0.8f);
    Check(controller(&input) == 1 && input.device == 2 && input.buttons == 17 && input.clicked == 0 &&
        Near(input.scroll, -0.5f), "read right controller alone and use its joystick click and scroll");
    setButtons(1, grip, 0);
    setControllers(leftHand | rightHand, leftHand | rightHand, true);
    Check(controller(&input) == 1 && input.device == 2 && input.clicked == 0, "ignore a held grip on a newly connected controller");
    setButtons(1, 0, 0);
    Check(controller(&input) == 1 && input.device == 2, "retain active hand when the other releases its grip");
    setButtons(1, grip, 0);
    Check(controller(&input) == 1 && input.device == 1 && input.clicked == 8, "switch to left hand and deliver the grip press separately from right click");
    setButtons(2, 0, 0.5f);
    Check(controller(&input) == 1 && input.device == 1 && input.clicked == 0, "hold the left hand while the right trigger stays above release threshold");
    setButtons(2, 0, 0.2f);
    Check(controller(&input) == 1 && input.device == 1, "retain active hand after the right trigger releases");
    setButtons(2, 0, 0.7f);
    Check(controller(&input) == 1 && input.device == 2 && input.clicked == 1, "switch to right hand and deliver an analog trigger press");
    setButtons(1, 0, 0);
    Check(controller(&input) == 1 && input.device == 2, "sample released left grip");
    setButtons(1, grip, 0);
    setButtons(2, stick, 0.7f);
    Check(controller(&input) == 1 && input.device == 2 && input.clicked == 16, "prefer active hand and deliver grip-mode toggle when both press in the same frame");
    suspend();
    Check(controller(&input) == 1 && input.device == 2 && input.clicked == 0, "ignore held buttons after desktop focus returns");
    setControllers(leftHand | rightHand, leftHand, true);
    Check(controller(&input) == 1 && input.device == 1 && input.buttons == 8 && input.clicked == 0 && Near(input.scroll, 0.7f),
        "switch to left controller and read its touchpad when the right loses tracking");
    setControllers(leftHand, leftHand, false);
    Check(controller(&input) == 1 && !input.hasInput && input.clicked == 0, "keep tracked pose while SteamVR owns buttons");
    setControllers(leftHand, leftHand, true);
    Check(openPanel() == 1 && controller(&input) == 1 && input.clicked == 0 && !input.pointsAtPanel,
        "open game panel with just the left hand and wait for the first texture");
    int panelEvent = queuePanel(left.Get());
    Check(panelEvent > 0 && queuePanel(left.Get()) == 0, "queue one panel texture at a time");
    std::thread(render, panelEvent).join();
    Check(panelFrames() == 1 && controller(&input) == 1 && input.pointsAtPanel &&
        Near(input.panelX, 0.5f) && Near(input.panelY, 0.5f), "submit panel and project the left-hand ray to its center");
    setControllers(rightHand, rightHand, true);
    Check(controller(&input) == 1 && input.device == 2 && input.pointsAtPanel &&
        Near(input.gripPose.m[0][3], 0.4f) && Near(input.aimPose.m[0][3], 0.25f) &&
        Near(input.panelX, 0.5f + 0.15f / 0.9f) && Near(input.panelY, 0.5f - 0.1f / 0.675f) && Near(input.rayLength, 0.45f),
        "project the right-hand tip ray after left-hand disconnect");
    RenderModel_t* model = nullptr;
    Check(loadModel(input.device, &model) == 0 && !model, "wait for the controller render model");
    Check(loadModel(input.device, &model) == 1 && model && model->unVertexCount == 3, "load the active controller mesh");
    freeModel(model);
    Check(openPanel() == 1, "reopen beside the new active hand");
    HmdMatrix34_t panelBefore{};
    panelPose(&panelBefore);
    Check(Near(panelBefore.m[0][3], 0.4f) && Near(panelBefore.m[1][3], 0.35f) && Near(panelBefore.m[2][3], -1.05f),
        "spawn panel 55 cm ahead of the active controller");
    setControllers(leftHand, leftHand, true);
    Check(controller(&input) == 1 && openPanel() == 1 && dragPanel(1, 1) == 1, "grab panel without snapping");
    constexpr float diagonal = 0.70710678f;
    HmdMatrix34_t moved{{{1, 0, 0, 0.4f}, {0, diagonal, -diagonal, 0.5f}, {0, diagonal, diagonal, -0.5f}}};
    setPose(1, &moved);
    Check(dragPanel(1, 1) == 1 && controller(&input) == 1 && input.pointsAtPanel &&
        Near(input.panelX, 0.5f) && Near(input.panelY, 0.5f) && Near(input.rayLength, 0.55f),
        "move and tilt grabbed panel while preserving its hand-relative pose");
    Check(dragPanel(1, 0) == 0, "release panel");
    moved.m[1][3] += 0.1f * diagonal;
    moved.m[2][3] += 0.1f * diagonal;
    setPose(1, &moved);
    Check(controller(&input) == 1 && input.pointsAtPanel && Near(input.panelY, 0.5f - 0.1f / 0.675f),
        "released tilted panel stays fixed and pointer uses its local vertical axis");
    Check(dragPanel(1, 1) == 1, "grab again");
    setControllers(leftHand, 0, true);
    Check(dragPanel(1, 1) == 0, "tracking loss releases grab");
    setControllers(leftHand, leftHand, true);
    panelEvent = queuePanel(left.Get());
    Check(panelEvent > 0, "queue panel update before close");
    closePanel();
    render(panelEvent);
    Check(panelFrames() == 1 && controller(&input) == 1 && !input.pointsAtPanel, "ignore queued panel event after close");
    setControllers(0, 0, true);
    Check(controller(&input) == 0 && begin(pose) == 1, "continue rendering after all controllers disconnect");
    stop();

    SetEnvironmentVariableA("AL_VR_TEST_MODE", "noOverlay");
    Check(start(mockPath.c_str(), &display) == 1 && openPanel() == -1 && begin(pose) == 1,
        "keep stereo available without an overlay interface");
    stop();

    SetEnvironmentVariableA("AL_VR_TEST_MODE", "failPanel");
    Check(start(mockPath.c_str(), &display) == 1 && openPanel() == 0, "wait for a controller before opening panel");
    setControllers(leftHand, leftHand, true);
    Check(controller(&input) == 1 && openPanel() == 1, "start for panel texture rejection");
    panelEvent = queuePanel(left.Get());
    Check(panelEvent > 0, "queue panel texture for rejection");
    render(panelEvent);
    Check(queuePanel(left.Get()) == -1 && begin(pose) == 1, "report panel rejection and continue stereo");
    stop();

    SetEnvironmentVariableA("AL_VR_TEST_MODE", "failRight");
    Check(start(mockPath.c_str(), &display) == 1, "start for compositor rejection");
    Check(bind(left.Get(), right.Get()) == 1 && begin(pose) == 1, "bind for compositor rejection");
    render(arm());
    Check(submitted() == 0 && accepted() == 1 && begin(pose) == -1, "propagate right-eye rejection");
    lastError(error, sizeof(error));
    Check(std::strstr(error, "right eye") != nullptr, "identify the rejected eye");
    stop();
    render(newEvent);
    Check(begin(pose) == -1, "ignore queued callback after shutdown");
    std::puts("PASS: OpenVR stereo submission, restart, controller handoff, and game panel projection and submission.");
}
