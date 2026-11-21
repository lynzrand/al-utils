# AL Scene Lighting

AL Scene Lighting shades character skin and fabric under the map lights. Each light chooses a toon band, then its cast shadow fades that contribution. On hair, nearby strands have slightly different tilts, so each lamp catches a different part of a lock as the character or camera moves. A softer sheen connects the fine reflections beneath the artist’s painted streak.

## Installing the standalone build

Extract the archive beside `AmanatsuLocation.exe` with BepInEx 6 IL2CPP installed. Start the game. The DLL and its shader bundle belong together in `BepInEx/plugins/AL_NPR/`. When upgrading, replace both files. Press **F7** on a map to compare with stock lighting. Shadow settings are in `BepInEx/config/local.al.npr.cfg`.

Fresh installs request 32-bit depth for the additional-light shadow atlas to reduce stepping where hair casts shadows on skin. Set `HigherShadowDepthPrecision = false` to use the game’s depth format and save atlas memory. Existing installations keep their saved preference.

This build targets the Windows Direct3D player in Amanatsu Location 1.0.4. It contains the reconstructed non-instanced configuration of each material pass. Other keyword permutations, including instancing and alternate shadow layouts, were present in the earlier game-derived bundle and may render differently here.

## Building the bundle

The release build reads the Slang sources and checked-in Unity material layouts. Install CMake, Ninja, Slang, Windows SDK FXC, and Python 3.11 with UnityPy 1.25.4 and lz4 4.4.5. From the repository root:

~~~powershell
$python = (Get-Command python).Source
cmake -S AL_NPR/shaders -B artifacts/npr/standalone-build -G Ninja "-DAL_BUNDLE_PYTHON=$python" "-DAL_GAME_PATH="
cmake --build artifacts/npr/standalone-build --target standalone-bundle
~~~

The output is `artifacts/npr/standalone-build/standalone/al-skin-lighting.unity3d`. The builder serializes five shaders and a bundle catalog, then reopens them and checks the result. Each shader contains the vertex and fragment stages for ExtraPrePass, Forward, ShadowCaster, DepthOnly and DepthNormals. The layouts describe the material properties, render states, mesh channels and Unity buffer bindings used by those stages.

To make the player download, supply a Release build of `AL_NPR.dll` in `AL_NPR/bin/Release/net6.0/`. Rebuilding the managed DLL requires BepInEx and game interop references. With the DLL already built, the packaging command needs only the shader toolchain:

~~~powershell
python tools/package_release.py artifacts/npr/downloads artifacts/npr/standalone-build --lighting-only
~~~

The game-backed `bundle`, `original-bundle` and `release-bundle` targets remain available for reference comparisons. Maintaining the layouts for a different player version is a separate development operation. `standalone/export_layouts.py` reads a reference bundle to refresh the JSON interface data. [Shader targets and feature flags](shaders/README.md) · [How the game draws a material](shaders/MAINTAINING.md)
