# AL SteamVR

Experimental BepInEx 6 IL2CPP plugin for Amanatsu Location on Windows x64. It renders separate URP views for each eye with SteamVR's predicted headset pose, eye offsets and asymmetric projections. A native callback submits both D3D11 textures to the OpenVR compositor on Unity's graphics thread.

## Build and install

Requires the .NET 6 targeting pack, Visual Studio x64 C++ tools, the Windows SDK, and the game's generated IL2CPP interop assemblies. The build fetches Valve's [OpenVR v2.12.14 C header](https://github.com/ValveSoftware/openvr/tree/v2.12.14/headers) and license. It checks the header hash before compiling.

```powershell
./AL_VR/build.ps1 -GamePath 'H:\Programs\gal\amanatsu-location'
```

Use `-InteropPath` if BepInEx generates the interop assemblies elsewhere. Exit the game and copy the `AL_VR` folder from `AL_VR/artifacts/plugin` into the game's `BepInEx/plugins` folder. Remove that installed folder to uninstall.

Copy `Launch AL VR.bat` next to `AmanatsuLocation.exe`. Start SteamVR with the headset connected, then run the batch file. It launches the game with `-force-d3d11 --al-vr`. The game panel opens automatically once a controller is tracked so you can navigate the title screen from the headset. When a compatible 3D camera becomes available, the stereo view appears behind the panel. Use the controller's application-menu button to hide the panel.

With `-force-d3d11` alone, **F9** starts VR manually. **F9** also stops VR or retries a failed connection after SteamVR and the headset are ready. Press **F10** from a comfortable neutral position to recenter the headset and reposition an open panel. Keyboard and mouse still control the game.

The BepInEx config is `com.al-vr.steamvr.cfg`. `Eye Resolution Scale` defaults to `1.0` times SteamVR's recommended width and height (78% more pixels than the old 0.75 default). Existing configs retain their value unless edited. `World Units Per Meter` defaults to `1.0`. Set `OpenVR DLL Path` to an absolute path to SteamVR's 64-bit `openvr_api.dll` if discovery fails.

## One-controller controls

Either hand can operate the game panel. The panel renders the game's screen-space Canvas UI, including menus, dialogs and HUDs, on a transparent background. It excludes the desktop scene camera, so the 3D scene appears only in the stereo view. It stays open until you hide it. Every opening/recenter places the 90 cm-wide panel 55 cm ahead of the active controller, upright along the headset's heading. Aim the active controller's ray at the panel to move the pointer. The plugin draws that controller using the model supplied by SteamVR, or a simple marker if the model is unavailable. Third-party IMGUI windows are not captured by the Canvas panel.

| Input | Action |
| --- | --- |
| Application menu | Show or hide the game panel |
| Hold application menu | Reinitialize/recenter the viewpoint and reposition the open panel |
| Thumbstick/pad click | Toggle grip mode: move panel (blue ray) / move camera (amber ray) |
| Trigger | Left click or drag |
| Primary face button | Right click or drag |
| Grip, in panel mode | Aim at the panel, then hold to move/rotate it; release to leave it there |
| Grip, in camera mode | Hold to pull the viewpoint through the scene and turn it horizontally |
| Thumbstick up/down or touch the top/bottom of the pad | Scroll |

With both controllers connected, the most recently pressed panel button selects its controller. The press also performs its normal action. If both controllers register a press in the same frame, the current controller wins. If the active controller disconnects or loses tracking, the other tracked controller takes over automatically. Controller buttons use the [SteamVR legacy input mapping](https://github.com/ValveSoftware/openvr/wiki/Input-Profiles), so physical button names and availability vary by binding. The SteamVR system button opens the dashboard. Keep the game window focused and unobstructed while using the panel. Starting and stopping VR and entering text use the desktop controls.

Grabs release on focus loss, tracking loss, handoff or mode change. A held grip cannot silently start a new grab. Camera movement preserves a level horizon and resets on recenter or viewpoint reinitialization. The ray remains visible with the panel closed, extending up to five physical metres and stopping at scene colliders. When pointing at the overlay, it ends on the panel instead.

## Rendering and camera behavior

When the player's rig is ready, VR initializes its origin at the eye midpoint (head bone fallback), with the head's horizontal heading. This origin stays fixed during animation. It is sampled again on scene change, after sex-position transitions settle, on game viewpoint/camera selection changes, and on manual recenter. Scenes without a player use the ordinary scene-camera anchor. Headset pitch and roll remain independent of character and desktop-camera animation. Nearby player head/hair meshes are hidden only during the eye passes and restored for desktop rendering; moving the VR camera away makes the head visible again. Leave PoVX disabled when using VR to avoid its separate global head-hiding behavior.

The eye cameras copy the main camera's renderer selection and scene culling mask, with individual single-sample targets. Each eye has its own manually updated volume stack: the game's bloom, tone mapping and colour grading are retained, while lens distortion, Panini projection, motion blur, depth of field and chromatic aberration are excluded. Temporal AA remains disabled. Desktop profiles stay untouched. The headset's asymmetric projections and physical eye offsets remain authoritative. Screen-space camera canvases temporarily switch to overlay mode during eye passes and are restored for desktop rendering.

After the desktop frame, a dedicated UI camera renders screen-space canvases into a transparent target using a temporary layer without scene geometry. Canvas cameras, modes and object layers are restored before the next input update. World-space canvases remain in the 3D scene. Movement and camera interaction follow the game's existing controls through the panel. Physical headset retesting is still required for viewpoint stability, panel orientation and pointer alignment.

The stereo views add two render passes to the desktop frame. Their timing and compositor pacing need to be measured in a representative scene with a connected headset before evaluating comfort.

Eye projection follows Valve's [raw projection formula](https://github.com/ValveSoftware/openvr/wiki/IVRSystem%3A%3AGetProjectionRaw). Its `top` and `bottom` parameter names are counterintuitive: they supply the lower and upper Y tangents to Unity's frustum. Negating and swapping them reflects the vertical optical centre and disagrees with the compositor's lens correction. The D3D11 texture flip is handled separately at submission.

## Verification

```powershell
./AL_VR/build.ps1 -Smoke
```

The standalone test uses actual D3D11 WARP textures and a mock OpenVR function table. It covers stereo submission and vertical texture bounds, either controller by itself, controller handoff, separate grip/mode input, tracked poses when SteamVR owns input, controller tip projection and model loading, transparent panel submission, controller-relative spawning, panel translation/tilt/release and pointer projection on the tilted panel, tracking-loss release, and stale callbacks across close/restart.

The Unity smoke runs at 640 × 480 per eye with the new default. In-game checks cover camera grab translation/yaw/release, pose-transition reset timing, projection rays against Valve's formula, independent eye volume stacks with bloom preserved and distortion/blur excluded, source-profile preservation, transparent UI scene exclusion and canvas restoration. The user confirmed the corrected projection in a physical headset; FPV placement, the new grab controls, post-processing appearance and performance still need physical testing.

For a game smoke test, point the process-local `AL_VR_SMOKE_RUNTIME` environment variable at the absolute path of `AL_VR/artifacts/native/MockOpenVr.dll` and set `AL_VR_TEST_MODE=trackedController`, then run `Launch AL VR.bat`. The plugin starts and opens the panel without physical input, and stops after the mock accepts 30 stereo frames and a game panel frame. The BepInEx log records `AL SteamVR smoke passed`. Keep the mock in the build artifacts and clear the launch environment before using a real headset.

The SteamVR compositor loop follows Valve's [OpenVR compositor overview](https://github.com/ValveSoftware/openvr/wiki/IVRCompositor_Overview). The rendering callback follows Unity's [native rendering extension guidance](https://docs.unity3d.com/6000.0/Documentation/Manual/native-plugin-interface.html).
