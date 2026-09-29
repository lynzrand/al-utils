# AL H Utils

Camera and scene-control utilities for **Amanatsu Location**, with POV inspired by
[FairBear/AI_PovX](https://github.com/FairBear/AI_PovX), reference commit
`03d44bcb4a0ffe5497a101913f37279ec4e10bda`.

Targets the installed game's **Unity 6000.0.65f1**, **BepInEx 6.0.0-be.788 IL2CPP**,
and **.NET 6**. This is a new IL2CPP integration; the original AI-Syoujyo DLL cannot
be loaded into this game.

The public project name is `al-h-utils`. For upgrades, the existing DLL name
`AL_PovX.dll` and plugin/config ID are retained to avoid duplicate plugins or
losing existing settings.

## Build and install

Requires a .NET SDK with the .NET 6 targeting pack, and a game installation that
has been run once with BepInEx to generate `BepInEx/interop`.

```powershell
dotnet build -c Release '-p:GamePath=H:\Programs\amanatsu-location'
```

Exit the game, then install using:

```powershell
./tools/install.ps1 -GamePath 'H:\Programs\amanatsu-location'
```

The installer builds, backs up any previous AL_PovX DLL into this project's
`artifacts/backups`, copies only `AL_PovX.dll` into
`BepInEx/plugins/AL_PovX`, and checks the installed SHA-256 hash. Game and loader
assemblies are local build references and are not redistributed. To uninstall,
exit the game and remove `BepInEx/plugins/AL_PovX/AL_PovX.dll`.

## Controls

| Input | Action |
| --- | --- |
| Comma | Toggle POV on/off |
| Period | Cycle active characters, starting with the player when available |
| Q / W / E / R (POV) | Look at and track the regular scene camera's selected body-part target |
| Hold right mouse button | Look around |
| Hold Z | Zoom |
| Home | Stop target tracking and recenter to the head orientation |
| Left Control | Toggle cursor release / mouse-look suspension |
| Escape | Exit POV |
| Hold Space | Repeat the scene's Stronger / 激しく button (every 0.15 seconds) |
| D | Toggle the scene's male gauge lock |
| F | Toggle the scene's female gauge lock |

Scene shortcuts work with POV on or off. They use the game's existing button
and lock toggles, respecting their active/interactable state. They do nothing
outside a loaded scene, while paused, while typing, or while the app is unfocused.
Releasing Space stops repetition. D/F toggle once per press and leave the native
lock state in place until toggled again or reset by the game.
The `Scene Hotkeys` config section contains these keys and the repeat interval.

The pointer stays available by default. Enable `Lock Cursor` for mouse look
without holding a button. Hotkeys are ignored while a Unity or TMP text field
has focus, except the configured POV exit key. Losing application focus exits POV.

Configuration is generated at `BepInEx/config/com.al-povx.camera.cfg` on first
load. It includes key bindings, sensitivity, normal/zoom FOV, near clipping,
eye offsets, head visibility, pitch/yaw limits, and animated head tracking.
Edit the file while the game is closed. By default, `Follow Head Position` and `Follow Head Rotation` are true: the camera follows the eyes and applies mouse-look angles relative to the current animated head orientation. Home recenters. A scene pose change automatically clears look offsets and target tracking once the transition completes; disable `Reset On Pose Change` to opt out. Q/W/E/R enable tracking of the regular scene camera target in supported scenes, using the native key mapping. Home, moving the mouse while mouse look is engaged, switching POV characters, or leaving the scene cancels tracking.

## Integration and scope

The plugin uses `Character.Human.List`, prioritizes `Manager.Game`'s player,
and follows the midpoint of `Human.Face.eyeLookCtrl`'s eye bones. It falls back
to the head bone if eye transforms are unavailable. Offsets are in world units
along the animated head axes; these positional offsets follow the head independently of the viewing direction.

The Unity render-pipeline begin/end camera callbacks apply the POV to
`Camera.main` and restore position, rotation, FOV and near clip after rendering. Head and hair meshes remain hidden throughout POV, including other cameras and mirrors. Their previous renderer visibility is restored on exit or character switch; bone scale is never changed. The plugin exits when its character is unloaded/reloaded or the
main camera changes; press Comma to enter POV again in the new scene.

This implements the camera portion of PoVX: eye tracking, character cycling,
look, zoom, offsets and head hiding. AI-Syoujyo-specific body steering,
head-before-body rotation, merchant visibility and housing logic are not ported.
Movement remains controlled by Amanatsu Location. Other mods that override the
same camera during render callbacks may conflict. Scenes using an untagged
camera instead of `Camera.main` are not supported.

## Verification

Run `dotnet run --project tests/RepeatGate.Tests.csproj -c Release` for the
repeat timing and pose-transition reset checks.

See [the validation notes](docs/validation.md) for build/runtime evidence and
the in-game acceptance checklist. A successful build alone does not establish
that eye alignment, animation or render ordering is correct in every scene.

## License

GPL-3.0; see [LICENSE](LICENSE). The original PoVX project is by FairBear and
2155X. This adaptation retains its licensing and credits; proprietary game
assemblies and assets are not included.




See [key-binding configuration](docs/key-bindings.md) for all settings and an editable example.
