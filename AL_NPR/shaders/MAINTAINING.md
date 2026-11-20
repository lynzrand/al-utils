# Maintaining the AL shaders

## Follow one draw through the face Forward pass

This example follows `AL/skin_head` in Amanatsu Location 1.0.4. Pass names, keywords, register assignments and texture property names come from the shipped Unity asset and its Shader Model 5 DXBC. Draw events and pixel comparisons come from a D3D12 capture. Names such as `FaceRim` and the skin response’s `bounce()` are our interpretation of the compiled math. The asset lists `AmplifyShaderEditor.MaterialInspector` as its custom editor. Recovering the original graph and the author’s variable names would require the authoring project.

### Find the program Unity selects

Open path ID 76 in `AmanatsuLocation_Data/globalgamemanagers.assets`. Subshader 0 contains ExtraPrePass, Forward, ShadowCaster, DepthOnly and DepthNormals in that order. Pass 1 is named `Forward` and carries the `LightMode=UniversalForward` tag. Its serialized state enables back-face culling and depth writes, sets source/destination blending to One/Zero, and disables alpha-to-mask. Although the material-type tag says `Unlit`, the fragment program reads URP lights and shadow maps and shades the face itself.

For the Forward+ variant covered by this project, resolve each stage's keyword indices through `m_KeywordNames` and match the complete set. On this asset both stages select player subprogram group 3, entry 4. The vertex and fragment entries have different keyword sets and different code and parameter records.

| Stage | Keywords | Code blob | Parameter blob |
|---|---|---:|---:|
| Vertex | `_MAIN_LIGHT_SHADOWS_CASCADE`, `_FORWARD_PLUS`, `_LIGHT_LAYERS` | 19 | 12 |
| Fragment | Same three plus `_ADDITIONAL_LIGHT_SHADOWS` | 91 | 43 |

`m_PlayerSubPrograms[3][4].m_BlobIndex` identifies the stage code. The parallel `m_ParameterBlobIndices[3][4]` entry supplies its variant-specific bindings. Each blob index resolves to an offset, size and segment in the decompressed Unity shader data. The code record wraps a DXBC container. The original fragment container's SHA-256 begins `65bc9b7a730b6c94` (`FaceForwardPS.stock.sha256` in the manifest). The packager appends replacement code and redirects the matching stage reference so another permutation that shares the original blob can still use it. The selected parameter record stays paired with the replacement. [Program manifest](programs.json) · [Shader data reader](../tools/build_skin_assets.py) · [Variant selection and packaging](../tools/slang_bundle.py)

### Trace a property from the asset to a pixel

Read the stage's `m_CommonParameters` together with the selected parameter blob. For example, the common fragment table names `_Cheek_color` as a four-component vector in `UnityPerMaterial` at byte 176. Parameter blob 43 binds that buffer at pixel slot `b6`. Dividing 176 by the 16-byte constant-register size gives `c11`, the `packoffset` used in Slang. The same calculation maps the scalar `_Dither` at byte 540 to `c33.w`. The cheek texture binds at `t6` with sampler `s8`. In `sampleFaceMakeup`, the red channel supplies pigment coverage and the blue channel supplies a separately positioned highlight. [Face material layout](Materials/Face/Material.slang) · [Textures and samplers](Materials/Face/Bindings.slang) · [Makeup sampling](Materials/Face/Makeup.slang)

| Forward fragment slot | Data read by this draw |
|---|---|
| `b0` globals | Screen dimensions at `c3`, main light position/color at `c5–6`, Forward+ parameters at `c15–17`, camera position at `c25`, view columns at `c70–72` |
| `b1` additional lights | 256-entry arrays of positions, colors, attenuation, spot directions and layer masks starting at `c0`, `c256`, `c512`, `c768` and `c1280` |
| `b2`, `b3` | Forward+ depth-bin and screen-tile bit masks. Preserve their `uint4` declarations so dynamic indexing preserves every packed bit. |
| `b4` UnityPerDraw | Object transforms, renderer layer bits at `c10.x`, probe HDR decode at `c15` and spherical harmonic coefficients at `c25–31` |
| `b5` LightShadows | Main cascade transforms and spheres, main strength at `c27`, additional-light fade at `c31`, per-light shadow properties from `c33` and shadow matrices from `c289` |
| `b6` UnityPerMaterial | Artist controls, colors and UV transforms at the original byte offsets |
| `b10` ALMapLighting (NPR) | The plugin supplies a count at `c0.x`, then up to 32 world-space direction/color pairs at `c1–64`. |

