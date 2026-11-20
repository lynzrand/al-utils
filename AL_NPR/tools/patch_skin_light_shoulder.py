"""Patch the late additional-light mix of the two audited AL skin PS variants."""

import argparse
from pathlib import Path
import hashlib
import math
import struct
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "AL_Performance" / "tools"))
from patch_ssao_dxbc import build_container, dxbc_checksum, parts


# Each stock variant mixes two accumulated light responses with the same MAD.
# The hash identifies the bytecode that was traced, including its signatures.
VARIANTS = {
    "f6b4a3c640a97882ae90f95caafc1077b4b94f1d723cfbecb87e3d2f70d03e46": (3295, 1),
    "543515967b601fb7dd147e6af8b7298ab6eefccbbdc70269da81c88d269ffe9b": (3072, 2),
}
ADD, DIV, MAD, MAX, MUL, DECLARE_TEMPS = 0, 14, 50, 52, 56, 104
OPCODE_MASK = 2047
TEMP_X, TEMP_XYZ = 0x00100012, 0x00100072
SOURCE_X, SOURCE_Y, SOURCE_Z, SOURCE_XYZX = 0x0010000A, 0x0010001A, 0x0010002A, 0x00100246
MOV, DP3, IADD = 54, 16, 30


def imm32(value):
    return (0x00004001, struct.unpack("<I", struct.pack("<f", value))[0])


def emit(opcode, *operands):
    return ((1 + len(operands)) << 24 | opcode, *operands)


def shoulder(rgb, scratch, knee, strength):
    """Emit ALSkinExtraLightShoulder in place, with one spare scalar."""
    temp = (TEMP_X, scratch)
    peak = (SOURCE_X, scratch)
    return (
        emit(MAX, *temp, SOURCE_X, rgb, SOURCE_Y, rgb),
        emit(MAX, *temp, *peak, SOURCE_Z, rgb),
        emit(ADD, *temp, *peak, *imm32(-knee)),
        emit(MAX, *temp, *peak, *imm32(0.0)),
        emit(MAD, *temp, *peak, *imm32(strength), *imm32(1.0)),
        emit(DIV, *temp, *imm32(1.0), *peak),
        emit(MUL, TEMP_XYZ, rgb, SOURCE_XYZX, rgb, *peak),
    )


def decode_stage(code):
    words = struct.unpack(f"<{len(code) // 4}I", code)
    cursor = 2
    instructions = []
    while cursor < len(words):
        opcode = words[cursor] & OPCODE_MASK
        size = words[cursor + 1] if opcode == 53 else (words[cursor] >> 24) & 127
        if size == 0 or cursor + size > len(words):
            raise ValueError(f"Malformed instruction at word {cursor}")
        instructions.append(words[cursor:cursor + size])
        cursor += size
    if words[1] != len(words):
        raise ValueError("Incomplete shader instruction stream")
    return words[0], instructions


def decode_program(code):
    version, instructions = decode_stage(code)
    if version != 0x50:
        raise ValueError("Expected a complete SM5 pixel program")
    return version, instructions


def locate_mix(instructions):
    # Across the regular Forward+ variants, this mix immediately follows the
    # additional punctual-light loop and precedes the skin palette controls.
    matches = []
    for i in range(2, len(instructions) - 3):
        t = instructions[i]
        if (len(t) == 12 and t[0] & OPCODE_MASK == MAD and t[1] == TEMP_XYZ
                and t[3] == SOURCE_XYZX and t[2] == t[4]
                and t[5:10] == (0x4002, 0x3F000000, 0x3F000000, 0x3F000000, 0)):
            neighbors = tuple(instructions[i + j][0] & OPCODE_MASK for j in (-2, -1, 1, 2, 3))
            if neighbors == (22, ADD, ADD, MAX, MAD):
                matches.append((i, t[2]))
    if len(matches) != 1:
        raise ValueError(f"Expected one audited additional-light mix, found {len(matches)}")
    return matches[0]


def patch_program(code, mix_index, rgb, knee, strength):
    version, instructions = decode_program(code)
    if locate_mix(instructions) != (mix_index, rgb):
        raise ValueError("Cannot find the audited additional-light mix")

    declarations = [i for i, t in enumerate(instructions) if t[0] & OPCODE_MASK == DECLARE_TEMPS]
    if len(declarations) != 1 or declarations[0] >= mix_index:
        raise ValueError("Unexpected temporary register declaration")
    d = declarations[0]
    opcode, temps = instructions[d]
    instructions[d] = (opcode, temps + 1)

    instructions[mix_index + 1:mix_index + 1] = shoulder(rgb, temps, knee, strength)
    return encode_program(version, instructions)


def encode_program(version, instructions):
    output = [version, 0]
    for instruction in instructions:
        output.extend(instruction)
    output[1] = len(output)
    return struct.pack(f"<{len(output)}I", *output)


def redirect_key_color(instruction, key):
    """Replace immediate cb0[6] sources with the same swizzle on the skin key."""
    if instruction[0] & OPCODE_MASK == 53:
        return instruction
    result = [instruction[0]]
    index = 1
    while index < len(instruction):
        token = instruction[index]
        extended = 1 if token & 0x80000000 else 0
        args = index + 1 + extended
        if token & 0x7FFFF000 == 0x00208000 and instruction[args:args + 2] == (0, 6):
            result.append(token & 0x80000FFF | 0x00100000)
            if extended:
                result.append(instruction[index + 1])
            result.append(key)
            index = args + 2
        else:
            result.append(token)
            index += 1
    result[0] = result[0] & ~(127 << 24) | len(result) << 24
    return tuple(result)


