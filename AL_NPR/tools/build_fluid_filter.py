"""Give the body fluid mask the same Slang reconstruction across regular Forward+ variants."""

import argparse
from pathlib import Path

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


def build(source, output, slangc=None):
    entry = compile_entry("FluidSample", source="FluidSample.slang", slangc=slangc)
    build_material_bundle(source, output, lambda code, _: patch_body(code, entry), targets=(146,))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--slangc")
    args = parser.parse_args()
    build(args.source, args.output, args.slangc)


if __name__ == "__main__":
    main()
