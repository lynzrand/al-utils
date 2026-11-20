"""Build a face-only comparison filter with the existing light and material inputs."""
import argparse
from pathlib import Path

from build_view_band_trial import build_material_bundle
from compiled_material_entry import compile_entry, bind_entry
from patch_skin_light_shoulder import decode_program, emit, encode_program

def filter_face(code, entry, band):
    version, instructions = decode_program(code)
    decl, = [i for i,t in enumerate(instructions) if t[0] & 2047 == 104]
    count, program = entry
    uvz = instructions[decl][1]
    output, scratch = uvz + 1, uvz + 2
    # Only the first punctual traversal supplies the visible toon band.
    reads = [i for i,t in enumerate(instructions) if t[0] & 2047 == 56 and len(t) == 10
             and t[5] & ~0xff0 == 0x06208006 and t[6:8] == (1,256)]
    raw, lit = reads[:2]
    def ops(start, stop):
        return [t[0]&2047 for t in instructions[start:stop]]
    if ops(lit+8,lit+17) != [16,56,16,50,52,56,14,56,0] or ops(lit-1,lit+2) != [56,56,56]:
        raise ValueError("Unexpected normal-bent head band")
    contribution = instructions[lit+9]
    visibility = instructions[lit-1][-2:]
    result = []
    sites = 0
    for i,t in enumerate(instructions):
        if i == decl:
            result.append((t[0], scratch + max(count,band[0])))
        elif t[0] & 2047 == 71 and instructions[i-1][0] & 2047 == 14:
            if len(t) != 13 or t[7] >> 12 != 0x107 or t[9] != 0x106000:
                raise ValueError("Unexpected punctual shadow comparison")
            result.extend([emit(54,0x100032,uvz,*t[5:7]),emit(54,0x100042,uvz,*t[-2:]),
                           *bind_entry(program,[uvz],output,scratch,{(7,0):t[8],(6,0):t[10]}),
                           emit(54,*t[3:5],0x10000a,output)])
            sites += 1
        elif i == lit+9:
            result.extend([emit(56,0x100072,uvz,0x100246,instructions[raw][2],*instructions[lit+1][-2:]),
                           emit(56,0x100072,uvz,0x100246,uvz,*contribution[5:]),
                           emit(54,0x100082,uvz,*visibility),
                           *bind_entry(band[1],[uvz],contribution[2],scratch)])
        elif not lit+10 <= i <= lit+15:
            result.append(t)
    if sites not in (0,2):
        raise ValueError(f"Expected matching prepass and replay shadow lookups, found {sites}")
    return encode_program(version,result)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source",type=Path)
    parser.add_argument("output",type=Path)
    args = parser.parse_args()
    entry = compile_entry("FaceShadow")
    band = compile_entry("FaceBand")
    build_material_bundle(args.source,args.output,lambda code,_:filter_face(code,entry,band),targets=(76,))