def patch_environment_program(code, *, expected_lights=6, locate_light_mix=locate_mix):
    version, instructions = decode_program(code)
    mix, accumulator = locate_light_mix(instructions)
    declaration, = (i for i, t in enumerate(instructions) if t[0] & OPCODE_MASK == DECLARE_TEMPS)
    opcode, temps = instructions[declaration]
    key, raw, scale = range(temps, temps + 3)
    if instructions[declaration + 1][0] & OPCODE_MASK not in (ADD, MOV, MUL, IADD):
        raise ValueError("Unexpected first skin instruction")

    rewritten = [redirect_key_color(t, key) for t in instructions]
    if sum(a != b for a, b in zip(instructions, rewritten, strict=True)) < 8:
        raise ValueError("Too few key-color consumers")
    rewritten[declaration] = (opcode, temps + 3)

    # Preserve key brightness and the fourth channel. The game still provides
    # the original direction and filtered shadows through their own bindings.
    after = {declaration: (
        emit(MOV, 0x001000F2, key, 0x00208E46, 0, 6),
        emit(DP3, TEMP_XYZ, key, SOURCE_XYZX, key, 0x00004002,
             imm32(0.212673)[1], imm32(0.715152)[1], imm32(0.072175)[1], 0),
    ), mix: shoulder(accumulator, scale, 0.18, 4.5)}
    before = {}
    for i, t in enumerate(instructions):
        if (len(t) != 10 or t[0] & OPCODE_MASK != MUL or
                t[5] & ~0xFF0 != 0x06208006 or t[6:8] != (1, 256)):
            continue
        previous = instructions[i - 1]
        guard = instructions[i - 2]
        light_mask = (0x0620800A, 1, 1280, *t[8:10])
        layers = (guard[3:6] == (0x0020800A, 4, 10) and guard[6:] == light_mask
                  or guard[3:8] == light_mask and guard[8:11] == (0x0620800A, 6, 8))
        if (len(previous) != 7 or previous[0] & OPCODE_MASK != MUL or
                guard[0] & OPCODE_MASK != 1 or not layers):
            raise ValueError("Unrecognized shadow or layer gate before a skin light-color multiply")
        component = ((previous[1] >> 4) & 15).bit_length() - 1
        scalar = (SOURCE_X | component << 4, previous[2])
        splat = 0x00100006 | (component * 0x55 << 4)
        if component < 0 or t[3:5] != (splat, previous[2]) or scalar not in (previous[3:5], previous[5:7]):
            raise ValueError("Cannot identify the unshadowed attenuation")

        # Compute the divisor from unshadowed RGB just before AL multiplies by
        # shadow. Scale the original contribution afterward so shadows retain
        # their original contrast. The original RGB destination is xyz or yzw.
        temp = (TEMP_X, scale)
        peak = (SOURCE_X, scale)
        before[i - 1] = (
            emit(MUL, TEMP_XYZ, raw, *scalar, 0x06208246, *t[6:10]),
            emit(MAX, *temp, SOURCE_X, raw, SOURCE_Y, raw),
            emit(MAX, *temp, *peak, SOURCE_Z, raw),
            emit(ADD, *temp, *peak, *imm32(-0.10)),
            emit(MAX, *temp, *peak, *imm32(0)),
            emit(MAD, *temp, *peak, *imm32(7.0), *imm32(1)),
            emit(DIV, *temp, *imm32(1), *peak),
        )
        rgb_channels = [(t[5] >> (4 + c * 2)) & 3 for c in range(4) if t[1] & (16 << c)]
        if t[1] & ~0xF0 != 0x00100002 or rgb_channels != [0, 1, 2]:
            raise ValueError("Unexpected light RGB destination")
        after[i] = (emit(MUL, t[1], t[2], 0x00100E46, t[2], *peak),)
    if len(before) != expected_lights:
        raise ValueError(f"Expected {expected_lights} additional-light reads, found {len(before)}")
    emitted = []
    for i, instruction in enumerate(rewritten):
        emitted.extend(before.get(i, ()))
        emitted.append(instruction)
        emitted.extend(after.get(i, ()))
    return encode_program(version, emitted)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stock", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--knee", type=float, default=0.20)
    parser.add_argument("--strength", type=float, default=2.0)
    args = parser.parse_args()
    if any(not math.isfinite(value) or value < 0 or value > 10 for value in (args.knee, args.strength)):
        parser.error("knee and strength must be finite and between 0 and 10")
    stock = args.stock.read_bytes()
    variant = VARIANTS.get(hashlib.sha256(stock).hexdigest())
    if variant is None or dxbc_checksum(stock[20:]) != stock[4:20]:
        parser.error("expected an audited stock skin head or body DXBC container")
    if args.stock.resolve() == args.output.resolve():
        parser.error("use a new output file")

    sections = [(tag, patch_program(code, *variant, args.knee, args.strength) if tag == b"SHEX" else code)
                for tag, code in parts(stock)]
    args.output.write_bytes(build_container(sections))


if __name__ == "__main__":
    main()
