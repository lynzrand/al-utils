"""Insert zero-contribution branches in the captured map002 SSAO shader."""

import argparse
import hashlib
import math
from pathlib import Path
import struct


STOCK_SHA256 = "45ab2e1b4a440096c674cd5d4c8700f32fed48ef9569efde1b0764706b675585"
WORD = 0xFFFFFFFF
MD5_CONSTANTS = [int(abs(math.sin(index + 1)) * 2**32) for index in range(64)]


def dxbc_checksum(data):
    """DXBC uses MD5 compression with its retail container padding."""
    count = len(data)
    remainder = count % 64
    whole = data[:count - remainder]
    tail = data[count - remainder:]
    if remainder >= 56:
        whole += tail + b"\x80" + bytes(63 - remainder)
        tail = bytes(56)
    else:
        tail += b"\x80" + bytes(55 - remainder)
    blocks = whole + struct.pack("<I", count << 3) + tail + struct.pack("<I", (count << 1) | 1)
    state = (0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476)
    shifts = ((7, 12, 17, 22), (5, 9, 14, 20), (4, 11, 16, 23), (6, 10, 15, 21))

    for offset in range(0, len(blocks), 64):
        words = struct.unpack_from("<16I", blocks, offset)
        a, b, c, d = state
        for index, constant in enumerate(MD5_CONSTANTS):
            round_index = index // 16
            if round_index == 0:
                value, word = (b & c) | (~b & d), index
            elif round_index == 1:
                value, word = (d & b) | (~d & c), (5 * index + 1) % 16
            elif round_index == 2:
                value, word = b ^ c ^ d, (3 * index + 5) % 16
            else:
                value, word = c ^ (b | ~d), (7 * index) % 16
            shift = shifts[round_index][index % 4]
            step = (a + value + constant + words[word]) & WORD
            rotated = ((step << shift) | (step >> (32 - shift))) & WORD
            a, b, c, d = d, (b + rotated) & WORD, b, c
        state = tuple((old + new) & WORD for old, new in zip(state, (a, b, c, d)))
    return struct.pack("<4I", *state)


def parts(container):
    count = struct.unpack_from("<I", container, 28)[0]
    for offset in struct.unpack_from(f"<{count}I", container, 32):
        kind = container[offset:offset + 4]
        size = struct.unpack_from("<I", container, offset + 4)[0]
        yield kind, container[offset + 8:offset + 8 + size]


def build_container(chunks):
    offset = 32 + 4 * len(chunks)
    offsets, sections = [], []
    for kind, code in chunks:
        offsets.append(offset)
        section = kind + struct.pack("<I", len(code)) + code
        sections.append(section)
        offset += len(section)
    data = struct.pack("<3I", 1, offset, len(chunks)) + struct.pack(f"<{len(chunks)}I", *offsets) + b"".join(sections)
    return b"DXBC" + dxbc_checksum(data) + data


def patch_program(code):
    words = struct.unpack(f"<{len(code) // 4}I", code)
    cursor = 2
    instructions = []
    while cursor < len(words):
        op = words[cursor] & 2047
        size = words[cursor + 1] if op == 53 else (words[cursor] >> 24) & 127
        if not size:
            raise ValueError(f"Malformed instruction at word {cursor}")
        instructions.append(words[cursor:cursor + size])
        cursor += size

    # The first seven instructions are declarations. Leave the first tap
    # intact: it computes an unmasked contribution for the second tap's FMA.
    # Later taps feed one FMA into the AO accumulator. A zero validity mask
    # makes that FMA an identity for finite contributions.
    insert_before = {}
    ranges = [(170, 183, 3, 3), (221, 234, 3, 3), (271, 284, 3, 3),
              (322, 335, 3, 3), (372, 385, 3, 3), (423, 436, 3, 3),
              (473, 486, 3, 3), (524, 537, 3, 3), (574, 587, 3, 3)]
    for mask, end, register, component in ranges:
        start = mask + 7
        stop = end + 8
        expected_dest = 0x00100002 | (1 << (component + 4))
        if (instructions[start][0] & 2047, *instructions[start][1:3]) != (56, expected_dest, register):
            raise ValueError(f"Unexpected validity mask at instruction {mask}")
        if instructions[stop - 1][0] & 2047 != 50:
            raise ValueError(f"Unexpected accumulator at instruction {end}")
        scalar_source = 0x0010000A | (component << 4)
        insert_before[start + 1] = (0x0304001F, scalar_source, register)  # if_nz
        insert_before[stop] = (0x01000015,)  # endif

    output = list(words[:2])
    for index, instruction in enumerate(instructions):
        output.extend(insert_before.get(index, ()))
        output.extend(instruction)
    output[1] = len(output)
    return struct.pack(f"<{len(output)}I", *output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stock", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    stock = args.stock.read_bytes()
    if hashlib.sha256(stock).hexdigest() != STOCK_SHA256:
        parser.error("input differs from the captured stock map002 SSAO variant")
    if dxbc_checksum(stock[20:]) != stock[4:20]:
        parser.error("input container checksum mismatch")
    chunks = [(kind, patch_program(code) if kind == b"SHDR" else code) for kind, code in parts(stock)]
    args.output.write_bytes(build_container(chunks))


if __name__ == "__main__":
    main()
