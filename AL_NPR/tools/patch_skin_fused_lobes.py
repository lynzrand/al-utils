"""Fuse the two final additional-light traversals of one audited stock body PS.

Preserve separate Lambert/wrapped accumulators and the original final mix.
This is an offline replay candidate, not a generalized runtime patch. Stock
instructions 2722..3239 repeat the same light lists, attenuation, shadow and
layer gate; only their wrapped response differs. Their sole live-out read by
the remaining shader is r5.xyz, replaced from the new wrapped accumulator.
"""

import argparse
import hashlib
from pathlib import Path

from patch_skin_light_shoulder import (
    build_container, decode_program, encode_program, parts, dxbc_checksum,
    emit, imm32, TEMP_XYZ, SOURCE_XYZX, DECLARE_TEMPS, OPCODE_MASK,
    locate_mix,
)


STOCK_SHA256 = 'f6b4a3c640a97882ae90f95caafc1077b4b94f1d723cfbecb87e3d2f70d03e46'


def validate_live_out(instructions, start, mix):
    """Conservatively scan temp components in this straight-line shader tail."""
    def registers(instruction):
        for index, token in enumerate(instruction[1:], 1):
            if token & 0x7FFFF000 != 0x00100000:
                continue
            argument = index + 1 + int(bool(token & 0x80000000))
            if argument >= len(instruction):
                raise ValueError('Truncated temp operand')
            register = instruction[argument]
            mode = (token >> 2) & 3
            if mode == 0:
                channels = [c for c in range(4) if token & (16 << c)]
            elif mode == 2:
                channels = [(token >> 4) & 3]
            elif mode == 1:
                channels = [(token >> (4 + 2*c)) & 3 for c in range(4)]
            else:
                raise ValueError('Unsupported temp addressing')
            yield index == 1 and mode == 0, {(register, c) for c in channels}
    killed, live, written = set(), set(), set()
    for instruction in instructions[mix-1:]:
        if instruction[0] & OPCODE_MASK in (2, 3, 6, 7, 8, 10, 18, 21, 22, 23, 31, 48, 63, 76):
            raise ValueError('Fusion live-out proof requires a straight-line tail')
        operands = list(registers(instruction))
        for destination, components in operands:
            if not destination:
                live |= components - killed
        for destination, components in operands:
            if destination:
                killed |= components
    for instruction in instructions[start:mix-1]:
        for destination, components in registers(instruction):
            if destination:
                written |= components
    select = instructions[mix-3]
    expected = {(select[2], c) for c in range(4) if select[1] & (16 << c)}
    if (live & written) - expected:
        raise ValueError('Removed traversal has another live-out')


def patch_program(code):
    """Structural candidate for regular Forward+ skin; callers gate stock hashes.

    The result has FOUR light-color sites. Downstream cap and reject passes must
    explicitly accept four, and must execute after this pass. The stock mix
    signature is retained for locate_mix; caps then feed both lobe accumulators.
    """
    version, ins = decode_program(code)
    mix, _ = locate_mix(ins)
    sites = [i for i, t in enumerate(ins) if len(t) == 10 and t[0] & OPCODE_MASK == 56
             and t[5] & ~0xFF0 == 0x06208006 and t[6:8] == (1, 256)]
    if len(sites) != 6:
        raise ValueError('Fusion requires six original light-color reads')
    stack, owners, ends = [], {}, {}
    for i, t in enumerate(ins):
        if t[0] & OPCODE_MASK == 48:
            stack.append(i)
        elif t[0] & OPCODE_MASK == 22:
            ends[stack.pop()] = i
        if stack:
            owners[i] = stack[-1]
    loops = [owners[i] for i in sites]
    if len(set(loops)) != 6 or ends[loops[-1]] != mix - 2:
        raise ValueError('Unexpected six-loop/mix structure')
    start, remove = loops[2] - 2, loops[4] - 2
    for index in (start, remove):
        if any(ins[index+j][0] & OPCODE_MASK != 54 for j in (0, 1)):
            raise ValueError('Expected accumulator and directional-index initialization')
        if any(ins[index+j][-1] != 0 for j in (0, 1)):
            raise ValueError('Expected zero initialization')
    declaration, = [i for i, t in enumerate(ins) if t[0] & OPCODE_MASK == DECLARE_TEMPS]
    header, accumulator = ins[declaration]
    scratch = accumulator + 1
    ins[declaration] = (header, accumulator + 2)
    before = {start: [emit(54, TEMP_XYZ, accumulator, *imm32(0.0))]}
    for a, b in zip(sites[2:4], sites[4:6]):
        lambert, wrapped, response = ins[a+1], ins[b+1], ins[b+2]
        if (lambert[0] & OPCODE_MASK != 16 or not lambert[0] & 0x2000
                or wrapped[0] & OPCODE_MASK != 16 or wrapped[0] & 0x2000
                or response[0] & OPCODE_MASK != 50 or response[-4:] != (*imm32(0.5), *imm32(0.5))):
            raise ValueError('Unexpected Lambert/wrapped response')
        if lambert[3:5] != wrapped[5:7]:
            raise ValueError('Lobes do not share the same normal')
        light = ins[a]
        channels = [c for c in range(4) if light[1] & (16 << c)]
        if len(channels) != 3:
            raise ValueError('Expected RGB light destination')
        swizzle = 0x00100006 | (sum(c << (4 + 2*n) for n,c in enumerate(channels + channels[:1])))
        gate = ins[a-2]
        if gate[0] & OPCODE_MASK != 1:
            raise ValueError('Expected layer AND')
        mask = (gate[1] >> 4) & 15
        if mask not in (1, 2, 4, 8):
            raise ValueError('Expected scalar layer gate')
        component = mask.bit_length() - 1
        before[a+1] = [
            emit(16, 0x00100082, scratch, *lambert[5:7], *lambert[3:5]),
            emit(50, 0x00100082, scratch, 0x0010003A, scratch, *imm32(0.5), *imm32(0.5)),
            emit(50, TEMP_XYZ, scratch, 0x00100FF6, scratch, swizzle, light[2], SOURCE_XYZX, accumulator),
            emit(55, TEMP_XYZ, accumulator, 0x00100006 | (component * 0x55 << 4), gate[2],
                 SOURCE_XYZX, scratch, SOURCE_XYZX, accumulator),
        ]
    # The removed wrapped pair feeds only this ADD; the original Lambert
    # accumulator and the final MAD remain untouched.
    addition = ins[mix-1]
    final_select = ins[mix-3]
    if final_select[0] & OPCODE_MASK != 55 or addition[-1] != final_select[2]:
        raise ValueError('Unexpected wrapped accumulator live-out')
    validate_live_out(ins, remove, mix)
    ins[mix-1] = (*addition[:-2], SOURCE_XYZX, accumulator)
    out = []
    for i, t in enumerate(ins):
        if remove <= i <= mix-2:
            continue
        out.extend(before.get(i, ()))
        out.append(t)
    result = encode_program(version, out)
    # The kept loop now directly precedes the original ADD/MAD signature.
    locate_mix(out)
    return result


