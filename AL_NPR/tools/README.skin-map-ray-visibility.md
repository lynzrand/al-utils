# Experimental skin directional visibility input

Build with `build_skin_assets.py --skin-only --full-light-fusion
--shader-map-lights --map-directionals --map-ray-visibility --output <workspace path>`.
The flag is opt-in and requires the authored directional-list path. Legacy bundles
and the list-only default remain separate. No runtime installation is performed.

The CPU-built candidate is
`artifacts/npr/direct-skin/al-skin-map-ray-visibility.unity3d`, serialized bundle
name `al-skin-map-ray-visibility`, shader markers:

- `AL/skin_head/MapRayVisibilityEnvironment`
- `AL/skin_body/MapRayVisibilityEnvironment`

## Runtime contract

`ALMapLighting` remains 65 float4 at b10 (1040 bytes). Header `[0]` contains raw
uint32 bits: x directional count (clamped to 32), y visibility enabled (0 disables),
z texture width, w texture height. Do not numerically convert these integers to
float. Existing direction/color pairs and their ordering remain unchanged.

Bind `_ALDirectionalVisibility` as a non-MSAA Texture2D<uint2>, format
R32G32_UInt, with mip zero at full receiver/render-target pixel coordinates.
It reuses the removed main-shadow resource slot: head t14, body t13. No sampler
is used. Only the 64 regular Forward+ fragment variants per skin shader have
their binary texture binding renamed; DOTS and other passes remain untouched.

- X: occluded directional bits. Bit i=1 skips authored list entry i, including
  all three existing lighting responses. Bit i=0 retains it exactly.
- Y: raw uint32 bit pattern of the matching receiver's SV_Position.z.

The shader obtains SV_Position from the verified DXBC input signature, extends
its used/declaration mask to xyz, truncates SV_Position.xy to pixel indices and
loads the texture once, outside the light loop. Out-of-bounds coordinates or a
disabled gate leave the occlusion mask zero. The loaded depth must lie within
the fragment's half-pixel depth footprint:
`abs(sampleDepth - fragmentDepth) <= .5 * (abs(ddx(z)) + abs(ddy(z))) + z * 2^-20`.
The original exact-bit check rejected almost all sloped skin pixels in the live
MSAA scene. The bounded check admits resolved samples from the same plane;
overlapping surfaces within that interval remain ambiguous. It is not a
receiver-identity test. `test_ray_depth_match.py` exercises the emitted bound.

The producer must use the same camera, depth convention, pixel orientation,
resolution and authored-light ordering. Invalid texels can use X=0 and
Y=0xffffffff. Gate off until a correctly typed texture and coherent current-frame
data are bound. Matching depth does not establish frame freshness or light
identity: those are runtime responsibilities. A same-depth stale frame must not
be reused on the strength of this check alone.

No skin colors, SH shaping, punctual PCF, palette or rolloff formulas change.
Zero accepted occlusion bits execute the baseline directional arithmetic;
set bits omit the corresponding directional contribution. Shadows are currently
binary; fractional softness and shadow strength are not encoded by this input.

## Evidence boundary

All 128 regular head/body programs built and passed offline FXC disassembly.
Removing the injected read/gates and restoring exactly three declarations
(resource return type, position mask, temp count) reproduces every baseline SHEX
byte. The sole ISGN change is SV_Position's used-Z bit. Parameter-blob checks
verify all 64 renamed bindings preserve resource slot, dimension and no-sampler
metadata. The validation report is
`artifacts/npr/map-ray-visibility-validation/validation.json`.

Those checks describe the original exact-depth candidate. The revised bounded
candidate also passed FXC disassembly for all 128 skin programs. Live forced-bit
tests established shader binding, followed by a real sun-only frozen-pose test
on 2026-11-16. With map geometry and 12 baked character submeshes, head-to-neck
and hand-to-chest shadows were visible. Triangle-shaped artifacts remained on
the torso; this is not accepted image quality or a continuous shadow solution.

The session candidate is
`artifacts/npr/cap-comparison/character-map-rays-footprint.unity3d`.
Captures are under `artifacts/npr/sun-shadow-check/self-{off,on,restored}.png`.
The diagnostic DXIL emits only bit zero, which was `Directional Light Far` in
that captured light ordering. It does not implement general sun selection.
The snapshot was cleared and animation restored after testing. No production
frame-time claim follows from this rebuild-and-readback experiment.
