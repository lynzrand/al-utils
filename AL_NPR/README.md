# AL Scene Lighting

AL Scene Lighting applies authored map light directions, per-light toon bands and shadow visibility to character materials. The release pairs normal-bent skin and fabric with painted hair reflections and a cubic filter for painted body oil.

Extract the archive beside the game executable and double-click **Prepare AL Lighting.cmd**. The preparation script requires 64-bit Python 3.11, installs its Python dependencies into a private environment under BepInEx/cache, and verifies the rebuilt asset before installing it beside the plugin. It reads the original 1.0.4 game files. Press **F7** in a scene to compare the replacement and original materials. The additional-light shadow depth precision option is in BepInEx/config/local.al.npr.cfg.

## Building the release

Build AL_NPR.csproj in Release against the game's BepInEx 6 IL2CPP installation. For the shader work, install UnityPy 1.25.4 and lz4 4.4.5 in Python 3.11, use a Windows SDK FXC compiler, and have Slang on PATH. Set AL_GAME_PATH to the game folder and add AL_NPR/tools and AL_Performance/tools to PYTHONPATH. From the repository root run the following in PowerShell.

~~~powershell
python AL_NPR/tools/build_default.py
$work = "artifacts/npr/default-build"
python AL_NPR/tools/build_hair_reflection.py "$work/al-skin-lighting.unity3d" "$work/painted.unity3d" --style painted
python AL_NPR/tools/build_face_shadow_trial.py "$work/painted.unity3d" "$work/filtered-face.unity3d"
python AL_NPR/tools/build_fluid_filter.py "$work/filtered-face.unity3d" "$work/release.unity3d"
python AL_NPR/tools/validate_toon_bundle.py "$work/release.unity3d"
python AL_NPR/tools/release_delta.py "$env:AL_GAME_PATH" "$work/lighting.patch" --create-from "$work/release.unity3d"
~~~

The release patch reconstructs and verifies the tested bundle with SHA-256 36ae8431f0abc87cefcf487385c345859d89347c94106e48e6ae997a2493aec1. Edit the [Slang modules](shaders/slang/README.md) for lighting, hair, shadows and body oil. The same functions feed the representative stages and the release builder's SM5 entries. The handwritten HLSL listings are historical references.
