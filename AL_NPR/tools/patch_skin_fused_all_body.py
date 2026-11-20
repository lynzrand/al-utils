"""Experimental three-lobe fusion of the SHA-audited captured body shader.

Keep the first NPR/ramp accumulator and its early consumers unchanged. Evaluate
the later r6-normal Lambert and wrapped sums during the first light traversal,
using two private RGB accumulators across the intervening skin shading. All
original per-light arithmetic order inside each sum and the final mix survive.
Not a generic asset patch; requires replay acceptance before integration.
"""

import argparse
import hashlib
from pathlib import Path

from patch_skin_light_shoulder import (
    decode_program, encode_program, parts, build_container, dxbc_checksum,
    emit, imm32, TEMP_XYZ, SOURCE_XYZX, DECLARE_TEMPS, OPCODE_MASK,
)
from patch_skin_fused_lobes import STOCK_SHA256


def patch_container(raw):
    if hashlib.sha256(raw).hexdigest() != STOCK_SHA256 or dxbc_checksum(raw[20:]) != raw[4:20]:
        raise ValueError('Expected audited original captured body DXBC')
    sections = list(parts(raw))
    code, = [v for k,v in sections if k == b'SHEX']
    version, ins = decode_program(code)
    offset = 54
    at = lambda n: ins[n+offset]
    declaration, = [i for i,t in enumerate(ins) if t[0] & OPCODE_MASK == DECLARE_TEMPS]
    header, lambert = ins[declaration]
    wrapped, scratch = lambert+1, lambert+2
    ins[declaration] = (header, lambert+3)
    if not (at(1125)[0] & OPCODE_MASK == 54 and at(2206)[0] & OPCODE_MASK == 54
            and at(3239)[0] & OPCODE_MASK == 22 and at(3240)[0] & OPCODE_MASK == 0
            and at(3241)[0] & OPCODE_MASK == 50):
        raise ValueError('Changed instruction anchors')
    # The later normal is ready before the first traversal and remains immutable.
    if any(len(t)>2 and t[1] & 0xFFFFFF0F == 0x00100002 and t[2] == 6 and t[1] & 0x70
           for t in ins[offset+1125:offset+3239]):
        raise ValueError('Later normal was modified')
    # All six original light responses share the exact same fade operand.
    colors = (1354,1662,2435,2717,2951,3234)
    if any(at(n-3)[0] & OPCODE_MASK != 50 or at(n-3)[3:5] != (0x0010003A,25) for n in colors):
        raise ValueError('Different shadow fade input')
    for number in colors:
        color, gate = at(number), at(number-2)
        if (color[6:8] != (1,256) or gate[0] & OPCODE_MASK != 1
                or gate[3:6] != (0x0020800A,4,10)
                or gate[6:] != (0x0620800A,1,1280,*color[8:10])):
            raise ValueError('Different light color or rendering-layer source')
    before = {offset+1125: [emit(54,TEMP_XYZ,lambert,*imm32(0)),
                           emit(54,TEMP_XYZ,wrapped,*imm32(0))]}
    for number, direction, color, gate in (
            (1355,(0x00100346,36),37,29),
            (1663,(SOURCE_XYZX,37),38,30)):
        if at(number)[0] & OPCODE_MASK != 16 or at(number)[3:5] != (SOURCE_XYZX,10):
            raise ValueError('First lobe changed')
        if at(number)[5:7] != direction:
            raise ValueError('First light direction changed')
        before[offset+number] = [
            emit(16|0x2000,0x00100082,scratch,SOURCE_XYZX,6,*direction),
            emit(50,TEMP_XYZ,scratch,SOURCE_XYZX,color,0x00100FF6,scratch,SOURCE_XYZX,lambert),
            emit(55,TEMP_XYZ,lambert,0x00100FF6,gate,SOURCE_XYZX,scratch,SOURCE_XYZX,lambert),
            emit(16,0x00100082,scratch,*direction,SOURCE_XYZX,6),
            emit(50,0x00100082,scratch,0x0010003A,scratch,*imm32(.5),*imm32(.5)),
            emit(50,TEMP_XYZ,scratch,0x00100FF6,scratch,SOURCE_XYZX,color,SOURCE_XYZX,wrapped),
            emit(55,TEMP_XYZ,wrapped,0x00100FF6,gate,SOURCE_XYZX,scratch,SOURCE_XYZX,wrapped),
        ]
    # The final two old accumulator live-outs are replaced directly. Private
    # temps cannot be clobbered by stock instructions; the first lobe's original
    # r34/r36 sums remain available to instructions1667 onward.
    addition = at(3240)
    if addition[3:] != (0x80100796,0x41,3,SOURCE_XYZX,5):
        raise ValueError('Changed final accumulator linkage')
    ins[offset+3240] = emit(0,TEMP_XYZ,1,0x80100246,0x41,lambert,SOURCE_XYZX,wrapped)
    mix = at(3241)
    if mix[-2:] != (0x00100796,3):
        raise ValueError('Changed final mix')
    ins[offset+3241] = (*mix[:-2],SOURCE_XYZX,lambert)
    result = []
    for i,t in enumerate(ins):
        if offset+2206 <= i <= offset+3239:
            continue
        result.extend(before.get(i,()))
        result.append(t)
    changed = encode_program(version,result)
    result = build_container([(k,changed if k == b'SHEX' else v) for k,v in sections])
    if [(k,v) for k,v in parts(result) if k != b'SHEX'] != [(k,v) for k,v in sections if k != b'SHEX']:
        raise ValueError('Shader bindings or another nonexecutable section changed')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stock',type=Path)
    parser.add_argument('output',type=Path)
    args = parser.parse_args()
    if args.stock.resolve() == args.output.resolve():
        parser.error('Choose a separate output path')
    args.output.write_bytes(patch_container(args.stock.read_bytes()))
