# Map002 shader inspection and patching

`map_shader_bytecode.py` lists compiled shader subprograms in Unity bundles and serialized files. It can match a RenderDoc DXBC export by the full container, executable chunk, or instruction stream and report every pass and keyword combination that references it.

`patch_map_shader.py` creates a workspace copy of one specific map002 bundle with a replacement pixel shader. It checks the source bundle and original DXBC against their stock SHA-256 hashes. The output is validated against the source before it replaces the requested output file. `--restore` copies the verified stock bundle to the output path. Both operations require a workspace output path and leave the source file untouched.

The tools were verified with Python 3.11, UnityPy 1.25.4, and lz4 4.4.5. In a Python environment for this research, install `UnityPy==1.25.4` and `lz4==4.4.5` if needed. Run the commands from the workspace root.

```powershell
python AL_Performance/tools/map_shader_bytecode.py --shader AL/Map --bytecode artifacts/bench/rd-map-stock-shaders/10287-ps.dxbc
python AL_Performance/tools/patch_map_shader.py --replace artifacts/bench/shader-edits/shadow-caster-1.dxbc --output artifacts/static/shader-patch/02-uniform-fast-branch.unity3d
python AL_Performance/tools/patch_map_shader.py --restore --output artifacts/static/shader-patch/02-stock.unity3d
```

Both tools default to `H:\Programs\gal\amanatsu-location\lib\ma\pre\sc\000_08\02.unity3d`. Use `--source` to read a different path. The `artifacts` paths in the examples refer to local benchmark outputs. `--replace` accepts an SM5 DXBC pixel shader with the stock input and output signatures. Keep resource bindings and constant-buffer layouts compatible with the original shader when compiling the replacement.

The patch targets `AL/Map`, path ID 206 in `BuildPlayer-map002.sharedAssets`, ShaderCompilerPlatform 4, subprogram 620. Unity uses that subprogram for the default ShadowCaster and DepthOnly passes. All 31 map materials that use `AL/Map` refer directly to path ID 206. The base game also contains the same DXBC in `globalgamemanagers.assets`, under shader path ID 78 and subprogram 317. The bundle patch targets the map-local object.

The script adjusts the Unity subprogram table and recompresses two inner LZ4 segments. It then reopens the output and compares the shader metadata, all 639 other subprograms, all other objects in `BuildPlayer-map002.sharedAssets`, and the two other embedded files against the source. The game calls Unity's synchronous and asynchronous `LoadFromFile` methods with CRC and offset set to zero for these unencrypted bundles. Live testing is needed to establish driver acceptance, frame output, and performance.

## Map002 no-clip replay experiment

The captured `AL/Map` ShadowCaster and DepthOnly pixel shader returns zero and discards fragments below a material threshold. All 31 local materials serialize `_Dither = 1`, `_Color.a = 1`, and `_Cutoff = 0.5`. The opacity scan resolved their `_MainTex` references through the three `lib/ma/te/c/000_08/{00,01,02}.unity3d` bundles and checked every BC1 and BC3 block in every mip. The 16 BC1 material bindings and four implicit white bindings have alpha 1 throughout. The eleven BC3 bindings have minimum alpha between 243 and 247 out of 255. See [the local opacity report](../../artifacts/static/map002-texture-opacity.txt) and [scanner](../../artifacts/static/map_texture_opacity.py).

With those draw constants and bindings, the Bayer mask is one and sampled alpha exceeds the cutoff by at least 0.45. The alpha-to-coverage calculation's coarse derivative width is at most `2 * (1 - 243/255)`, about 0.094, so the width adjustment also preserves coverage. Eligibility depends on the actual draw having a proven texture and normal filtering, plus those effective values after all material overrides. The static scan establishes the authored map002 inputs. A runtime material or texture override can invalidate the specialization.

Compile `shadow-caster-no-clip.hlsl` with Windows SDK `fxc.exe` and preserve the captured shader signatures with `make_shadow_no_clip.py`.

```powershell
fxc /nologo /T ps_5_0 /E main /O3 /Fo artifacts/static/shadow-caster-no-clip-fxc.dxbc AL_Performance/shaders/shadow-caster-no-clip.hlsl
python AL_Performance/tools/make_shadow_no_clip.py artifacts/bench/rd-map-stock-shaders/10287-ps.dxbc artifacts/static/shadow-caster-no-clip-fxc.dxbc artifacts/static/shadow-caster-no-clip-exact.dxbc
```

The result changes only the executable chunk and container checksum. Its executable emits zero and returns. Use it for RenderDoc replay measurements on event 10287 and compare the raw depth atlas and final output bytes before evaluating timings. Treat the unconditional program as a capture experiment. A live implementation would require proving eligibility for each draw and retaining the original program for draws with other textures or constants.
