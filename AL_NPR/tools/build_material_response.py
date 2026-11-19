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
UNBENT_SHA = "f34398d9778177fb9f56ee01fa52767af82a55a44f60ba4812cdf13cdd936f3e"
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


def compile_entries(source, fxc, directory, normal_bend):
    entries = {}
    names = ["PerLightBand", "SkinFill", "FabricFill"]
    if normal_bend:
        names.append("BandFacing")
    for name in names:
        path = directory / (name + ".cso")
        subprocess.run([fxc, "/nologo", "/O3", "/T", "ps_5_0", "/E", name, "/Fo", path, source], check=True)
        _, instructions = decode_program(dict(parts(path.read_bytes()))[b"SHEX"])
        declarations = [106, 98, 98, 101, 104] if name == "BandFacing" else [106, 98, 101, 104]
        start = len(declarations)
        if [t[0] & 2047 for t in instructions[:start]] != declarations or instructions[-1] != emit(62):
            raise ValueError(f"Unexpected input or output declarations for {name}")
        entries[name] = instructions[start-1][1], instructions[start:-1]
    return entries


def bind(entry, inputs, output, scratch):
    """Bind each compiled input swizzle and the output to the material's operands."""
    count, instructions = entry
    bound = []
    for t in instructions:
        op = t[0] & 2047
        if op not in (0, 14, 16, 50, 51, 52, 54, 56, 68):
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
                args.extend((token, scratch + idx))
            elif kind == 0x101000 and (idx, token & 0xfff) in inputs:
                args.extend(inputs[idx, token & 0xfff])
            elif kind == 0x102000 and idx == 0 and i == 1:
                # A scalar dot product can write any original destination lane.
                # Other instructions keep the compiler's lane selection.
                if (token & 0xfff) != (output[0] & 0xfff) and op != 16:
                    raise ValueError("Unexpected output lane remapping")
                args.extend(output)
            else:
                raise ValueError(f"Unexpected HLSL operand {token:#x}, {idx}")
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
        edits[i] = 6, bind(entries["PerLightBand"], {(0, 0x246): (SOURCE_XYZX, rgb)}, (TEMP_XYZ, rgb), scratch)
        if "BandFacing" in entries:
            facing = ins[i-2]
            if facing[0] & 0x27ff != 0x2010 or len(facing) != 7 or ops[i-1] != 56:
                raise ValueError("Expected a saturated world normal/light dot before the band")
            inputs = {(0, 0x246): facing[3:5], (1, 0x246): facing[5:7]}
            edits[i-2] = 1, bind(entries["BandFacing"], inputs, facing[1:3], scratch)
    merge, = [i for i,t in enumerate(ins) if t[0] & 0x27ff == 0x2038 and t[-2:] == imm32(1/.18)
              and ins[i-1][-5:] == LUMA]
    total = ins[merge][2]
    def fill_code(entry, probe, destination):
        inputs = {(0, 0x246): (SOURCE_XYZX, probe), (0, 0x03a): (0x10003a, total)}
        return bind(entries[entry], inputs, (0x100012, destination), scratch)
    if shader in SKIN:
        # The first full SH evaluation in the material replay uses the same
        # world-space normal as the per-light facing dot. The later half-normal
        # and view-dependent probes belong to other stock palette lobes.
        probe = next(i+10 for i in range(merge+1, len(ins)-10)
                     if ops[i:i+11] == [17,17,17,56,17,17,17,56,50,50,0]
                     and ins[i+10][1] == TEMP_XYZ)
        edits[probe] = 1, [ins[probe], *fill_code("SkinFill", ins[probe][2], fill)]
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
        edits[probe] = 3, fill_code("FabricFill", ins[probe][4], ins[probe][2])
    output = []
    i = 0
    while i < len(ins):
        consumed, replacement = edits.get(i,(1,[ins[i]]))
        output.extend(replacement)
        i += consumed
    return encode_program(version,output)


def build(source, output, fxc=None, hlsl=SOURCE):
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    if digest not in (BASE_SHA, UNBENT_SHA):
        raise ValueError("Expected either the unbent per-light pair or its November 18 camera-bent version")
    with tempfile.TemporaryDirectory() as tmp:
        entries = compile_entries(hlsl, fxc or find_fxc(), Path(tmp), normal_bend=digest == UNBENT_SHA)
        build_material_bundle(source, output, lambda code, shader: patch(code,shader,entries))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--fxc", help="Path to the Windows SDK Shader Model 5 compiler")
    args = parser.parse_args()
    build(args.source, args.output, args.fxc)