The shader binds fluid and detail textures at `t0–4`, lip/cheek/head/line/spot/nose textures at `t5–10`, the palette ramp and expression map at `t11–12`, the reflection cube at `t13/s0`, and main/additional shadow atlases at `t14–15` with comparison sampler `s1`. Sampler and texture slot numbers are independent. [Frame constants](Materials/Skin/Frame.slang) · [Cluster masks](Lighting/ForwardPlus.slang) · [Shadow layout](Lighting/PunctualShadows.slang) · [Map-light producer](../MapDirectional.cs)

### Follow the vertex into the fragment shader

The vertex inputs arrive in register order as position, normal, tangent, UV1, UV2, UV0, UV3. In this stage `b1` is UnityPerDraw. The vertex program transforms the position to world space and then clip space using the view-projection columns at `b0:c82–85`. It transforms the normal with the inverse transpose, normalizes the transformed tangent, and multiplies the tangent sign by the object's transform sign. [Forward vertex entry](Materials/Face/Passes/ForwardVS.slang) · [Transform math](Geometry/VertexTransforms.slang)

| VS output | Fragment input and use |
|---|---|
| `o0 SV_POSITION` | Clip position on VS output. Rasterization supplies pixel coordinates for dithering and tile lookup. |
| `o1–3 TEXCOORD0–2` | World position, world normal, and world tangent with handedness. The fragment reconstructs the tangent frame for perturbed normals. |
| `o4–5 TEXCOORD3–4` | Zero-filled slots retained in the stage signature. |
| `o6 TEXCOORD5` | UV0 in `xy` for head pigment, expression, detail and fluid. UV1 in `zw` for cheeks. |
| `o7 TEXCOORD6` | UV2 in `xy` for the nose. UV3 in `zw` for lips and lip lines. |
| `o8 TEXCOORD7`, `o9 NORMAL0`, `o10 TEXCOORD8` | Object-space main light, mesh normal and mesh position, used by rim and surface effects. |

The rasterizer also supplies `SV_IsFrontFace`. Keep register order, component types and masks when editing this interface. An equivalent list of semantic names can still compile to a different D3D11 signature.

### Follow the fragment to the HDR target

1. **Coverage.** Both targets enter the same `main`. A screen-aligned 4×4 Bayer threshold tests `_Dither`, accounting for the render-target scale and projection sign. The resulting opacity is zero or one. `clipCoverage` uses a cutoff of 0.5 and applies a coarse-derivative adjustment when Unity reports alpha-to-mask availability. [Face fragment entry](Materials/Face/Passes/ForwardPS.slang) · [Coverage](Surface/Coverage.slang)
2. **Material.** `sampleFaceSurface` combines painted head pigment, expression, cheeks, lips and nose with detail masks and the fluid layer. It builds normals in the interpolated tangent frame. Wetness drives the reflection-probe sample. These operations run in both stock and NPR. [Face surface](Materials/Face/ForwardSurface.slang) · [Detail sampling](Materials/Face/Surface.slang) · [Shared skin effects](Materials/Skin/SurfaceMath.slang)
3. **Lighting.** `faceKey` prepares light directions and shadow weights. `evaluateSkinLights` accumulates the selected lights. `faceRim`, `faceGloss` and `facePalette` combine them with the artist's detail masks, the blue channel of `_Lamp`, and probe lighting. `faceSubsurface` adds the backlit tint. The two targets share these face functions. The stock and NPR manifest configurations compile this same entry with different `SKIN_NPR` values. [Forward entry](Materials/Face/Passes/ForwardPS.slang) · [Face lighting](Materials/Face/ForwardLighting.slang) · [Light traversal](Materials/Skin/Lighting.slang) · [Stock and NPR responses](Materials/Skin/LightResponse.slang)
4. **Output.** The shader bounds the base term with `clamp(lit * 0.98, 0, 0.98)`. Gloss and rim restore highlights above that range, then the shader adds pigment-weighted bounce and applies the NPR fill. Nose and face lines are the last color blends. `SV_Target0.a` receives the coverage opacity when alpha-to-mask is available and one otherwise. The captured color attachment uses `R11G11B10_FLOAT` and stores the three HDR color components. [Final composition](Materials/Face/Passes/ForwardPS.slang)

| Decision | Stock | NPR |
|---|---|---|
| Key light | Uses Unity's main direction and RGB, with the main cascade shadow sample. | Derives neutral key intensity and direction from the object's spherical harmonics. Key visibility is one. |
| Direct lights | Visits Unity's additional directional prefix, then the Forward+ lights in the pixel's tile and depth bin. Uses the renderer's layer bits. | Visits the plugin's map directionals, then the same cluster lookup for local lights filtered to map layer bit `2`. |
| Response | Accumulates cosine and wrapped diffuse. Their mean contributes colored bounce. | Compresses each incident color and selects its toon band using a bent normal. For a local face light the band is chosen before applying filtered shadow visibility. The combined bands get a second compression and drive palette weight, bounce and pigment-colored fill. |

