# Matched skin and fabric response in AL 1.0.4

The November 19 build keeps the individual-light toon bands. Both skin and fabric use the same compiled band and the same diffuse fill input. The fill combines ambient SH evaluated at the shading normal with the normalized merged-light band. Each material tints it with its own processed pigment. Skin gets 6% of this contribution on top of its palette. Fabric gets 97% of its November 18 contribution. The controls operate in the material shader before its final overlays and the game's postprocessing.

The [HLSL and diagram](../shaders/README.md) explain the light path. [Before/after captures](../../artifacts/npr/material-match-20261119/beach-comparison.jpg), [focused benchmark samples](../../artifacts/npr/material-match-20261119/) and the [full source pack](../../artifacts/npr/material-match-20261119/character-shader-sources.zip) are local generated artifacts.

## Fixed-camera material comparison

In the beach scene, six captures per version covered the authored lights, ambient-only, a dim front light, a stronger front light, backlighting, and the map sun spotlight alone. A 12% skin fill was tried first. It moved cheek luminance by about 10 displayed levels in daylight. The selected 6% fill gave the smaller changes below. Values are median paired pixel differences in fixed interior patches, measured with display RGB luma weights on a 0–255 scale.

| Beach daylight sample | Change |
| --- | ---: |
| Cheek | +5.50 |
| Thigh | +6.35 |
| Forearm beside shirt | +6.07 |
| White printed shirt | −1.78 |
| Dark shorts | −0.72 |
| Chair control | 0.00 |

The final median brightness was 189 on the shirt and 175 on the adjacent forearm. Under the stronger front light the white shirt approached display clipping in both versions. Skin still responds to its authored palette and normal map. The shared fill does not impose a fixed skin-to-fabric screen brightness ratio.

## Shadow reception and stability

In the second room, one camera-facing test spotlight illuminated the two characters while the scene's map lights were switched off. A cube near the emitter used URP Lit's verified ShadowCaster pass and shadows-only rendering. Changing only the blocker's active state lowered median paired display luma by 23 levels on the cheek, 39 on the thigh, 21 on the white shirt and 37 on the dark shorts. The blocked patches also matched the light-off reference within one displayed level in their medians. Removing the blocker recovered the lit image. A preliminary primitive used Unity's error material and had no caster pass. Its results are excluded.

The beach stability test stepped the actual cookieless sun spotlight through nine roll angles from 0 to 0.3 degrees in a frozen scene. The cone direction, color and intensity stayed fixed. Ideal illumination is invariant to this rotation. We selected 1,953,068 pixels where shadow removal brightened the image at both resolutions, and rejected pixels varying by one displayed level or more in either the repeat-at-zero or shadows-off controls. The RMS change between successive steps fell from 2.98 to 2.35 levels. The 95th percentile of the nine-frame brightness range fell from 13.00 to 9.93. This measures sensitivity to shadow-grid orientation across scene receivers. The original motion and camera from the user's screenshot have not been reproduced.

## Shadow cost

The release loader changes per-camera requests before URP packs its additional shadow atlas. Eligible map point and spot lights retain their existing caster flags, masks, strength and filtering. The custom directional list continues to use unit visibility. F7 restored the beach slice from 8192 to 4096, and re-enabling the materials restored 8192 while the asset's configured atlas size remained 4096.

RTX 5070 Ti, D3D12, 2560×1440, render scale 1, 8× MSAA, frozen pose and camera, uncapped. Each measurement used four seconds of warmup and twelve seconds of sampling, in standard/high/high/standard order. Camera, pipeline settings and focus matched at both ends of every retained run. GPU columns are the median of the two run medians, using positive Unity GPU frame times. These are whole-frame timings.

| Scene | Actual additional shadow allocation | Standard GPU | High GPU | Difference |
| --- | --- | ---: | ---: | ---: |
| Beach, morning | One 4096 slice became 8192 | 10.12 ms | 10.52 ms | +0.40 ms |
| Room, morning | 46 slices in both. 45 doubled in side length | 9.39 ms | 9.67 ms | +0.29 ms |
| Room, night | 59 slices in both. 51 doubled in side length | 12.10 ms | 12.29 ms | +0.19 ms |

The beach averaged 76.4–78.5 FPS at standard resolution and 77.3–77.5 FPS at high resolution. Whole-frame FPS overlapped in this view. The night room averaged 81.9–82.0 FPS at standard resolution and 80.7 FPS at high resolution. Its actual packed texture grew from 4096×2048 to 8192×4096. The room used the game's night setting (map manager time zone 3). An earlier unfocused run hid UI by disabling canvas components and generated UI exceptions. Its timings are excluded. The retained benchmarks ran after fresh launches with the canvases active. The room emitted fish-compute initialization errors while loading, before the night timing sequence.

The source build reproduces bundle SHA-256 `eae7b1bf2fc63a742e1d09848a661eb927495643aee9e8f95b757085ed0f1a88`. D3D11 WARP accepted all 768 changed SM5 pixel programs and the D3D12 game loaded the bundle after a restart. Each complete HLSL inspection listing also compiled separately with DXC at Shader Model 6. The translated listings serve inspection, while the three small FXC entry points provide the editable runtime lighting logic.
