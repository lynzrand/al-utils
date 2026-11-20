# Skin cap comparison

`build_skin_assets.py --cap-profile` selects `legacy` (default), `gentle-peak`,
or `color-aware`. Experimental profiles require the full-fusion authored map
directional list. They replace the directional, punctual and aggregate rolloff
scales while retaining the original shadow multiplication order. The existing
SH-driven palette selection is deliberately held constant for this experiment.

For metric m above knee k, the new target is
`k + (m-k)/(1+(m-k)/(ceiling-k))`. Below k the scale is one. The RGB triplet
is multiplied by target/m. Per-light k/ceiling are 0.5/1.0; aggregate values
are 0.75/1.5. These are trial values requiring visual calibration.

The gentle profile uses maximum RGB as the metric. The color-aware profile
uses half maximum RGB plus half Rec.709 luminance. It compresses saturated
lights less than the peak-only profile. Its ceiling bounds that blended metric,
not each individual channel. Both profiles retain RGB ratios within each light;
per-light compression can still change the color of the combined lighting.

Build example from the repository root:

```powershell
$env:PYTHONPATH = 'H:\Projects\al-povx\artifacts\static\deps'
python AL_NPR/tools/build_skin_assets.py --skin-only --full-light-fusion --shader-map-lights --map-directionals --cap-profile color-aware --output artifacts/npr/cap-comparison/color-aware.unity3d
python AL_NPR/tools/test_skin_cap_profile.py
```

On 2026-11-16 both bundles built and round-tripped. FXC disassembled all 128
regular skin programs per bundle. The emitted-arithmetic test executes the
patched instructions on neutral, primary-color and warm RGB inputs spanning
zero through 10,000, comparing to an independent scalar reference. It checks
finite outputs, monotonicity along each color ray, no amplification, and identity
below the knee within floating-point tolerance. Neither disassembly nor these
tests establishes successful live shader binding, appearance, or GPU cost.

Artifacts are under `artifacts/npr/cap-comparison`, including `validation.json`
and disassemblies.

## Live comparison, 2026-11-16

After restarting with `--al-repl`, isolated PID 18668 responded on its main
thread. Scene `map002` used D3D12 at 2560x1440. Both bundles loaded successfully
through `SceneLighting.Stop()` followed on a later REPL request by
`SceneLighting.StartDirect(path)`. `StartDirect` alone does not replace an
already-loaded bundle. Each candidate reported 66 overridden materials.

The authored directional list was empty in this scene; enabled map sources
were point and spot lights. Camera-only and water-only directional lights were
present. This comparison therefore exercises punctual lighting, not the new
authored directional traversal or directional visibility.

Scaled animation was frozen with `Time.timeScale=0` for four full-frame captures:
`live-stock.png`, `live-legacy.png`, `live-gentle.png`, `live-color.png`.
`comparison.jpg` shows matching crops. The new profiles restored much of the
shoulder/chest brightness lost by the legacy cap. The face remained pinker than
stock. This supports further isolation of the SH-driven palette response;
it does not establish that the cap alone fixes the original report. Water and
other unscaled effects need not remain pixel-identical while timeScale is zero.

The gentler profile was left active for this session, with animation and the
previous run-in-background setting restored. F7 retains stock comparison.
No on-disk startup bundle was replaced. GPU timings and colored-interior visual
acceptance remain open. The game log contained repeated `CSMain` kernel errors
whose source has not yet been identified, so it is not a clean benchmark run.

Whole-scene ray visibility is a separate pending integration. These bundles
remain skin-only and retain the current directional visibility baseline.

## Full-character baseline

The separate `character-baseline.unity3d` includes the color-aware skin plus
stock-response hair, cloth and cloth_alpha with the existing traversal
optimizations. The asset inventory found `AL/cloth_alpha` at stock path 136,
with 320 regular Forward+ fragment programs and the same built-in dependency
as cloth. The jacket in the live sunset scene uses cloth, while the bikini
uses cloth_alpha. Opacity, blending, depth state and material properties are
preserved. Hair outlines use a separate shader/pass and remain stock.

All 896 regular programs in this baseline passed FXC disassembly. The runtime
build with optional cloth_alpha loading passed with zero warnings/errors.
The currently running older DLL loaded cloth_alpha through its existing
private loader for the test, after `StartDirect` loaded the full bundle.
Status reported 218 overridden materials. Matched frozen captures
`outfit-before.png` and `outfit-baseline.png` showed no obvious appearance
regression in the visible hair, jacket and swimsuit. This is limited to the
current sunset view, not proof of all transparency states or visual equivalence.
Animation and background settings were restored afterward. The full baseline
was left active with F7 stock comparison. It does not yet change the hair/cloth
light selection or artistic response.

## Recovered surface-light trial, 2026-11-16

`--surface-map-lights` now connects the recovered surface patch to the builder.
It requires a full-character shader-map build and either experimental cap
profile. Reproduce the tested candidate with:

```powershell
python AL_NPR/tools/build_skin_assets.py --full-light-fusion --shader-map-lights --map-directionals --cap-profile color-aware --surface-map-lights --output artifacts/npr/cap-comparison/character-map-trial.unity3d
python AL_NPR/tools/test_surface_map_lighting.py
python AL_NPR/tools/validate_surface_map_lighting.py artifacts/npr/cap-comparison/character-baseline.unity3d artifacts/npr/cap-comparison/character-map-trial.unity3d --output artifacts/npr/cap-comparison/character-map-trial
```

The candidate hash is
`efbfe929765758f86c050351658db8bb6a981439bb34fe80274143ce42894d80`.
All 768 modified surface programs passed FXC disassembly. Comparison with the
full-character baseline verified unchanged skin/support objects, other passes,
parameter blobs, resource/signature chunks, and shader metadata other than the
name and packed program storage. Numerical tests exercise regular/instanced
layer gates, both RGB register layouts, both cap profiles and shadow strengths.

The live `map002` nighttime trial bound `AL/hair/MapEnvironment`,
`AL/cloth/MapEnvironment`, and `AL/cloth_alpha/MapEnvironment`. Frozen captures
are `recovery-stock.png`, `recovery-baseline.png`, and `recovery-trial.png` in
the same artifact directory. The trial visibly increases cool illumination
on the jacket and swimsuit and lightens the hair. The jacket becomes much
lighter than baseline. The user chose to use this version while shadow work
continues. It is active for the session with F7 stock comparison; the startup
bundle has not been replaced. Animation/background settings were restored.

This remains a partial shared-light response: additional map-light selection
and the per-light cap are shared, while the surfaces retain their stock
main-light highlight/band and aggregate response. Skin's authored directional
list and ray-visibility binding are not yet used by these surface shaders.
Wet/transparent transitions, other scenes and performance need further tests.