The capture used for the forward comparison is `artifacts/npr/4k/unified-visible-primary_frame14117.rdc`, event 5012, a 25,104-index draw. Replaying the extracted game program and compiled stock Slang on that draw's inputs produced identical target pixels. Comparing the NPR reference with the compiled NPR program also matched. These substitutions test one draw and its bound inputs. The asset's keyword and parameter tables establish which original variant the build replaces.

## The other character materials

The original global shader assets give the following defaults. Materials can override render queues, and the cutout cloth material also supplies render-state properties. The event IDs are observed draws in `unified-visible-primary_frame14117.rdc`. They identify replay points for this frame.

| Game shader and path ID | Queue tag | Color passes in the capture | Where to follow the material |
| --- | --- | --- | --- |
| `AL/skin_head` (76) | Geometry | ExtraPrePass 4987, Forward 5012 | The face trace above |
| `AL/skin_body` (146) | AlphaTest | ExtraPrePass 5593, Forward 5621 | Body surface construction samples the body pigment, anatomical masks and wet layers. The shared skin lighting feeds the body palette and outline. [Body color](Materials/Body/Color.slang) |
| `AL/cloth` (131) | AlphaTest | ExtraPrePass 5526, Forward 5549 | The garment pipeline combines dye regions, matcaps, metallic and wet highlights before applying opacity. [Cloth color](Materials/Cloth/Passes/ColorPass.slang) |
| `AL/hair` (129) | Transparent | ExtraPrePass 5711, Forward 5728 | The stock base pass has a smaller binding layout. NPR pairs the two color passes and adds a painted specular streak per eligible light. [Hair color](Materials/Hair/Color.slang) · [Pass pairing](../tools/build_hair_reflection.py) |
| `AL/cloth_alpha` (136) | Transparent | ExtraPrePass 7056 → Forward 7075, then 7094 → 7113 | Shares the cloth color path and supplies cutout-specific property slots, samplers and opacity. [Cutout material properties](Materials/ClothAlpha/MaterialProperties.slang) |

A material’s shader pointer can refer to a local copy in a character bundle. In `lib/chara/head/head_00.unity3d`, renderer `cf_O_face` uses material `m_al_head_00`, which points to the local `AL/skin_head`. Its parsed shader and compressed programs match global path ID 76. In the sampled top clothing bundle `co_top_000_00.unity3d`, `o_cf_top_chinadress_b` uses `m_cf_top_chinadress` and a local `AL/cloth_alpha` at material queue 2475. The local garment copies retain 192 of the global 480 Forward fragment keyword rows. Each retained row has the same instructions as its global counterpart. These counts apply to this bundle. Shader names, local path IDs, material queues and serialized variant inventories answer different questions.

All five original shaders declare the same five named passes in their serialized SubShader. The two alternating cloth-alpha draw groups show how the game can visit the same passes again within one camera frame. `ExtraPrePass` writes color. Use a capture to establish the ordering for a particular frame. Face, body and both cloth shaders specify front-face culling there, while hair specifies back-face culling. Alongside the two hair draws above the game also uses the separate `AL/hair_outline` shader (path ID 134). Its color draw at 5570 falls outside this replacement set.

This capture shows a 4096 × 4096 shadow target beginning at event 2236, a 1600 × 900 normals/depth target pair from 3039, and the 8× MSAA scene-color target from 4482. DepthNormals matches occur at 3210 (face), 3498 (body), 3536 (hair), 3462 (cloth) and 4397 (cloth alpha). A matching fragment shader can identify more than one pass. When DepthOnly and ShadowCaster share bytecode, inspect the active render targets, vertex shader and draw state before assigning an event to either pass.

## How the mod supplies lighting

AL_NPR loads `al-skin-lighting.unity3d` beside the plugin DLL and looks up replacement shaders using catalog names such as `assets/al_npr/skin_head.shader`. It swaps the shader on the existing material, saves the old shader for restoration, and reapplies that material’s keywords and render queue. Material properties and renderer-specific property blocks still belong to the game. The replacement shader’s name tells the plugin which lighting inputs the bundle requires. [Plugin startup](../Plugin.cs) · [Material swaps](../SkinOverrides.cs)

