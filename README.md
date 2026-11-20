# Amanatsu Location plugins

> What would you do with weapon-grade autism?

Download the Windows x64 archives you want from [Releases](https://github.com/lynzrand/al-h-utils/releases). Install BepInEx 6 IL2CPP, run the game once, then exit and extract each archive beside `AmanatsuLocation.exe`. The archives include their `BepInEx` directory layout. The plugins were built against Amanatsu Location 1.0.4, Unity 6000.0.65f1 and BepInEx 6.0.0-be.788.

## AL H Utils

AL H Utils places the camera at a character’s eyes and follows their animated head. It also adds configurable keys for scene controls. The camera was inspired by FairBear and 2155X’s [PoVX](https://github.com/FairBear/AI_PovX).

Press **Comma** to enter or leave POV, **Period** to switch characters and **Home** to recenter. Hold the right mouse button to look around. Bindings are in `BepInEx/config/com.al-povx.camera.cfg`. [All controls](docs/key-bindings.md)

## AL Scene Lighting

Ever wondering why

Extract the archive, then run **Prepare AL Lighting.cmd** once from the game folder before starting the game. It uses 64-bit Python 3.11 to build and verify the shader bundle from your 1.0.4 game files. The lighting loads at startup. Press **F7** in a scene to compare it with the original lighting.

## AL SteamVR

AL SteamVR renders separate views for each eye and uses the headset pose to place the camera. A controller-operated panel gives access to the game’s menus and HUD. Headset and controller behavior remain experimental.

Start SteamVR with the headset connected, then run **Launch AL VR.bat** from the game folder. **F9** toggles VR, **F10** recenters, and the controller’s application-menu button toggles the panel. [Controller guide](AL_VR/README.md)

## AL Performance

AL Performance exposes internal render scale, MSAA and shadow filtering. Its optional benchmark records frame times and rendering settings so you can compare the same scene across configurations.

Start the game once, then edit `BepInEx/config/com.al-povx.performance.cfg` with the game closed. For a benchmark, set `AL_PERF_CONTROL` to an absolute JSON control-file path before launch and use the supplied sweep script. [Configuration and benchmark examples](AL_Performance/README.md)

## AL Dev REPL

The development REPL evaluates C# on Unity’s main thread through a Windows named pipe restricted to the account running the game. It keeps variables alive between commands so you can inspect a scene or compare material settings interactively.

Install Runtime Unity Editor for its C# compiler. Launch the game with `--al-repl`, then run `BepInEx/plugins/AL_DevRepl/Invoke.ps1 ':ping'` from PowerShell in the game folder. An empty `EnableNextLaunch` file beside the plugin also enables one launch. [Command examples](AL_DevRepl/README.md)

## AL RenderDoc Preloader

This optional BepInEx patcher loads RenderDoc early enough to capture the game’s graphics device. It works with AL Performance’s frame-capture command.

Install x64 RenderDoc, set `AL_PERF_RENDERDOC=1` and `AL_PERF_RENDERDOC_DLL` to the absolute path of its `renderdoc.dll`, then launch the game. [Capture instructions](AL_Performance/RenderDocPreloader/README.md)

## License

Plugin and tooling code, including the PoVX adaptation, uses [GPL-3.0](LICENSE). Project-authored shader code uses [MPL-2.0](LICENSES/MPL-2.0.txt). Game assets are supplied by the player’s installation. Valve’s OpenVR notice accompanies the VR package.
