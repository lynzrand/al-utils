"""Give the body fluid mask the same Slang reconstruction across regular Forward+ variants."""

import argparse
from pathlib import Path
import subprocess
import tempfile

from build_skin_assets import WORKSPACE
from build_view_band_trial import build_material_bundle
from compiled_material_entry import bind_entry, compile_entry
from patch_skin_light_shoulder import decode_program, emit, encode_program


def patch_body(code, entry):
    version, instructions = decode_program(code)
    decl, = (i for i, t in enumerate(instructions) if t[0] & 2047 == 104)
    uv = instructions[decl][1]
    output, scratch = uv + 1, uv + 2
    count, program = entry
    patched = []
    sites = 0
    for i, t in enumerate(instructions):
        if i == decl:
            patched.append((t[0], scratch + count))
        elif t[0] & 2047 == 69 and len(t) == 11 and t[8] == 0:
            if t[7] != 0x107e46 or t[9] != 0x106000 or t[3] not in (0x100082, 0x1000f2):
                raise ValueError("Unexpected body fluid texture sample")
            patched.append(emit(54, 0x100032, uv, *t[5:7]))
            patched.extend(bind_entry(program, [uv], output, scratch, {(7, 0): 0, (6, 0): t[10]}))
            patched.append(emit(54, *t[3:5], 0x100e46, output))
            sites += 1
        else:
            patched.append(t)
    if sites != 6:
        raise ValueError(f"Expected two sets of three body fluid samples, found {sites}")
    return encode_program(version, patched)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--slangc", default="slangc")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as temp:
        source = Path(temp) / "FluidSample.slang"
        source.write_text("import FluidMask;\n"
                          "Texture2D<float4> mask : register(t0);\n"
                          "SamplerState state : register(s0);\n"
                          "[shader(\"fragment\")] float4 main(float2 uv : TEXCOORD0) : SV_Target\n"
                          "{ return sampleFluidMask(mask, state, uv); }\n")
        hlsl = source.with_suffix(".hlsl")
        subprocess.run([args.slangc, str(source), "-I", str(WORKSPACE / "AL_NPR/shaders/slang"),
                        "-entry", "main", "-target", "hlsl", "-profile", "sm_5_0",
                        "-o", str(hlsl)], check=True)
        entry = compile_entry(hlsl, "main")
        if any(t[0] & 2047 in (62, 63) for t in entry[1]):
            raise ValueError("Fluid sampling must return to the original shader")
    build_material_bundle(args.source, args.output, lambda code, _: patch_body(code, entry), targets=(146,))


if __name__ == "__main__":
    main()
