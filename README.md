# Amanatsu Location plugins

> Note: This project was made possible with great help from LLM agents. If you are allergic to AI-generated code, please do not use this project.

> What would you do with weapon-grade autism?

Download the Windows x64 archives you want from [Releases](https://github.com/lynzrand/al-h-utils/releases). Install BepInEx 6 IL2CPP, run the game once, then exit and extract each archive beside `AmanatsuLocation.exe`. The archives include their `BepInEx` directory layout. The plugins were built against Amanatsu Location 1.0.4, Unity 6000.0.65f1 and BepInEx 6.0.0-be.788.

## AL H Utils

Nobody has made a POV plugin yet, so guess I'll have to do it. This plugin also provides shortcut
keys for POV and intense mode in H. Inspired by FairBear and 2155X’s
[PoVX](https://github.com/FairBear/AI_PovX).

Press **Comma** to enter or leave POV, **Period** to switch characters and **Home** to recenter. Hold the right mouse button to look around. Bindings are in `BepInEx/config/com.al-povx.camera.cfg`. [All controls](docs/key-bindings.md)

## AL Scene Lighting

Ever wondered why we need a primary "key" light for character shading? Turns out it's not that
necessary! Characters will use the scene lightings with this plugin installed. Might look weird.
Definitely needs more polishing.

Extract the archive, then run **Prepare AL Lighting.cmd** once from the game folder before starting
the game. It uses 64-bit Python 3.11 to build and verify the shader bundle from your 1.0.4 game
files. The lighting loads at startup. Press **F7** in a scene to compare it with the original
lighting.

p.s. we also have the full shader translated into very modular Slang, courtesy of GPT.

## AL SteamVR

Yes, main game VR! Does exactly what it says. Not much testing have been made yet, use with caution.
The only thing I know is that it works.

Start SteamVR with the headset connected, then run **Launch AL VR.bat** from the game folder. **F9** toggles VR, **F10** recenters, and the controller’s application-menu button toggles the panel. [Controller guide](AL_VR/README.md)

## AL Performance

AL Performance exposes internal render scale, MSAA and shadow filtering. Its optional benchmark records frame times and rendering settings so you can compare the same scene across configurations.

Start the game once, then edit `BepInEx/config/com.al-povx.performance.cfg` with the game closed. For a benchmark, set `AL_PERF_CONTROL` to an absolute JSON control-file path before launch and use the supplied sweep script. [Configuration and benchmark examples](AL_Performance/README.md)

## AL Dev REPL

This is a tool for LLM agents to interact with and inspect the game procedurally.
Basically just Runtime Unity Editor's REPL connected to a named pipe.

Install Runtime Unity Editor for its C# compiler. Launch the game with `--al-repl`, then run `BepInEx/plugins/AL_DevRepl/Invoke.ps1 ':ping'` from PowerShell in the game folder. An empty `EnableNextLaunch` file beside the plugin also enables one launch. [Command examples](AL_DevRepl/README.md)

## AL RenderDoc Preloader

For capturing frames from the game for analysis. This optional BepInEx patcher loads RenderDoc early
enough to capture the game’s graphics device. It works with AL Performance’s frame-capture command.

Install x64 RenderDoc, set `AL_PERF_RENDERDOC=1` and `AL_PERF_RENDERDOC_DLL` to the absolute path of its `renderdoc.dll`, then launch the game. [Capture instructions](AL_Performance/RenderDocPreloader/README.md)

## License

Plugin and tooling code, including the PoVX adaptation, uses [GPL-3.0](LICENSE). Project-authored
shader code uses [MPL-2.0](LICENSES/MPL-2.0.txt). Game assets are supplied by the player’s
installation. Valve’s OpenVR notice accompanies the VR package.
