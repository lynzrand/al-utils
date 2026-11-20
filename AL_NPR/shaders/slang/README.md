# Character shaders in Slang

Start with `SceneLighting.slang` for per-light toon bands, `ForwardPlus.slang` for the tile and depth-bin light lists, `ShadowFiltering.slang` for the face shadow tent, and `HairLighting.slang` for the painted reflection. Both hair color passes use `Hair/Color.slang`. The opaque base pass supplies its own coverage ceiling.

The face, body, hair, opaque cloth and cutout cloth directories contain the recovered material programs, including the original palette, textures, overlays, alpha tests and vertex transforms. The stock portions retain temporary registers where the binary lost the source variable names. Constant buffer comments give Unity property names and component offsets.

`programs.json` maps each of the five materials' ExtraPrePass, Forward, ShadowCaster, DepthOnly and DepthNormals vertex and fragment stages to an entry file. Several use identical source. Each record names the selected Unity keywords and the SHA-256 of the source DXBC. The source bundle was the painted hair and filtered face trial, SHA-256 `58d99ee2cf096505de48c8fcc731c0a439533600f389e61ecf76da9857ace5dd`. The manifest covers one non-instanced permutation per stage. Instancing, DOTS and alternative material keyword permutations require their own binding and control-flow checks.

## Building stages

Install CMake 3.21 or newer, native Ninja and `slangc`. For game bytecode, install Windows SDK FXC. From the repository root:

```powershell
cmake -S AL_NPR/shaders/slang -B artifacts/npr/shaders-sm5 -G Ninja
cmake --build artifacts/npr/shaders-sm5
cmake --build artifacts/npr/shaders-sm5 --target BodyForwardPS
```

The default target emits one named DXBC file per manifest record in the build directory. Ninja tracks imported modules and included pass bodies. Entries with identical source and stage share a compile. Set `-DSLANGC=...` or `-DFXC=...` when configuring to select a specific executable. The existing Python command also accepts `--program` and exports the selected files to its output directory.

### Target features and material variants

| Choice | Example | What it controls |
| --- | --- | --- |
| Bytecode and hardware capabilities | `-DSHADER_TARGET=dxil -DDXIL_PROFILE=sm_6_6` | Slang's output target and shader model. The game uses DXBC SM5. |
| Material behavior | `-DFILTER_BODY_OIL=OFF` | Selects the original body mask sample. The CMake default enables the release filter. The compatibility Python command retains its original opt-in switch. |
| Unity keywords | `_FORWARD_PLUS`, `_LIGHT_LAYERS` | The manifest records the permutation each recovered program implements. Further permutations need matching stage logic, Unity resource bindings and signatures. |

Use a separate build tree for each configuration you want to keep:

```powershell
cmake -S AL_NPR/shaders/slang -B artifacts/npr/shaders-sm66 -G Ninja -DSHADER_TARGET=dxil -DDXIL_PROFILE=sm_6_6
cmake --build artifacts/npr/shaders-sm66 --target BodyForwardPS
```

For an optional hardware capability, Slang accepts `-profile <profile>+<capability>`, which you can pass as `DXIL_PROFILE`. Use `slangc -h capability` for the names recognized by your compiler. The target device and graphics API must support the features you use. [Slang compiler options](https://shader-slang.org/slang/command-line-slangc-reference.html)

Slang 2026.14.1 and Windows SDK 10.0.26100.0 were used for the comparison build. The DXBC build preserves integer masks passed through float lanes with FXC's IEEE-strict, unoptimized backend. Enabling FXC optimization removed bound light lists from the resulting shaders.

All 50 original/translated stage pairs matched input and output semantics, component masks, register numbers, component types and constant-buffer slots. D3D11 WARP created every translated shader. In capture `unified-visible-primary_frame14117.rdc`, substituting the original trial DXBC and then the translated DXBC gave identical packed HDR output for face draw 5012 (27,836 covered pixels) and body draw 5621 (42,480). Both substitutions visibly changed the captured baseline. Hair and clothing have compile, interface and driver-creation coverage. Their image parity and the frame time of these comparison builds remain unverified.

## Painted body oil

The massage scene supplies a 512 × 512 bilinear, single-level `_FluidTex` through the renderer's per-material property block. The body shader uses its alpha and two neighboring alpha samples to derive the fluid normal. `FluidMask.slang` reconstructs the painted mask with a cubic B-spline before those differences are taken. Mipmapped textures and single-texel fallbacks use the original sample.

To compile the complete translated body program with this filter, add `--program BodyForwardPS --filter-body-oil` to the build command. To apply just the sampling function to all 64 regular Forward+ body variants in a Unity trial bundle, run

```powershell
python AL_NPR/tools/build_fluid_filter.py artifacts/npr/normal-bend/balanced-face.unity3d artifacts/npr/slang/fluid-trial.unity3d
python AL_NPR/tools/validate_toon_bundle.py artifacts/npr/slang/fluid-trial.unity3d
```
