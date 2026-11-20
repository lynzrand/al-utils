# Authored directional raster shadows

The first raster candidate keeps the accepted color-aware character lighting
and restores the stock main-shadow PCF/fade in the skin shader. It applies that
visibility only to the authored directional whose ID occupies URP's main slot.
The other authored directionals remain unshadowed. Existing point/spot shadow
maps and their punctual-light filters remain intact.

Build from the audited stock assets:

```powershell
$env:PYTHONPATH = 'H:\Projects\al-povx\artifacts\static\deps'
C:\Python311\python.exe AL_NPR/tools/build_skin_assets.py --full-light-fusion --shader-map-lights --map-directionals --cap-profile color-aware --surface-map-lights --map-raster-shadows --output artifacts/npr/cap-comparison/character-map-raster.unity3d
```

The bundle uses `MapRasterShadowsEnvironment` skin names. `SkinOverrides` selects
the matching runtime contract automatically. `ALMapLighting[0].y` enables one
main shadow sample; each list color's `.w` marks whether that entry owns it.
All RGB arithmetic and light caps are retained. The ray bundle uses a separate
suffix and retains its existing texture/header contract.

## Session routing and comparison

Load the bundle with `SceneLighting.StartDirect`. The controller selects the
brightest active, nonbaked, positive-intensity directional reaching both the
Map object layer and map rendering-layer bit 2. It excludes Camera/Water-named
directionals, rejects nonfinite or black inputs, and breaks equal-intensity
ties by instance ID. The regular scene scan replaces a route when that light
disappears or another eligible light becomes brightest.

The route sets `RenderSettings.sun` to that light, enables shadows, and includes the
`Chara`/`Chara2` object layers and character rendering-layer bit in its caster
mask. It preserves transforms, color, intensity, bias, normal bias, range and
shadow strength. When the original shadow mode is `None`, it uses `Soft`.

Call `SceneLighting.SetRasterShadows(false)` and `SceneLighting.SetRasterShadows(true)` for a matched
comparison. The main-light route and caster masks stay constant while the
selected light's shadow mode changes. This avoids confusing a main-light slot
change with the cost or appearance of shadows. Existing punctual shadows are
present in both sides of this comparison.

F7 off, controller disable, scene restoration and `SceneLighting.Stop()` dispose
the route and restore the original sun reference, shadow mode, culling mask and
shadow rendering-layer configuration. F7 on selects the current map sun again.
The shadow on/off preference survives that toggle and scene changes. If the old
scene destroyed its sun, disposal does not resurrect its dead Unity reference.

The low-level `RasterShadowMaps(light, true)` helper is still available for
isolated diagnostics. An explicitly constructed helper must be disposed by its
caller; do not overlap one with the controller-owned route. In particular,
dispose a manual route from an older hot-loaded runtime before starting this
version so it captures the real authored state rather than another trial's state.

Promoting a different sun also changes the stock main-light inputs still used
by hair and clothing. Their shader objects are identical to the accepted
surface build, but their main-light highlight can change because the pipeline
supplies a different light. Compare routing alone before attributing that
appearance change to the shadow sample.

## Validation and scope

```powershell
C:\Python311\python.exe AL_NPR/tools/validate_skin_raster_shadows.py artifacts/npr/cap-comparison/character-map-trial.unity3d artifacts/npr/cap-comparison/character-map-raster.unity3d --output artifacts/npr/cap-comparison/raster-validation
```

The validation disassembles all 128 regular Forward+ skin pixel variants,
checks the main-atlas enable and per-entry ownership selector, and checks that
unsupported programs, parameter blobs, resource bindings, shader metadata and
all hair/clothing/support objects are unchanged. The directional patch also
asserts byte-identical preservation of the original punctual loop.

Initial offline build passed these checks and the managed Release build. This
is not evidence of live appearance, stable animation or performance; record
those separately from the actual same-camera run. Supporting several shadowed
directionals requires additional map renders and per-light atlas bindings;
this first implementation does not reinterpret another light's atlas as theirs.
