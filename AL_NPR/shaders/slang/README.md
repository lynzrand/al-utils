# Character shaders in Slang

For a traced game draw, pass and binding tables, material-specific behavior and an editing workflow, see the [maintainer’s guide](MAINTAINING.md).

Edit the material source under `Face`, `Body`, `Hair`, `Cloth` and `ClothAlpha`. Each pass entry declares its Unity interface and selects the shared implementation. The recovered stock and NPR programs use the same material properties, textures, vertex transforms and coverage rules. The lighting and palette modules carry their differences.

| To change | Start here |
| --- | --- |
| Mesh deformation, outline extrusion, transforms | `Geometry/`, `VertexTransforms.slang`, material binding files |
| Dither, cutout and alpha-to-coverage | `Coverage.slang`, material depth and opacity functions |
| Tile and depth-bin traversal, attenuation, shadows | `ForwardPlus.slang`, `PunctualLighting.slang`, `PunctualShadows.slang` |
| Cosine and wrapped diffuse, wet Blinn–Phong highlights, grazing rims | `Reflectance.slang` |
| Authored directionals, toon band and diffuse fill | `MapLighting.slang`, `SceneLighting.slang` |
| Spherical harmonics, sweat and fluid normals | `AmbientProbe.slang`, `MaterialNoise.slang`, `FluidMask.slang` |
| Stock light color, palette exposure and shadow ramps | `ToonPalette.slang`, material palette files |
| Painted hair highlights | `Hair/Color.slang`, `HairLighting.slang` |

For face color, start in `Face/ForwardPS.slang`. Its surface and lighting functions use the same cheek, lip and nose makeup as the outline prepass.
For body color, `Body/Color.slang` composes pigment, highlights and palette work for both color passes.
Both materials share skin lighting, painted fluid, sweat and reflection in `Skin/`. Each material's `Material.slang` declares its Unity property layout.

## Build a material

Install CMake 3.21 or newer, native Ninja and `slangc`. The game's D3D backend uses Shader Model 5 DXBC. Install FXC from the Windows SDK. If a Windows installation has multiple Ninja executables, select a native one with `-DCMAKE_MAKE_PROGRAM=path/to/ninja.exe`. Run these commands from the repository root.

```powershell
cmake -S AL_NPR/shaders/slang -B artifacts/npr/npr -G Ninja
cmake --build artifacts/npr/npr --target BodyForwardPS
cmake --build artifacts/npr/npr

cmake -S AL_NPR/shaders/slang -B artifacts/npr/stock -G Ninja -DSHADING=stock
cmake --build artifacts/npr/stock
```

The compatibility command `python AL_NPR/tools/build_slang_shaders.py OUTPUT` uses the same CMake build. It accepts `--shading stock`, repeatable `--program`, `--target dxil` and `--dxil-profile sm_6_6`. Its historical `--filter-body-oil` switch is opt-in.

Each tree produces 50 named stages covering Forward, ExtraPrePass, ShadowCaster, DepthOnly and DepthNormals for five materials. Entries with the same source, stage and compile definitions share a compiled program. Ninja tracks imported modules. Set `SLANGC` and `FXC` as CMake cache paths to choose compiler binaries. The character DXBC build lowers Slang to intermediate HLSL and uses FXC with `/Od /Gis` for arithmetic comparisons.

### Target features

| Setting | Meaning |
| --- | --- |
| `SHADING=npr` or `stock` | Compile the modified material or the reconstruction of the game's original material. |
| `SHADER_TARGET=dxbc` or `dxil` | Select bytecode format. The Unity bundle target consumes DXBC. |
| `DXIL_PROFILE=sm_6_6` | Select a shader model for DXIL. For example, `sm_6_6+rayquery` also declares ray-query support. Run `slangc -h capability` for supported spellings. |
| `FILTER_BODY_OIL=ON` | Use cubic B-spline reconstruction of the painted body mask in the NPR body Forward stage. Set it to `OFF` to use the original sample. |

```powershell
cmake -S AL_NPR/shaders/slang -B artifacts/npr/sm66 -G Ninja -DSHADER_TARGET=dxil -DDXIL_PROFILE=sm_6_6
cmake --build artifacts/npr/sm66 --target BodyForwardPS
```

