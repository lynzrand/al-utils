# AL Scene Lighting

AL Scene Lighting applies authored map light directions, per-light toon bands and shadow visibility to character materials. The release pairs normal-bent skin and fabric with painted hair reflections and a cubic filter for painted body oil.

Extract the archive beside the game executable and double-click **Prepare AL Lighting.cmd**. The preparation script requires 64-bit Python 3.11, installs its Python dependencies into a private environment under BepInEx/cache, and verifies the rebuilt asset before installing it beside the plugin. It reads the original 1.0.4 game files. Press **F7** in a scene to compare the replacement and original materials. The additional-light shadow depth precision option is in BepInEx/config/local.al.npr.cfg.

## Editing the shaders

Edit the Slang material or shared lighting function, then build the `bundle` target to try the compiled stage. The same source tree builds an editable stock reconstruction with `-DSHADING=stock`. Use `original-bundle` for a comparison with the exact game bytecode. Each target writes to the build directory. [Shader targets and feature flags](shaders/README.md) · [How the game draws a material](shaders/MAINTAINING.md)

## Reproducing the release

Build AL_NPR.csproj in Release against the game's BepInEx 6 IL2CPP installation. For the shader work, install UnityPy 1.25.4 and lz4 4.4.5 in Python 3.11, use a Windows SDK FXC compiler, and have Slang on PATH. Set AL_GAME_PATH to the game folder, configure the Slang project with CMake and build its release target.

~~~powershell
cmake -S AL_NPR/shaders -B artifacts/npr/npr -G Ninja
cmake --build artifacts/npr/npr --target release-bundle
$release = "artifacts/npr/npr/variants/release.unity3d"
python AL_NPR/tools/validate_toon_bundle.py $release
python AL_NPR/tools/release_delta.py "$env:AL_GAME_PATH" "artifacts/npr/npr/lighting.patch" --create-from $release
~~~

The release patch reconstructs and verifies the tested bundle with SHA-256 36ae8431f0abc87cefcf487385c345859d89347c94106e48e6ae997a2493aec1. Edit the [Slang modules](shaders/README.md) for lighting, hair, shadows and body oil. The same functions feed the representative stages and the release builder's SM5 entries. The handwritten HLSL listings are historical references.
