"""Experimental shared map-light selection for AL hair, cloth and cloth_alpha.

Apply after optional full fusion and early shadow rejection. Only additional
light inputs change. Stock main-light highlight/band logic, palette, textures,
reflection, alpha and shadow sampling remain intact. This deliberately does
not claim removal of primary-light specialness or full skin response parity.
"""

from patch_skin_light_shoulder import decode_program, encode_program, emit, imm32
from patch_skin_map_layer import patch_program as use_map_layer


def patch_program(code, *, expected_lights, early_reject=True, cap_profile='color-aware'):
    if cap_profile not in ('gentle-peak', 'color-aware'):
        raise ValueError('Surface trial requires gentle-peak or color-aware cap')
    version, ins = decode_program(code)
    declaration, = [i for i,t in enumerate(ins) if t[0]&2047 == 104]
    header, raw = ins[declaration]
    scale, spare = raw+1, raw+2
    ins[declaration] = (header, raw+3)
    dest, value = (0x00100012,scale), (0x0010000A,scale)
    extra_dest, extra = (0x00100012,spare), (0x0010000A,spare)
    before, after = {}, {}
    for i,t in enumerate(ins):
        if len(t)!=10 or t[0]&2047!=56 or t[5]&~0xFF0!=0x06208006 or t[6:8]!=(1,256):
            continue
        previous, gate = ins[i-1], ins[i-2]
        light_mask=(0x0620800A,1,1280,*t[8:10])
        layers=(gate[3:6]==(0x0020800A,4,10) and gate[6:]==light_mask
                or gate[3:8]==light_mask and gate[8:11]==(0x0620800A,6,8))
        if len(previous)!=7 or previous[0]&2047!=56 or gate[0]&2047!=1 or not layers:
            raise ValueError('Unrecognized surface shadow/layer gate')
        mask=(previous[1]>>4)&15
        if mask not in (1,2,4,8): raise ValueError('Expected scalar shadow attenuation')
        component=mask.bit_length()-1
        attenuation=(0x0010000A|(component<<4),previous[2])
        splat=0x00100006|(component*0x55<<4)
        if t[3:5]!=(splat,previous[2]) or attenuation not in (previous[3:5],previous[5:7]):
            raise ValueError('Unrecognized unshadowed surface attenuation')
        channels=[(t[5]>>(4+c*2))&3 for c in range(4) if t[1]&(16<<c)]
        if t[1]&~0xF0!=0x00100002 or channels!=[0,1,2]:
            raise ValueError('Unexpected surface light RGB destination')
        # Same per-light knee/ceiling as the skin trial, evaluated before shadow
        # so an occluded bright source does not change the compression factor.
        sequence=[emit(56,0x00100072,raw,*attenuation,0x06208246,*t[6:10]),
                  emit(52,*dest,0x0010000A,raw,0x0010001A,raw),
                  emit(52,*dest,*value,0x0010002A,raw)]
        if cap_profile=='color-aware':
            sequence += [emit(16,*extra_dest,0x00100246,raw,0x4002,
                              imm32(.212673)[1],imm32(.715152)[1],imm32(.072175)[1],0),
                         emit(0,*dest,*value,*extra),emit(56,*dest,*value,*imm32(.5))]
        sequence += [emit(0,*extra_dest,*value,*imm32(-.5)),
                     emit(52,*extra_dest,*extra,*imm32(0)),
                     emit(50,*dest,*extra,*imm32(2),*imm32(1)),
                     emit(14,*dest,*imm32(1),*value),
                     emit(50,*dest,*extra,*value,*imm32(.5)),
                     emit(0,*extra_dest,*extra,*imm32(.5)),
                     emit(14,*dest,*value,*extra)]
        before[i-1]=sequence
        after[i]=[emit(56,*t[1:3],0x00100E46,t[2],*value)]
    if len(before)!=expected_lights:
        raise ValueError(f'Expected {expected_lights} surface light reads, found {len(before)}')
    output=[]
    for i,t in enumerate(ins):
        output.extend(before.get(i,()))
        output.append(t)
        output.extend(after.get(i,()))
    return use_map_layer(encode_program(version,output),expected_lights=expected_lights,
                         early_reject=early_reject)