DXIL requires a downstream DXC library. CMake looks for the SDK installation on Windows. Set `-DDXC=path/to/dxc` to select another installation. Hardware capabilities describe what instructions the compiler may emit. Unity keywords such as `_LIGHT_LAYERS` choose game permutations with specific bindings and stage interfaces. Each entry in `programs.json` records the keyword set for its recovered permutation and its source DXBC digest. A `stock` override records differences from the NPR trial. The optional `defines` array selects Slang compilation features for a stage and its imports. The NPR hair programs use `HAIR_NPR=1`. [Slang compiler options](https://shader-slang.org/slang/command-line-slangc-reference.html)

## Build a Unity bundle or extract original bytecode

Set `AL_GAME_PATH` to your Amanatsu Location 1.0.4 installation when configuring. These targets require Python 3.11 with UnityPy 1.25.4 and lz4 4.4.5. The stage-only targets work without an installation of the game.

```powershell
$env:AL_GAME_PATH = 'D:/Games/AmanatsuLocation'
cmake -S AL_NPR/shaders/slang -B artifacts/npr/stock -G Ninja -DSHADING=stock
cmake --build artifacts/npr/stock --target stock-reference original-bundle check-bundle
cmake -S AL_NPR/shaders/slang -B artifacts/npr/npr -G Ninja -DSHADING=npr
cmake --build artifacts/npr/npr --target bundle
```

| Target | Output in the build directory |
| --- | --- |
| `stock-reference` | `stock-reference/*.dxbc` contains the 50 exact, hash-checked original game binaries for comparison. |
| `original-bundle` | `original/al-skin-lighting.unity3d` packages all original game permutations with the plugin’s replacement shader names. |
| `check-bundle` | Reopens the editable bundle and verifies each selected stage against its compiled file, and every original program slot and Unity pass table against its base. |
| `bundle` | `al-skin-lighting.unity3d` uses your compiled complete stages for the 50 selected permutations. Additional slots preserve the original bindings and keep the other permutations on their base programs. The stock configuration uses original game assets as its base. NPR uses the release variant bundle. |
| `release-bundle` | `variants/release.unity3d` contains the broad NPR variant build. The linker compiles shared Slang entry functions and binds them at the corresponding sites in the original Unity programs. Changes confined to a complete stage appear in `bundle`. |

The manifest covers one non-instanced permutation per stage. Instancing, DOTS and other keyword layouts require their own full-stage reconstructions before those complete sources can replace them. The release linker retains the surrounding game code for its 1,088 regular Forward+ and hair color programs. The verified release with Slang 2026.14.1 and Windows SDK 10.0.26100.0 has SHA-256 `36ae8431f0abc87cefcf487385c345859d89347c94106e48e6ae997a2493aec1`.

## Fidelity checks

The reference for stock shading is the original game DXBC. For NPR, compare with the corresponding program from the released bundle. A compiler can preserve rendering while changing bytecode.

- D3D11 WARP accepted the 50 reconstructed stages in each configuration. A stream-output comparison matched every vertex output for 128 inputs per stage across all 25 original vertex programs.
- RenderDoc replay of the face Forward and outline draws matched their packed HDR reference pixels. On the body Forward draw, stock and NPR each differed at one of 42,480 affected pixels, by one packed green-channel step. The body outline matched.
- The garment WARP comparisons covered opacity, wet layers, normals and clustered lighting. Across six color programs there were zero coverage mismatches and a maximum absolute color error of 1.8e-7. All garment depth and shadow coverage comparisons matched exactly.
- Hair and cloth draws in the game capture had small packed HDR differences. Identical-bytecode replay controls also varied at a few pixels. These comparisons cover the tested draws. Full-stage frame time and behavior across other scenes remain unmeasured.

## Performance experiments

The optional `performance` target builds the AL_Performance map shadow caster, opaque replay control and twelve-tap depth-normal SSAO reconstruction. Set `PERFORMANCE_FEATURES` to a semicolon-separated list of experiment defines. The map shader supports `FAST_UNIFORM_PATH`, `FAST_OPAQUE_PATH` and `FAST_AUDITED_MAP_TEXTURES`. SSAO supports `SKIP_INVALID_SAMPLE` and `SKIP_ZERO_NUMERATOR`. The opaque control assumes the specific map002 textures and constants described in the [map shader experiment](../../../AL_Performance/tools/README.shader-patch.md).

The map-shadow experiments matched the historical HLSL in 2,349,056 synthetic pixel comparisons across all eight feature combinations. All four SSAO configurations matched the historical HLSL on a 2560 × 1440 captured draw.

The optional DXIL target `visibility-kernels` builds the native interop compute shader at SM 6.0 and the inline ray-query shaders at SM 6.5. `receiver-diagnostics` builds the frozen-camera diagnostic permutations. [Receiver tests](../../tools/README.ray-receiver-reprojection.md)
