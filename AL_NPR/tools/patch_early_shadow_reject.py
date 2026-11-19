"""Skip a captured skin light's shadow reads when its contribution is zero."""

import argparse
import hashlib
from pathlib import Path

from patch_skin_light_shoulder import (
    VARIANTS, DECLARE_TEMPS, IADD, MUL, OPCODE_MASK, SOURCE_X, TEMP_X,
    build_container, decode_program, emit, encode_program, parts,
)


AND, FTOI, ILT, MOVC = 1, 27, 34, 55
ENDLOOP, CONTINUE, IF, ENDIF = 22, 7, 31, 21
IMMEDIATE_ZERO = (0x4001, 0)


def patch(code, *, expected_lights=6, max_tail=7):
    version, instructions = decode_program(code)
    declaration, = (i for i, instruction in enumerate(instructions)
                    if instruction[0] & OPCODE_MASK == DECLARE_TEMPS)
    header, scratch = instructions[declaration]
    instructions[declaration] = (header, scratch + 1)
    before = {}
    for i, light in enumerate(instructions):
        if (len(light) != 10 or light[0] & OPCODE_MASK != MUL or
                light[5] & ~0xFF0 != 0x06208006 or light[6:8] != (1, 256)):
            continue
        gate = instructions[i - 2]
        if gate[0] & OPCODE_MASK != AND:
            raise ValueError("Unexpected light layer gate")
        light_mask = (0x0620800A, 1, 1280, *light[8:10])
        regular = gate[3:6] == (0x0020800A, 4, 10) and gate[6:] == light_mask
        instanced = gate[3:8] == light_mask and gate[8:11] == (0x0620800A, 6, 8)
        if not (regular or instanced):
            raise ValueError("The layer check must use the same light index")
        start = next(j for j in range(i - 3, i - 250, -1)
                     if instructions[j][0] & OPCODE_MASK == ILT
                     and instructions[j][3:] == (*light[8:10], *IMMEDIATE_ZERO)
                     and instructions[j + 1][0] & OPCODE_MASK == FTOI)
        attenuation = instructions[start - 1]
        if attenuation[0] & OPCODE_MASK != MUL or len(attenuation) != 7:
            raise ValueError("Expected the distance and angle product before the shadow")
        component = ((attenuation[1] >> 4) & 15).bit_length() - 1
        preshadow = instructions[i - 1]
        if (SOURCE_X | (component << 4), attenuation[2]) not in (preshadow[3:5], preshadow[5:7]):
            raise ValueError("Unverified attenuation")

        end = next(j for j in range(i + 1, i + max_tail + 1)
                   if instructions[j][0] & OPCODE_MASK == ENDLOOP)
        prefix = ()
        if instructions[end - 1][0] & OPCODE_MASK == IADD:
            increment = instructions[end - 1]
            if increment[3:] != (*light[8:10], 0x4001, 1):
                raise ValueError("Unexpected loop index increment")
            prefix = (increment,)
        elif instructions[end - 1][0] & OPCODE_MASK != MOVC:
            raise ValueError("Unexpected clustered loop tail")

        before[start] = (
            emit(AND, TEMP_X, scratch, *gate[3:]),
            emit(MOVC, TEMP_X, scratch, SOURCE_X, scratch,
                 SOURCE_X | (component << 4), attenuation[2], *IMMEDIATE_ZERO),
            emit(IF, SOURCE_X, scratch),
            *prefix,
            emit(CONTINUE),
            emit(ENDIF),
        )

    if len(before) != expected_lights:
        raise ValueError(f"Expected {expected_lights} light loops, matched {len(before)}")
    result = []
    for i, instruction in enumerate(instructions):
        result.extend(before.get(i, ()))
        result.append(instruction)
    return encode_program(version, result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stock", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    stock = args.stock.read_bytes()
    if hashlib.sha256(stock).hexdigest() not in VARIANTS or args.stock.resolve() == args.output.resolve():
        parser.error("Use audited stock bytecode and a distinct output file")
    args.output.write_bytes(build_container([(tag, patch(code) if tag == b"SHEX" else code)
                                             for tag, code in parts(stock)]))


if __name__ == "__main__":
    main()
