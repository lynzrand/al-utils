"""Early shadow rejection for audited captured AL cloth and hair programs.

Each rejected light has a zero distance/spot attenuation or a nonmatching
rendering layer. Skip its PCF work and preserve the outer light-list iterator.
The AL/Map candidate rejects only mismatched layers because its BRDF and
transmission paths use attenuation at different points.
"""

import argparse
import hashlib
from pathlib import Path

from patch_early_shadow_reject import patch as patch_skin_structure
from patch_skin_light_shoulder import (
    decode_program, build_container, parts, dxbc_checksum, MUL, OPCODE_MASK,
    emit, encode_program, TEMP_X, SOURCE_X, DECLARE_TEMPS,
)


CAPTURES = {
    'ec281fa16c3c7fb20b9cfb278d05c9ce17174888a42027fd41c4138dd942ed0d': 'AL/cloth event 18407',
    'e90e9ea43016cd1238278b0d284b3c7645c811ccaa5560c192ee782ba4b116c1': 'AL/hair event 18654',
    'ceeeedfaec4536cc8431407a536e244637a565481d2cd87d4b10b0d620b29767': 'AL/Map event 17875',
}


def patch_map_layers(code):
    version, instructions = decode_program(code)
    declaration, = (i for i,t in enumerate(instructions) if t[0] & OPCODE_MASK == DECLARE_TEMPS)
    header, scratch = instructions[declaration]
    instructions[declaration] = (header, scratch + 1)
    stack, owners, ends = [], {}, {}
    for i,t in enumerate(instructions):
        op = t[0] & OPCODE_MASK
        if op == 48:
            stack.append(i)
        elif op == 22:
            ends[stack.pop()] = i
        if stack:
            owners[i] = stack[-1]
    before = {}
    for i,t in enumerate(instructions):
        if (t[0] & OPCODE_MASK != 1 or len(t) != 11 or
                t[3:6] != (0x0020800A, 4, 10) or t[6:9] != (0x0620800A, 1, 1280)):
            continue
        loop = owners[i]
        end = ends[loop]
        if not 1 <= end - i <= 25:
            raise ValueError('Unexpected map light accumulator length')
        index = t[9:11]
        starts = [j for j in range(max(loop + 1, i - 249), i)
                  if instructions[j][0] & OPCODE_MASK == 34
                  and instructions[j][3:] == (*index, 0x4001, 0)
                  and instructions[j + 1][0] & OPCODE_MASK == 27]
        if len(starts) != 1 or owners[starts[0]] != loop:
            raise ValueError('Unexpected map shadow entrance')
        start = starts[0]
        if any(q[0] & OPCODE_MASK in (7, 8, 13, 48, 62, 63, 164, 165, 166)
               for q in instructions[start:end]):
            raise ValueError('Unexpected map shadow region side effect')
        tail = instructions[end - 1]
        prefix = ()
        if tail[0] & OPCODE_MASK == 30:
            if tail[3:] != (*index, 0x4001, 1):
                raise ValueError('Unexpected map directional iterator')
            prefix = (tail,)
            select = instructions[end - 2]
        else:
            select = tail
        gate_component = ((t[1] >> 4) & 15).bit_length() - 1
        gate_splat = 0x00100006 | (gate_component * 0x55 << 4)
        if select[0] & OPCODE_MASK != 55 or select[3:5] != (gate_splat, t[2]):
            raise ValueError('Map accumulator must be selected by this layer gate')
        before[start] = (emit(1, TEMP_X, scratch, *t[3:]), emit(31, SOURCE_X, scratch),
                         *prefix, emit(7), emit(21))
    if len(before) != 6:
        raise ValueError('Expected six map layer gates')
    result = []
    for i,t in enumerate(instructions):
        result.extend(before.get(i, ()))
        result.append(t)
    return encode_program(version, result)


def validate_loops(code, *, expected_lights=6, max_tail=7):
    _, instructions = decode_program(code)
    stack = []
    enclosing = {}
    ends = {}
    for i, instruction in enumerate(instructions):
        op = instruction[0] & OPCODE_MASK
        if op == 48:  # LOOP
            stack.append(i)
        elif op == 22:  # ENDLOOP
            if not stack:
                raise ValueError('Unmatched ENDLOOP')
            ends[stack.pop()] = i
        if stack:
            enclosing[i] = stack[-1]
    if stack:
        raise ValueError('Unclosed LOOP')

    lights = []
    for i, instruction in enumerate(instructions):
        if (len(instruction) == 10 and instruction[0] & OPCODE_MASK == MUL
                and instruction[5] & ~0xFF0 == 0x06208006
                and instruction[6:8] == (1, 256)):
            lights.append(i)
            loop = enclosing.get(i)
            if loop is None or not 1 <= ends[loop] - i <= max_tail:
                raise ValueError('Light accumulation is not at an audited outer-loop tail')
            matches = [j for j in range(max(loop + 1, i - 249), i - 2)
                       if instructions[j][0] & OPCODE_MASK == 34
                       and instructions[j][3:] == (*instruction[8:10], 0x4001, 0)
                       and instructions[j + 1][0] & OPCODE_MASK == 27]
            if len(matches) != 1 or enclosing.get(matches[0]) != loop:
                raise ValueError('Shadow entrance must be unique and in the same light loop')
            # The inserted continue skips only this loop's shadow and arithmetic.
            # Texture stores, discard, returns, or another loop invalidate it.
            region = instructions[matches[0]:i]
            if any(t[0] & OPCODE_MASK in (7, 8, 13, 48, 62, 63, 164, 165, 166)
                   for t in region):
                raise ValueError('Unexpected side effect or nested loop in shadow region')
    if len(lights) != expected_lights or len({enclosing[i] for i in lights}) != expected_lights:
        raise ValueError(f'Expected {expected_lights} distinct additional-light loops')


def patch_container(raw):
    fingerprint = hashlib.sha256(raw).hexdigest()
    if fingerprint not in CAPTURES or raw[:4] != b'DXBC' or dxbc_checksum(raw[20:]) != raw[4:20]:
        raise ValueError('Expected one of the audited stock cloth/hair captures')
    sections = list(parts(raw))
    programs = [code for tag, code in sections if tag == b'SHEX']
    if len(programs) != 1:
        raise ValueError('Expected one SM5 executable section')
    is_map = CAPTURES[fingerprint].startswith('AL/Map ')
    if not is_map:
        validate_loops(programs[0])
    transform = patch_map_layers if is_map else patch_skin_structure
    # The shared routine additionally proves layer-index equivalence, attenuation
    # operands, and explicit directional-loop increment versus clustered tail.
    result = build_container([(tag, transform(code) if tag == b'SHEX' else code)
                              for tag, code in sections])
    if [(tag, data) for tag, data in parts(result) if tag != b'SHEX'] != [
            (tag, data) for tag, data in sections if tag != b'SHEX']:
        raise ValueError('Nonexecutable shader section changed')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stock', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    if args.stock.resolve() == args.output.resolve():
        parser.error('Choose a separate output file')
    args.output.write_bytes(patch_container(args.stock.read_bytes()))