def patch_container(raw):
    if hashlib.sha256(raw).hexdigest() != STOCK_SHA256 or dxbc_checksum(raw[20:]) != raw[4:20]:
        raise ValueError('Expected the audited body event18223 stock DXBC')
    sections = list(parts(raw))
    code, = [v for k, v in sections if k == b'SHEX']
    version, instructions = decode_program(code)
    declaration, = [i for i, t in enumerate(instructions) if t[0] & OPCODE_MASK == DECLARE_TEMPS]
    header, accumulator = instructions[declaration]
    scratch = accumulator + 1
    instructions[declaration] = (header, accumulator + 2)
    # FXC instruction numbering excludes the 54 declaration records.
    offset = 54
    at = lambda number: instructions[offset + number]
    if not (at(2206)[0] & OPCODE_MASK == 54 and at(2721)[0] & OPCODE_MASK == 22
            and at(3239)[0] & OPCODE_MASK == 22 and at(3240)[0] & OPCODE_MASK == 0):
        raise ValueError('Audited instruction anchors changed')
    before = {offset + 2206: [emit(54, TEMP_XYZ, accumulator, *imm32(0.0))]}
    for number, direction, color, gate, gate_component in (
            (2436, 2, (SOURCE_XYZX, 5), 3, 2),
            (2718, 5, (0x00100796, 7), 7, 0)):
        original = at(number)
        if original[0] & OPCODE_MASK != 16 or not original[0] & 0x2000:
            raise ValueError('Expected stock saturated Lambert dot')
        # Keep the original Lambert DP3 untouched. Wrapped stock uses reversed
        # dot operands, then a scalar MAD, then its own RGB MAD and layer select.
        before[offset + number] = [
            emit(16, 0x00100082, scratch, SOURCE_XYZX, direction, SOURCE_XYZX, 6),
            emit(50, 0x00100082, scratch, 0x0010003A, scratch, *imm32(0.5), *imm32(0.5)),
            emit(50, TEMP_XYZ, scratch, 0x00100FF6, scratch, *color, SOURCE_XYZX, accumulator),
            emit(55, TEMP_XYZ, accumulator, 0x00100006 | (gate_component * 0x55 << 4), gate,
                 SOURCE_XYZX, scratch, SOURCE_XYZX, accumulator),
        ]
    result = []
    for index, instruction in enumerate(instructions):
        if offset + 2722 <= index <= offset + 3239:
            continue
        if index == offset + 3240:
            result.append(emit(54, TEMP_XYZ, 5, SOURCE_XYZX, accumulator))
        result.extend(before.get(index, ()))
        result.append(instruction)
    changed = encode_program(version, result)
    return build_container([(k, changed if k == b'SHEX' else v) for k, v in sections])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stock', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    if args.stock.resolve() == args.output.resolve():
        parser.error('Choose a distinct output path')
    args.output.write_bytes(patch_container(args.stock.read_bytes()))