For NPR’s authored directionals, the plugin builds a per-camera constant buffer. The first register stores a count, followed by direction and color registers for up to 32 lights. The Slang struct describes that binary layout at `b10`. The renderer still provides the Forward+ grid and additional-light buffers. Skin and cloth can replace the directional prefix with this map list while retaining local light traversal. Hair uses its map-directional reflection loop alongside Unity lighting. [MapDirectional.cs](../MapDirectional.cs) · [MapLighting.slang](Lighting/MapLighting.slang) · [Hair light traversal](Materials/Hair/Lights.slang)

## Working with Slang modules

The stage entry imports the material operations it uses. `Materials.Face.Bindings` declares texture, sampler and interpolator assignments. `Materials.Face.Material` owns the artist-property layout. For a new material operation, import its owning module and pass a typed surface, palette, or light value. Give the function direct access to one binding module when that module owns its resource contract. This keeps Unity register knowledge at the boundary. [Face entry](Materials/Face/Passes/ForwardPS.slang) · [Face bindings](Materials/Face/Bindings.slang)

The material selects a concrete type before the shader is compiled. Each interface names the operation that its caller needs. To change how a skin light contributes to the palette, edit the response. To change which lights the draw visits, edit the traversal. [Slang interfaces and generics](https://docs.shader-slang.org/en/stable/external/slang/docs/user-guide/06-interfaces-generics.html)

| Interface | Implementations and callers |
| --- | --- |
| [`ISkinLightResponse`](Materials/Skin/LightResponse.slang) | `StockSkinResponse` accumulates diffuse and wrapped light. `ToonSkinResponse` accumulates compressed bands. Both face and body use the selected response when composing the palette, bounce and fill. |
| [`IHairLightResponse`](Materials/Hair/LightResponse.slang) | `StockHairResponse` keeps the painted base stripe. `ToonHairResponse` retains 26% of its gain and projects the painted highlight for authored directionals and clustered lights. Both share the Forward+ traversal. |
| [`IFabricOpacity`](Materials/Cloth/FabricOpacity.slang) | Opaque fabric keeps the dry outline. Cutout fabric also accounts for dye brightness and sheerness. Color, depth and shadow passes pick up the same rule from the material’s `Fabric` alias. |
| [`IFluidFilter`](Materials/Skin/FluidLayer.slang) | `FluidMap<Filter>` uses the chosen filter for the paint sample and both neighboring height samples. Stock skin uses hardware linear filtering. NPR body Forward can specialize the same operation with the cubic B-spline filter. |

For stage-dependent ABI choices, use the manifest's `defines` array. For example, the stock hair base needs its material at `b5`, while hair Forward has shadows at `b5` and the material at `b6`. CMake passes the selected defines to Slang so imported modules see the same layout. The compile key includes the source, stage and defines. [Stage manifest](programs.json) · [Hair bindings](Materials/Hair/Bindings.slang)

## Making a change

- **Change a reflectance equation** in `Lighting/Reflectance.slang` and check each caller. Cosine and wrapped diffuse consume the signed world-space normal/light dot. Wet hair and cloth use the same Blinn–Phong shape. Pigment, strength, visibility, and the position of a clamp in the palette remain material decisions. [Reflectance](Lighting/Reflectance.slang) · [Stock palette](Lighting/ToonPalette.slang)
- **Change light-list traversal** in `Lighting/ForwardPlus.slang`. `ForwardPlusGrid` unpacks Unity’s camera constants. Its cluster iterator owns the mutable tile/bin masks and returns the absolute index into the additional-light arrays. Keep the buffers typed as 32-bit integers. Converting a dynamically selected float lane first caused FXC to flush valid mask bits. [ForwardPlus](Lighting/ForwardPlus.slang)
- **Change one material’s appearance** in its surface, palette or composition file. Start with that material’s Forward stage in each configuration. If opacity or vertex displacement changes, also compare its outline, depth, normal and shadow passes. A matching color draw can still hide an incorrect shadow silhouette.
- **Add a Unity permutation** by identifying the actual pass, exact vertex and fragment keyword sets, parameter tables, register layout and varyings in the original asset. Hardware capability flags control Slang compilation. They cannot supply a missing Unity binding. [Stage manifest](programs.json) · [Build configurations](README.md#target-features)
- **Test the intended deliverable.** Use `check-bundle` for full-stage edits, `stock-reference` for exact original DXBC and `original-bundle` for a loadable original-bytecode control. The broad `release-bundle` consumes the shared Slang entry functions through its variant linker. For an image comparison, record the pass, event, covered-pixel count and error against the correct reference. Require nonzero coverage when reporting draw parity. [Build and verification targets](README.md#build-a-unity-bundle-or-extract-original-bytecode)
