"""Opt-in hue-preserving replacement for AL body's masked palette clamp.

This is not a global output limiter. The head shader has no matching branch and
must be left unchanged. With knee=None, only peaks above 0.95 change, using a
common RGB scale. A soft knee additionally compresses peaks above that knee,
approaching 0.95 smoothly. Neither mode has live visual acceptance.
"""

import argparse
import math
from pathlib import Path

from patch_skin_light_shoulder import (
    decode_program, encode_program, parts, build_container, emit, imm32,
    DECLARE_TEMPS, OPCODE_MASK, TEMP_XYZ, SOURCE_XYZX,
)


def patch_program(code, knee=None):
    if knee is not None and (not math.isfinite(knee) or not 0 < knee < 0.95):
        raise ValueError('Soft knee must lie strictly between zero and 0.95')
    version, instructions = decode_program(code)
    ceiling = imm32(0.95)[1]
    matches = [i for i,t in enumerate(instructions)
               if len(t) == 10 and t[0] & OPCODE_MASK == 51
               and t[1] == TEMP_XYZ and t[3:5] == (SOURCE_XYZX,t[2])
               and t[5:] == (0x4002, ceiling, ceiling, ceiling, 0)]
    if len(matches) != 1:
        raise ValueError('Expected exactly one body palette clamp; do not apply to head')
    index, = matches
    rgb = instructions[index][2]
    previous = instructions[index-1]
    if (previous[0] & OPCODE_MASK != 52 or previous[1:5] != instructions[index][1:5]
            or previous[5:] != (0x4002, 0, 0, 0, 0)
            or instructions[index-2][0] & OPCODE_MASK != 50
            or instructions[index-3][0] & OPCODE_MASK != 0):
        raise ValueError('Expected material lerp followed by nonnegative RGB clamp')
    declaration, = [i for i,t in enumerate(instructions) if t[0] & OPCODE_MASK == DECLARE_TEMPS]
    header, temporary = instructions[declaration]
    instructions[declaration] = (header, temporary + 1)
    x, y, z = (0x0010000A, temporary), (0x0010001A, temporary), (0x0010002A, temporary)
    dx, dy, dz = (0x00100012, temporary), (0x00100022, temporary), (0x00100042, temporary)
    replacement = [emit(52, *dx, 0x0010000A, rgb, 0x0010001A, rgb),
                   emit(52, *dx, *x, 0x0010002A, rgb)]
    if knee is None:
        # max(peak, ceiling) makes the divisor finite, including black, and
        # yields exactly one below the existing threshold.
        replacement += [emit(52, *dx, *x, *imm32(0.95)),
                        emit(14, *dx, *imm32(0.95), *x)]
    else:
        # t=max(peak-knee,0); mapped=min(peak,knee)+t/(1+t/(ceiling-knee)).
        replacement += [emit(0, *dy, *x, *imm32(-knee)),
                        emit(52, *dy, *y, *imm32(0.0)),
                        emit(50, *dz, *y, *imm32(1.0/(0.95-knee)), *imm32(1.0)),
                        emit(14, *dz, *y, *z),
                        emit(51, *dy, *x, *imm32(knee)),
                        emit(0, *dz, *z, *y),
                        emit(52, *dx, *x, *imm32(1e-20)),
                        emit(14, *dx, *z, *x)]
    replacement.append(emit(56, TEMP_XYZ, rgb, SOURCE_XYZX, rgb, *x))
    instructions[index:index+1] = replacement
    return encode_program(version, instructions)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stock', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--knee', type=float)
    args = parser.parse_args()
    if args.stock.resolve() == args.output.resolve():
        parser.error('Use a separate output path')
    args.output.write_bytes(build_container([(tag, patch_program(code,args.knee) if tag == b'SHEX' else code)
                                            for tag,code in parts(args.stock.read_bytes())]))
