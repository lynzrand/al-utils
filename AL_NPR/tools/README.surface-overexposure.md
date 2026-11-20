# Surface overexposure diagnosis, 2026-11-16

## Live candidate result, 2026-11-17

The three derived raster candidates were tested on the same paused map001
camera/pose at 2560x1440, with the black T-shirt and white waist jacket visible.
The previous raster bundle washed the shirt toward pale gray. Aggregate-only
made little difference here. Removing the stock material-color gain/floor
restored a dark shirt; the combined candidate retained that result and was left
active with sun shadow maps. Hair and skin shaders were unchanged.

Completed captures are `artifacts/npr/cloth-20261117/{stock,baseline,aggregate,color,combined}.png`.
Each screenshot finished before the next mode change. A fixed shirt region
(x1220:1460, y780:1010) had mean display RGB of approximately (200,194,195) in
the baseline, (198,192,193) aggregate-only, (107,85,105) color-only and
(106,84,104) combined. These are image measurements, not linear-light energy
or a raw-albedo measurement. The test supports this costume/view; night scenes,
wet transitions and the full clothing set still need validation.

The ready-to-load combined checkpoint is `artifacts/npr/checkpoint-20261117`.
The older checkpoint is preserved. Startup files were not replaced.

The current `--surface-map-lights` trial can wash a black shirt toward white.
The offline shader inspection identifies two interacting mechanisms. No fix was
implemented, and no live game state was changed for this diagnosis.

## Evidence

`patch_surface_map_lighting.py` compresses each additional light's unshadowed
RGB before applying its original shadow attenuation. The color-aware metric is
`(max(RGB) + luminance(RGB)) / 2`, with a knee of 0.5 and an asymptotic metric
ceiling of 1.0. The patch then changes the layer gate to map bit `0x2`. It does
not bound the accumulated result from multiple lights. Its two or six matched
light-read sites are shader loop bodies, not a limit on the number of scene
lights that can contribute.

Skin has a separate aggregate compression stage in `patch_skin_cap_profile.py`
(knee 0.75, ceiling 1.5 for the experimental profiles). Surfaces do not receive
that stage. A per-light cap alone therefore does not bound their total energy.

The retained stock cloth response also deliberately lifts dark material colors
when adding this extra light. An inspected non-instanced representative is
`artifacts/npr/cap-comparison/character-map-trial/131-264.asm`:

```text
1691: add r1.xyz, -r40.xyzx, r41.xyzx
1692: mad r1.xyz, r1.xyzx, (0.5,0.5,0.5), r40.xyzx
...
1715: mad_sat r2.xyz, r2.yzwy, (7,7,7), (0.3,0.3,0.3)
1716: mad r1.xyz, r1.xyzx, r1.wwww, r3.xyzx
1717: mad r0.xzw, r2.xxyz, r1.xxyz, r0.xxzw
```

The first pair mixes the Lambert and wrapped extra-light sums. After the
intervening stock response terms, the final pair multiplies the extra response
by `saturate(7 * processedMaterialColor + 0.3)` and adds it to the existing
shaded RGB. The input is a processed surface color, not a verified raw albedo
texture sample. Even a zero channel gets a multiplier of 0.3; a channel of 0.02
gets 0.44; channels of 0.1 or greater get 1.0. This is an explicit mechanism for
raising black cloth under additional light.

The same multiplier already appears in
`artifacts/npr/cap-comparison/character-baseline/131-264.asm:1687`; it was not
introduced by traversal fusion or the per-light cap. The trial exposes it to
the newly selected map-light set. An instanced representative,
`character-map-trial/131-703.asm`, retains the same `7 * color + 0.3` expression.
These are offline representative variants; the exact currently bound shirt
variant and its pixel values were not captured as part of this diagnosis.

## Next scoped experiment

Keep the accepted main-light response, textures, highlights, authored lights and
shadow work. First compare a surface aggregate bound against the current trial
at a fixed camera and pose; this isolates whether summed map-light energy is the
dominant source of clipping. A second isolated candidate should replace the
additional-light color lift with a response that preserves dark material color.
Identify the correct material-color input before calling that change an albedo
fix, and test black, mid-gray, white and saturated cloth together. Do not patch
hair merely because it shares the current surface-light entry point.

Shadow visibility reduces contributions from occluded lights. It does not remove
the dark-color floor or bound the sum of visible lights, so shadows alone cannot
guarantee that black clothing remains dark. No candidate constants or revised
material response have yet been visually accepted or performance-tested.

## Isolated candidates, 2026-11-17

`patch_cloth_response.py` now implements the two experiments separately. It
accepts only the audited 26-instruction cloth response tail and its two register
layouts. The builder calls it only for `AL/cloth` and `AL/cloth_alpha`; skin and
hair are unchanged.

- `--cloth-aggregate-cap` compresses the Lambert/wrapped additional-light mix
  with the skin color-aware aggregate curve: identity through metric 0.75,
  asymptotic metric ceiling 1.5. A common RGB scale preserves hue. This bounds
  that input, not every subsequent stock lighting term or final display RGB.
- `--cloth-preserve-color` changes the additional-light multiplier from
  `saturate(7 * processedMaterialColor + 0.3)` to
  `saturate(processedMaterialColor)`. It removes the dark-color floor and gain
  while leaving white at one. The input remains processed color, not verified
  raw albedo. Stock main-light and reflection responses remain unchanged.

The saved raster bundle is hash-checked before deriving each candidate:

```powershell
$env:PYTHONPATH = 'H:\Projects\al-povx\artifacts\static\deps'
python AL_NPR/tools/build_cloth_response_trial.py --cloth-aggregate-cap --output artifacts/npr/cloth-20261117/aggregate.unity3d
python AL_NPR/tools/build_cloth_response_trial.py --cloth-preserve-color --output artifacts/npr/cloth-20261117/color.unity3d
python AL_NPR/tools/build_cloth_response_trial.py --cloth-aggregate-cap --cloth-preserve-color --output artifacts/npr/cloth-20261117/combined.unity3d
python AL_NPR/tools/test_cloth_response.py
```

The full stock-assets builder also accepts these switches after the existing
full-character raster options. The derived route avoids rebuilding unchanged
shaders and verifies byte-identical non-clothing objects after serialization.
Use `validate_cloth_response.py baseline candidate --output validation-directory`
with the same experiment switches to check all 640 edited programs, unchanged
non-clothing objects and untouched programs/metadata, then disassemble the
supported surface programs with FXC. The numeric test covers both register
layouts, black/gray/white/saturated processed colors, the aggregate curve and
rejection of changed response operands.

All three derived candidates passed these checks: 640 edited clothing programs,
768 FXC disassemblies including unchanged hair, byte-identical non-clothing
objects and unchanged other programs/metadata. Reports are in the corresponding
`{aggregate,color,combined}-validation` directories beside the candidates. Three
numeric/structure tests and the existing surface-light arithmetic test passed.

| Candidate | SHA256 |
| --- | --- |
| Aggregate | `480b7e48ad84d106cce6fd4aabad4e3a79d01a0631f9a48cf532af11673e74d1` |
| Color | `2bc9776e136958651df3a2a892f3f6cd3fd8d63f588af4dd6644cf533e963d04` |
| Combined | `eff057297a9860aa354b2c5c906e1876c3ed0f4f41345f63dc6e58f721595266` |

Live appearance and performance are separate acceptance steps. These opt-in
candidates do not replace the 2026-11-16 checkpoint or install into the game.
