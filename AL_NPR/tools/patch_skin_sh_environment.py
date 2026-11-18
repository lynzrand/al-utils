"""Offline candidate using SH-derived skin shaping with no main-light inputs.

The stock-derived additional-light rolloffs are retained. This candidate removes
the main shadow-filter block and substitutes a broad SH lobe for AL's artistic
key. Its appearance and speed require replay/live validation. Pattern validation
covers regular Forward+ head/body variants, including conventional instancing.
"""

import argparse
from pathlib import Path

from patch_skin_authored_direction import patch_program as add_authored_direction
from patch_skin_light_shoulder import (
    parts, build_container, decode_program, encode_program, dxbc_checksum,
    patch_environment_program, locate_mix, emit, imm32, MOV, MUL, MAD, MAX,
    DECLARE_TEMPS, TEMP_X, TEMP_XYZ, SOURCE_X, SOURCE_XYZX,
)


def redirect(instruction, slot, register):
    if instruction[0] & 2047 == 53:
        return instruction
    out = [instruction[0]]
    i = 1
    while i < len(instruction):
        token = instruction[i]
        extended = int(bool(token & 0x80000000))
        args = i + 1 + extended
        if token & 0x7FFFF000 == 0x00208000 and instruction[args:args + 2] == (0, slot):
            out.append(token & 0x80000FFF | 0x00100000)
            if extended:
                out.append(instruction[i + 1])
            out.append(register)
            i = args + 2
        else:
            out.append(token)
            i += 1
    out[0] = out[0] & ~(127 << 24) | len(out) << 24
    return tuple(out)


def patch(code, *, expected_lights=6, locate_light_mix=locate_mix, authored_direction=False):
    version, instructions = decode_program(patch_environment_program(
        code, expected_lights=expected_lights, locate_light_mix=locate_light_mix))
    declaration, = (i for i, t in enumerate(instructions) if t[0] & 2047 == DECLARE_TEMPS)
    opcode, count = instructions[declaration]
    ambient, direction, instance = count, count + 1, count + 2
    # The original first instruction loads the instance ID before register reuse.
    _, original = decode_program(code)
    original_decl = next(i for i,t in enumerate(original) if t[0] & 2047 == DECLARE_TEMPS)
    first = original[original_decl + 1]
    instanced = first[0] & 2047 == 30 and first[-3:] == (0x0020800A, 5, 0)
    shadow_buffer = 8 if instanced else 5
    shadow = count + (3 if instanced else 2)
    instructions[declaration] = (opcode, shadow + int(authored_direction))
    def sh(component, swizzle):
        if instanced:
            return (0x06208000 | swizzle, 7, component, 0x0010000A, instance)
        return (0x00208000 | swizzle, 4, 25 + component)
    # The earlier patch's neutral main-color initialization now receives the
    # SH constant coefficients. The actual main color never enters the result.
    instructions = [redirect(redirect(t, 6, ambient), 5, direction) for t in instructions]
    initialization = [
        emit(MOV, 0x00100012, ambient, *sh(0, 0x3A)),
        emit(MOV, 0x00100022, ambient, *sh(1, 0x3A)),
        emit(MOV, 0x00100042, ambient, *sh(2, 0x3A)),
        emit(MOV, 0x00100082, ambient, *imm32(1.0)),
        emit(MAX, TEMP_XYZ, ambient, SOURCE_XYZX, ambient, *imm32(0.001)),
        emit(MUL, TEMP_XYZ, direction, *sh(0, 0x246), *imm32(0.212673)),
        emit(MAD, TEMP_XYZ, direction, *sh(1, 0x246), *imm32(0.715152), SOURCE_XYZX, direction),
        emit(MAD, TEMP_XYZ, direction, *sh(2, 0x246), *imm32(0.072175), SOURCE_XYZX, direction),
        # Flat ambient has no dominant direction. A tiny upward bias keeps the
        # original normalization finite and defines that otherwise ambiguous case.
        emit(0, 0x00100022, direction, 0x0010001A, direction, *imm32(0.0001)),
        emit(MOV, 0x00100082, direction, *imm32(0.0)),
    ]
    if instanced:
        initialization[:0] = [
            emit(30, 0x00100012, instance, *first[3:]),
            emit(38, 0xD000, 0x00100012, instance, 0x0010000A, instance, 0x4001, 7),
        ]
    starts = [i for i, t in enumerate(instructions) if t[0] & 2047 == 49
              and t[3:] == (0x4001, 0, 0x20801A, shadow_buffer, 27)]
    fades = [i for i,t in enumerate(instructions) if t[0] & 2047 == 0 and len(t) == 9
             and t[3:7] == (0x8020800A, 0x41, shadow_buffer, 27)]
    if len(starts) > 1 or len(fades) != 1:
        raise ValueError('Expected one main-shadow fade and at most one quality selector')
    fade = fades[0]
    start = starts[0] if starts else fade - 1
    if not starts and instructions[start][0] & 2047 != 71:
        raise ValueError('Expected direct comparison sample in hard-shadow variant')
    depth = 0
    end = None
    for i in range(start + 1, fade):
        op = instructions[i][0] & 2047
        if op == 31:
            depth += 1
        elif op == 21:
            depth -= 1
            if depth == 0:
                end = i + 7
                break
    if not starts:
        end = fade + 6
    if starts and end != fade + 6:
        raise ValueError('Shadow filter and fade are not adjacent')
    if end is None or [t[0] & 2047 for t in instructions[end - 5:end + 1]] != [MAD, 29, 29, 60, 55, 0]:
        raise ValueError('Unexpected main-shadow fade/clamp sequence')
    # The final clamp writes r0.x in both audited shaders. Main shadow is one;
    # the map's additional lights retain their original shadow maps and PCF.
    if instructions[end - 1][1:3] != (0x00100012, 0):
        raise ValueError('Unexpected main-shadow destination')
    shadow_region = instructions[start:end] if authored_direction else []
    replacement = []
    if authored_direction:
        # The runtime sets this flag only when the omitted map directional
        # owns the bound shadow atlas. Its attenuation is used solely by
        # that light's contribution to the three light accumulations.
        replacement.extend([
            emit(MOV, TEMP_X, shadow, *imm32(1.0)),
            emit(31 | 0x40000, 0x0020800A, 10, 2),
            *shadow_region,
            emit(MOV, TEMP_X, shadow, SOURCE_X, 0),
            emit(21),
        ])
    replacement.append(emit(MOV, TEMP_X, 0, *imm32(1.0)))
    instructions[start:end] = replacement
    instructions[declaration + 1:declaration + 1] = initialization
    code = encode_program(version, instructions)
    return add_authored_direction(code, shadow_source=(SOURCE_X, shadow)) if authored_direction else code


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stock', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    raw = args.stock.read_bytes()
    if raw[:4] != b'DXBC' or dxbc_checksum(raw[20:]) != raw[4:20]:
        parser.error('Expected a valid DXBC shader container')
    if args.stock.resolve() == args.output.resolve():
        parser.error('Choose a separate output file')
    args.output.write_bytes(build_container([(tag, patch(data) if tag == b'SHEX' else data)
                                            for tag, data in parts(raw)]))
