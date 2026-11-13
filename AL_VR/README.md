# AL SteamVR

Experimental BepInEx 6 IL2CPP plugin for Amanatsu Location on Windows x64. It renders separate URP views for each eye with SteamVR's predicted headset pose, eye offsets and asymmetric projections. A native callback submits both D3D11 textures to the OpenVR compositor on Unity's graphics thread.

## Build and install

Requires the .NET 6 targeting pack, Visual Studio x64 C++ tools, the Windows SDK, and the game's generated IL2CPP interop assemblies. The build fetches Valve's [OpenVR v2.12.14 C header](https://github.com/ValveSoftware/openvr/tree/v2.12.14/headers) and license. It checks the header hash before compiling.

```powershell
./AL_VR/build.ps1 -GamePath 'H:\Programs\gal\amanatsu-location'
```

Use `-InteropPath` if BepInEx generates the interop assemblies elsewhere. Exit the game and copy the `AL_VR` folder from `AL_VR/artifacts/plugin` into the game's `BepInEx/plugins` folder. Remove that installed folder to uninstall.

Launch the game with `-force-d3d11`. Start SteamVR and verify it sees the headset, then enter a game scene and press **F9**. Press **F10** from a comfortable neutral position to align the headset with the game camera. Press **F9** again to stop the session. Keyboard and mouse still control the game.

The BepInEx config is `com.al-vr.steamvr.cfg`. `Eye Resolution Scale` defaults to `0.75` times SteamVR's recommended width and height. `World Units Per Meter` defaults to `1.0`. Set `OpenVR DLL Path` to an absolute path to SteamVR's 64-bit `openvr_api.dll` if discovery fails.

## One-controller controls

Either hand can operate the game panel. With VR running and the game window focused, look straight ahead and tap the controller's application menu button or click its thumbstick or touchpad to open the panel in front of you. Aim the controller at the panel to move the pointer over the game's live desktop view, including its menus.

| Input | Action |
| --- | --- |
| Application menu or stick/pad click | Show or hide the game panel |
| Hold application menu or stick/pad click | Recenter the headset view and reposition the open panel |
| Trigger | Left click or drag |
| Grip or primary face button | Right click or drag |
| Thumbstick up/down or touch the top/bottom of the pad | Scroll |

With both controllers connected, the most recently pressed panel button selects its controller. The press also performs its normal action. If both controllers register a press in the same frame, the current controller wins. If the active controller disconnects or loses tracking, the other tracked controller takes over automatically. Controller buttons use the [SteamVR legacy input mapping](https://github.com/ValveSoftware/openvr/wiki/Input-Profiles), so physical button names and availability vary by binding. The SteamVR system button opens the dashboard. Keep the game window focused and unobstructed while using the panel. Starting and stopping VR and entering text use the desktop controls.

## Rendering and camera behavior

The game's perspective main camera supplies world position and heading. Headset pitch and roll are relative to gravity and independent of the desktop camera's orbit angle. The desktop camera keeps rendering with its existing settings. PoVX temporarily applies its pose inside callbacks for that camera and restores it at the end of its pass. The eye cameras use the ordinary main-camera pose sampled before those callbacks. For the initial headset test, leave PoVX off so its head-hiding behavior does not affect the stereo views.

The eye cameras copy the main camera's renderer selection, culling mask and volume settings, with individual single-sample targets. They have independent URP histories and skip temporal AA. The optional game panel shows camera-stack overlays and screen-space UI from the desktop frame. Game-specific post effects, mirrors, color and texture orientation still need physical headset validation. Movement and camera interaction follow the game's existing controls through the panel.

The stereo views add two render passes to the desktop frame. Their timing and compositor pacing need to be measured in a representative scene with a connected headset before evaluating comfort.

## Verification

```powershell
./AL_VR/build.ps1 -Smoke
```

The standalone test uses actual D3D11 WARP textures and a mock OpenVR function table. It covers stereo rendering and submission, either controller by itself, controller handoff, SteamVR input focus, panel pointer projection and texture submission, and stale callbacks across panel close and session restart.

An isolated copy of the Unity 6000.0.65f1 game ran under D3D11. The mock runtime accepted 30 stereo pairs at 480 × 360 per eye and at least one captured game panel frame before the plugin closed the session. Physical SteamVR presentation, per-eye image correctness and headset pacing remain unverified.

For a game smoke test, point the process-local `AL_VR_SMOKE_RUNTIME` environment variable at the absolute path of `AL_VR/artifacts/native/MockOpenVr.dll` before launching with `-force-d3d11`. The plugin starts at the first compatible camera, opens the panel after the first stereo frame, and stops after the mock accepts 30 stereo frames and a game panel frame. The BepInEx log records `AL SteamVR smoke passed`. Keep the mock in the build artifacts and clear the launch environment before using a real headset. Verify pointer alignment, clicks, scrolling, and handoff with a physical headset and one controller at a time.

The SteamVR compositor loop follows Valve's [OpenVR compositor overview](https://github.com/ValveSoftware/openvr/wiki/IVRCompositor_Overview). The rendering callback follows Unity's [native rendering extension guidance](https://docs.unity3d.com/6000.0/Documentation/Manual/native-plugin-interface.html).
