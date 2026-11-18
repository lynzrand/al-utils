"""Route regular AL skin additional lights through authored map bit 0x2.

Apply LAST, after fusion, early rejection, and light caps. Both original gates
and early-rejection copies must be changed together. Runtime must select this
shader only for an eligible map scene; the bytecode cannot infer map presence.
No Unity light masks, culling, shadow-caster lists, or bindings are modified.
"""

import argparse
from pathlib import Path

from patch_skin_light_shoulder import decode_program, encode_program, emit, parts, build_container


def patch_program(code, *, expected_lights=6, early_reject=False):
    if expected_lights not in (2,4,6):
        raise ValueError('Expected two, four, or six audited light traversals')
    version, instructions = decode_program(code)
    changed = 0
    for i,t in enumerate(instructions):
        if t[0] & 2047 != 1:
            continue
        # Ordinary renderer mask (cb4[10].x), then per-light mask.
        regular = (len(t) == 11 and t[3:6] == (0x0020800A,4,10)
                   and t[6:9] == (0x0620800A,1,1280))
        # Conventional instancing reverses the operands and uses cb6[index+8].x.
        instanced = (len(t) == 13 and t[3:6] == (0x0620800A,1,1280)
                     and t[8:11] == (0x0620800A,6,8))
        if not (regular or instanced):
            continue
        light = t[6:] if regular else t[3:8]
        if light[3] & 0xFFFFFFCF != 0x0010000A:
            raise ValueError('Expected scalar temp light index')
        instructions[i] = emit(1,*t[1:3],0x4001,0x2,*light)
        changed += 1
    expected = expected_lights * (2 if early_reject else 1)
    if changed != expected:
        raise ValueError(f'Expected {expected} original/copied layer gates; found {changed}')
    return encode_program(version,instructions)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stock',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--expected-lights',type=int,default=6)
    parser.add_argument('--early-reject',action='store_true')
    args = parser.parse_args()
    if args.stock.resolve() == args.output.resolve():
        parser.error('Choose a separate output path')
    args.output.write_bytes(build_container([(tag,patch_program(code,expected_lights=args.expected_lights,
                                                               early_reject=args.early_reject) if tag==b'SHEX' else code)
                                            for tag,code in parts(args.stock.read_bytes())]))
