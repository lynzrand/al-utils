# Validation, 2026-09-19

## 0.3.0 update, 2026-09-20

- Added a separate SceneHotkeys component, independent of POV state.
- Space repeats the existing `Option._buttonAttack` Button's click event.
- D/F operate `GaugeController._togglesLock` through native Toggle.isOn;
  indices use the game's `CharaIndex.Male1` and `Female1` enum values.
- All actions require a loaded, non-ended scene and available controls. Hotkeys
  are suppressed while paused, unfocused, or typing. Repetition resets across
  scene changes and never catches up with a burst after stalled frames.
- Release build passes with zero warnings/errors. All 10 repeat-gate assertions
  pass using `dotnet run --project tests/RepeatGate.Tests.csproj -c Release`.
- Interactive acceptance remains pending: hold/release Space, verify its effect
  matches clicking 激しく, verify D/F toggle the corresponding lock icons and
  behavior, then check with POV off, in text fields, and after changing scenes.

## Verified

- Release build against `H:\Programs\amanatsu-location` succeeded with zero
  warnings and zero errors using .NET SDK 9.0.203 and target framework net6.0.
- Installed DLL hash matches the built DLL. Only the plugin DLL is deployed;
  game, Unity and BepInEx dependencies are not copied from the build output.
- An actual headless game startup loaded `AL PoV X 0.1.0`, registered
  `AL_PovX.PovController` in IL2CPP, completed BepInEx startup, and logged
  `POV render callbacks registered.`
- The plugin generated `BepInEx/config/com.al-povx.camera.cfg` with the expected
  controls and camera settings.
- The first startup exposed an unsupported managed Settings getter during type
  injection. Marking that accessor `HideFromIl2Cpp` removed the warning in the
  final startup check.

Local evidence is in `artifacts/bepinex-smoke-final.log` and
`artifacts/startup-smoke-final.log`. These ignored logs are not part of source
distribution. The original game log was preserved in
`artifacts/bepinex-before-smoke.log` before testing.

The test used `-batchmode -nographics -quit`. The game stayed running despite
`-quit`, so the test-owned processes were stopped after collecting evidence.
No interactive game session was running when testing began. The final test
process has been stopped.

The existing loader/NoPhoneHome combination produces Harmony type-load
warnings also present before this mod was installed. Headless mode additionally
produces graphics/material warnings. No AL_PovX exception or unsupported-type
warning appeared in the final startup check.

## Still requires interactive verification

Startup does not exercise a populated character scene or render with a GPU.
The following behaviors are implemented but not yet visually verified:

1. Enter a scene, press Comma, and verify the view is centered between the
   selected character's eyes. Adjust Camera / Offset Z if needed.
2. Hold right mouse and look to each limit. Hold Z and verify zoom and reduced
   sensitivity; release Z to restore normal POV FOV.
3. Press Period through all active characters, including a one-character scene.
   Confirm the previous character's head is fully restored.
4. Toggle Hide Head and Follow Head Rotation in the config between runs. Check
   hair/accessories, a level horizon in the latter mode, and Home recentering.
5. Enable Lock Cursor, release/relock with Left Control, then exit with Escape.
   Confirm the pointer returns to its previous mode.
6. Exit POV, change scenes/cameras, reload a character, pause, and alt-tab.
   Confirm the rig and camera remain usable and no POV errors enter the log.
7. Check character creation and animated scenes separately. The game retains
   its own movement controls; first-person locomotion/body steering is outside
   this camera port's scope.

If a scene has no tagged main camera, the plugin cannot target it. Visual
alignment, render callback ordering, and compatibility with additional camera
mods remain unverified until these checks are performed.

## 0.2.0 update

Detached position and rotation now default to off for head tracking. Home recaptures the eye pose. Head and hair renderers stay hidden throughout POV and restore their previous forceRenderingOff state on exit/switch. Bone scales are unchanged. Release build passes with zero warnings/errors. Interactive verification of the new behavior is pending; the earlier startup results above refer to 0.1.0.

The 0.2.0 headless startup also passed: BepInEx loaded version 0.2.0, registered PovController, and confirmed render callbacks. Evidence: artifacts/bepinex-0.2.0.log. The test process was stopped. The installed config has Follow Head Position=false, Follow Head Rotation=false, Hide Head=true.


0.3.0 runtime check: the first 20-second attempt produced no new loader log. A longer retry loaded AL PoV X 0.3.0, registered both PovController and SceneHotkeys, and logged Scene hotkeys ready. Evidence: artifacts/bepinex-0.3.0.log and artifacts/startup-0.3.0-retry.log. The test process was stopped; interactive scene behavior is still unverified.


## 0.4.0 update, 2026-09-26

- Corrected the default and installed config to Follow Head Position=true,
  Follow Head Rotation=false. Eye position is sampled each render; position
  offsets use the animated head axes while view rotation remains independent.
- Q/W/E/R during POV enable tracking of the native scene camera target after
  its normal key handling. Uses CameraController._targetTrans when available,
  otherwise CameraPos transformed by BaseTransform. No body-part names or key
  mapping are duplicated. This is limited to loaded normal-camera HScene scenes.
- Home, manual mouse movement with mouse look engaged, POV character switching,
  scene changes and POV exit release tracking. A coincident target does not
  request a zero-vector LookRotation.
- Release build: zero warnings/errors. Existing 10 repeat-gate tests still pass.
- Headless startup loaded 0.4.0, registered both components and render callbacks.
  Evidence: artifacts/bepinex-0.4.0.log. Test process stopped after verification.
- Interactive verification remains pending: animate the POV head and confirm
  position follows without unwanted view rotation; try each Q/W/E/R against the
  normal camera mapping; verify targets keep moving, mouse/Home release tracking,
  and switching character/scene restores normal behavior. The native camera
  pivot fallback and target selection cannot be validated by headless startup.

## 0.5.0 update, 2026-09-29

- Display/project name is AL H Utils (`al-h-utils`); DLL/config identifiers are
  retained for existing installations.
- Mouse-look angles now default to the current animated head's local frame,
  sampled after animation/IK. The installed Follow Head Rotation setting is true.
- SelectedData changes and the posture-change flag queue one reset; it runs
  once NowChangeAnimation clears. The reset clears pitch/yaw and native target
  tracking. Repeated frames and ordinary animation transitions do not reset.
- Releasing target tracking projects the last view direction into the current
  head frame rather than overwriting the head reference with a world rotation.
- All plugin-owned key bindings are documented in docs/key-bindings.md; the POV
  exit key is now configurable too. Q/W/E/R still belong to the game's native
  camera mapping and cannot be independently rebound by this plugin.
- `dotnet build -c Release`: zero warnings/errors.
- `dotnet run --project tests/RepeatGate.Tests.csproj -c Release`: 10 repeat-gate
  checks and 12 pose-change regression checks pass.
- Initial headless launch exited after component registration. The retry loaded
  AL H Utils 0.5.0 and registered render callbacks and scene hotkeys successfully.
  Evidence: artifacts/bepinex-0.5.0-retry.log. The test process was stopped.
- In-game pose-change timing, animated orientation and tracking-release feel
  remain unverified. Test changes between poses after panning and after Q/W/E/R
  tracking; confirm one recenter after transition and no repeated resets.
