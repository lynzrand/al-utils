"""Compile the shared HLSL band and fill into AL's existing skin and fabric programs."""

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from build_skin_assets import SKIN, WORKSPACE, parts
from build_toon_band_trials import LUMA, band_color
from build_view_band_trial import build_material_bundle
from patch_skin_light_shoulder import SOURCE_XYZX, TEMP_XYZ, decode_program, emit, encode_program, imm32


BASE_SHA = "63e6be4aed4878f1515d71014f0e5c411f832509df80d2540c185a21a798c4bd"
SOURCE = WORKSPACE / "AL_NPR/shaders/SceneToonLighting.hlsl"


def find_fxc():
    compiler = shutil.which("fxc")
    if compiler:
        return compiler
    kit = Path(os.environ["ProgramFiles(x86)"]) / "Windows Kits/10/bin"
    candidates = list(kit.glob("10.*/x64/fxc.exe"))
    if not candidates:
        raise FileNotFoundError("Install the Windows SDK FXC compiler or supply --fxc")
    return max(candidates, key=lambda p: tuple(map(int, p.parents[1].name.split("."))))


def compile_entries(source, fxc, directory):
    entries = {}
    for name in ("PerLightBand", "SkinFill", "FabricFill"):
        path = directory / (name + ".cso")
        subprocess.run([fxc, "/nologo", "/O3", "/T", "ps_5_0", "/E", name, "/Fo", path, source], check=True)
        _, instructions = decode_program(dict(parts(path.read_bytes()))[b"SHEX"])
        declarations = [t[0] & 2047 for t in instructions[:4]]
        if declarations != [106, 98, 101, 104] or instructions[-1] != emit(62):
            raise ValueError(f"{name} must be straight-line RGB arithmetic with one input and output")
        entries[name] = instructions[3][1], instructions[4:-1]
    return entries


def bind(entry, input_rgb, input_band, output, scratch):
    """Bind v0.xyz and v0.w to existing shader registers, o0 to a private result."""
    count, instructions = entry
    bound = []
    for t in instructions:
        op = t[0] & 2047
        if op not in (0, 14, 16, 50, 51, 52, 54, 56):
            raise ValueError(f"Unsupported HLSL arithmetic opcode {op}")
        args = []
        i = 1
        while i < len(t):
            token = t[i]
            if token in (0x4001, 0x4002):
                n = 2 if token == 0x4001 else 5
                args.extend(t[i:i+n])
                i += n
                continue
            kind = token & ~0xfff
            idx = t[i+1]
            if kind == 0x100000 and idx < count:
                register = scratch + idx
            elif kind == 0x101000 and idx == 0:
                # Reject cross-register swizzles. Only the RGB dot and the
                # separate W scalar are part of these entry point contracts.
                if token & 0xfff == 0x03a and input_band is not None:
                    register = input_band
                elif token & 0xfff == 0x246:
                    register = input_rgb
                else:
                    raise ValueError(f"Unexpected HLSL input swizzle {token:#x}")
            elif kind == 0x102000 and idx == 0 and i == 1:
                register = output
            else:
                raise ValueError(f"Unexpected HLSL operand {token:#x}, {idx}")
            args.extend((0x100000 | (token & 0xfff), register))
            i += 2
        bound.append(emit(t[0] & 0xffffff, *args))
    return bound


def patch(code, shader, entries):
    version, ins = decode_program(code)
    ops = [t[0] & 2047 for t in ins]
    decl, = [i for i, op in enumerate(ops) if op == 104]
    header, fill = ins[decl]
    pigment, scratch = fill + 1, fill + 2
    ins[decl] = (header, scratch + max(count for count, _ in entries.values()))
    edits = {}
    band_sites = [i for i,t in enumerate(ins[:-5]) if ops[i] == 16 and t[-5:] == LUMA
                  and tuple(ins[i:i+6]) == tuple(band_color(t[4], t[2]))]
    if len(band_sites) != 2:
        raise ValueError("Expected one directional and one clustered per-light band")
    for i in band_sites:
        rgb = ins[i][4]
        edits[i] = 6, bind(entries["PerLightBand"], rgb, None, rgb, scratch)
    merge, = [i for i,t in enumerate(ins) if t[0] & 0x27ff == 0x2038 and t[-2:] == imm32(1/.18)
              and ins[i-1][-5:] == LUMA]
    total = ins[merge][2]
    if shader in SKIN:
        # The first full SH evaluation in the material replay uses the same
        # world-space normal as the per-light facing dot. The later half-normal
        # and view-dependent probes belong to other stock palette lobes.
        probe = next(i+10 for i in range(merge+1, len(ins)-10)
                     if ops[i:i+11] == [17,17,17,56,17,17,17,56,50,50,0]
                     and ins[i+10][1] == TEMP_XYZ)
        edits[probe] = 1, [ins[probe], *bind(entries["SkinFill"], ins[probe][2], total, fill, scratch)]
        # Save the processed pigment before AL compresses it for its extra
        # color term. Add diffuse fill at the multiply-add combining that
        # term with the skin palette, before the face/body-specific overlays.
        at, = [i for i,t in enumerate(ins[:-2]) if t[0]&0x27ff == 0x2032
               and t[5:] == (0x4002, *(imm32(x)[1] for x in (7,7,7,0)),
                             0x4002, *(imm32(x)[1] for x in (.3,.3,.3,0)))
               and ops[i+1:i+3] == [50,50] and ins[i+2][3:5] == (SOURCE_XYZX,t[2])]
        result = ins[at+2]
        if result[1] != TEMP_XYZ or result[7:] != (SOURCE_XYZX, result[2]):
            raise ValueError("Unexpected skin composition")
        edits[at] = 1, [emit(54,TEMP_XYZ,pigment,*ins[at][3:5]),ins[at]]
        edits[at+2] = 1, [result,emit(50,*result[1:3],SOURCE_XYZX,pigment,0x10000a,fill,*result[7:])]
    else:
        probe, = [i for i,t in enumerate(ins[:-2]) if t[0]&0x27ff==0x2010 and t[-5:]==LUMA
                  and ins[i+1][-4:]==(*imm32(.84),*imm32(0))
                  and ins[i+2][3:7]==(0x10003a,total,*imm32(.49))]
        edits[probe] = 3, bind(entries["FabricFill"],ins[probe][4],total,ins[probe][2],scratch)
    output = []
    i = 0
    while i < len(ins):
        consumed, replacement = edits.get(i,(1,[ins[i]]))
        output.extend(replacement)
        i += consumed
    return encode_program(version,output)


def build(source, output, fxc=None, hlsl=SOURCE):
    if hashlib.sha256(source.read_bytes()).hexdigest() != BASE_SHA:
        raise ValueError("Expected the November 18 per-light default as input")
    with tempfile.TemporaryDirectory() as tmp:
        entries = compile_entries(hlsl, fxc or find_fxc(), Path(tmp))
        build_material_bundle(source, output, lambda code, shader: patch(code,shader,entries))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--fxc", help="Path to the Windows SDK Shader Model 5 compiler")
    args = parser.parse_args()
    build(args.source, args.output, args.fxc)
