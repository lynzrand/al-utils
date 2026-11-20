"""Replay candidate caching raw main-shadow PCF in captured AL/Map 15772.

15772 and map-filter15677 have identical DXBC. Keep each consumer's original
strength, saturation, out-of-bounds, and distance-fade arithmetic. Only reuse
raw comparison filtering, before the first consumer's saturating MAD.
SHA gating and shared-input checks delimit the audited program; GPU replay is
still required to test rounding differences from compiler arithmetic packing.
"""

import argparse
from collections import Counter
import hashlib
from pathlib import Path

from patch_skin_light_shoulder import (
    decode_program, encode_program, build_container, parts, dxbc_checksum,
    emit, DECLARE_TEMPS, OPCODE_MASK,
)
from patch_al_full_light_fusion import written_components


STOCK_SHA256='00f871a1f90a076539d350a6a6335d2cbacfc82277d2843c6d4fdfafd1bc6708'


def patch_container(raw):
    if hashlib.sha256(raw).hexdigest()!=STOCK_SHA256 or dxbc_checksum(raw[20:])!=raw[4:20]:
        raise ValueError('Expected audited stock AL/Map15772 or identical15677')
    sections=list(parts(raw))
    code,=[v for k,v in sections if k==b'SHEX']
    version,ins=decode_program(code)
    offset=33
    at=lambda n:ins[offset+n]
    blocks=((28,199),(895,1066),(1675,1847))
    if written_components(ins[offset+4:offset+1848]) & {(0,c) for c in (0,1,2)}:
        raise ValueError('Shared main-shadow projection r0.xyz is overwritten')
    fingerprints=[]
    for start,end in blocks:
        region=ins[offset+start:offset+end+1]
        if at(start)!=(0x0304001F,0x0010003A,0) or at(end)!=(0x01000015,):
            raise ValueError('Different outer PCF quality branch')
        samples=[t for t in region if t[0]&OPCODE_MASK==71]
        if len(samples)!=30 or any(t[-2:]!=(0x0010002A,0) for t in samples):
            raise ValueError('Different PCF comparison count or projected depth')
        resources=Counter()
        for t in region:
            if t[0]&OPCODE_MASK in (7,8,13,48,62,63,164,165,166):
                raise ValueError('Unexpected PCF region side effect')
            for i,token in enumerate(t[1:],1):
                kind=token&0x7FFFF000
                argument=i+1+int(bool(token&0x80000000))
                if kind==0x00208000:
                    resources[(kind,*t[argument:argument+2])]+=1
                elif kind in (0x00107000,0x00106000):
                    resources[(kind,t[argument])]+=1
        fingerprints.append(resources)
    if fingerprints[1:]!=[fingerprints[0],fingerprints[0]]:
        raise ValueError('PCF filter constants, texture, or sampler differ')
    # The first post-filter operation saturates; the other consumers do not.
    for number,source in ((201,(0x0010003A,2)),(1067,(0x0010000A,9)),(1848,(0x0010003A,0))):
        t=at(number)
        if t[0]&OPCODE_MASK!=50 or t[3:5]!=source or t[5:8]!=(0x0020800A,5,27):
            raise ValueError('Different raw-shadow consumer')
    declaration,=[i for i,t in enumerate(ins) if t[0]&OPCODE_MASK==DECLARE_TEMPS]
    header,cache=ins[declaration]
    ins[declaration]=(header,cache+1)
    result=[]
    for i,t in enumerate(ins):
        if offset+895<=i<=offset+1066 or offset+1675<=i<=offset+1847:
            if i==offset+895:
                result.append(emit(54,0x00100012,9,0x0010000A,cache))
            elif i==offset+1675:
                result.append(emit(54,0x00100082,0,0x0010000A,cache))
            continue
        result.append(t)
        if i==offset+199:
            result.append(emit(54,0x00100012,cache,0x0010003A,2))
    output=build_container([(tag,encode_program(version,result) if tag==b'SHEX' else value)
                            for tag,value in sections])
    if [(k,v) for k,v in parts(output) if k!=b'SHEX'] != [(k,v) for k,v in sections if k!=b'SHEX']:
        raise ValueError('Nonexecutable shader sections changed')
    return output


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stock',type=Path)
    parser.add_argument('output',type=Path)
    args=parser.parse_args()
    if args.stock.resolve()==args.output.resolve():
        parser.error('Use a separate output path')
    args.output.write_bytes(patch_container(args.stock.read_bytes()))
