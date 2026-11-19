"""Offline full light-traversal fusion for audited regular AL Forward+ programs.

Call on original stock code, before caps/routing/rejection. Three independent
RGB sums retain their own dot/MAD order, but attenuation and PCF execute once.
The caller must gate asset identities/keywords; structural validation is not
a replacement for GPU replay of newly accepted shader families.
"""

from collections import Counter

from patch_skin_light_shoulder import (
    decode_program, encode_program, emit, imm32, locate_mix,
    DECLARE_TEMPS, OPCODE_MASK, TEMP_XYZ, SOURCE_XYZX,
)
from patch_material_shadow_reject import validate_loops
from patch_early_shadow_reject import patch as validate_light_guards


def temp_operands(instruction):
    for index, token in enumerate(instruction[1:],1):
        if token & 0x7FFFF000 != 0x00100000:
            continue
        argument = index+1+int(bool(token & 0x80000000))
        if argument >= len(instruction):
            raise ValueError('Truncated temp operand')
        mode = token >> 2 & 3
        if mode == 0:
            channels = [c for c in range(4) if token & (16 << c)]
        elif mode == 2:
            channels = [token >> 4 & 3]
        elif mode == 1:
            channels = [token >> (4+2*c) & 3 for c in range(4)]
        else:
            raise ValueError('Unsupported temp addressing')
        yield index == 1 and mode == 0, {(instruction[argument],c) for c in channels}


def written_components(instructions):
    return set().union(*(components for t in instructions for destination,components in temp_operands(t)
                         if destination))


def check_liveouts(instructions,start,mix,allowed):
    killed,live = set(),set()
    for t in instructions[mix-1:]:
        if t[0] & OPCODE_MASK in (2,3,6,7,8,10,18,21,22,23,31,48,63,76):
            raise ValueError('Expected straight-line tail for live-out audit')
        operands = list(temp_operands(t))
        for destination,components in operands:
            if not destination:
                live |= components-killed
        for destination,components in operands:
            if destination:
                killed |= components
    if (live & written_components(instructions[start:mix-1]))-allowed:
        raise ValueError('Removed loops have additional live-outs')


def check_shadow_inputs(instructions,sites):
    """Check identical PCF sampling/control/input footprints under allocation.

    This permits reordered/repacked vector arithmetic introduced by allocation;
    it is a structural safeguard, not an arbitrary-program equivalence proof.
    """
    fingerprints=[]
    for i in sites:
        light=instructions[i]
        start=next(j for j in range(i-3,i-250,-1)
                   if instructions[j][0]&OPCODE_MASK==34
                   and instructions[j][3:]==(*light[8:10],0x4001,0)
                   and instructions[j+1][0]&OPCODE_MASK==27)
        region=instructions[start:i-2]
        operations=Counter(t[0]&OPCODE_MASK for t in region
                           if t[0]&OPCODE_MASK in (18,21,31,69,70,71,72,73,74))
        buffers=Counter()
        for t in region:
            for index,token in enumerate(t[1:],1):
                argument=index+1+int(bool(token&0x80000000))
                kind=token&0x7FFFF000
                if kind in (0x00208000,0x06208000):
                    buffers[(kind,*t[argument:argument+2])]+=1
                elif kind in (0x00107000,0x00106000):
                    buffers[(kind,t[argument])]+=1
        fingerprints.append((operations,buffers))
    if any(f!=fingerprints[0] for f in fingerprints):
        raise ValueError('Different PCF sampling/control or resource inputs')


def locate_fused_mix(instructions):
    """Locate the private-accumulator ADD/MAD, independent of an adjacent loop.

    Returns the MAD index and destination RGB register, like locate_mix. This
    locator expects the original unmodified post-mix tail; apply it before caps.
    """
    matches=[]
    for i,t in enumerate(instructions):
        if (i<1 or len(t)!=12 or t[0]&OPCODE_MASK!=50 or t[1]!=TEMP_XYZ
                or t[3:5]!=(SOURCE_XYZX,t[2])
                or t[5:10]!=(0x4002,0x3F000000,0x3F000000,0x3F000000,0)
                or t[-2]!=SOURCE_XYZX):
            continue
        previous=instructions[i-1]
        if (len(previous)==8 and previous[0]&OPCODE_MASK==0
                and previous[1:3]==t[1:3] and previous[3:5]==(0x80100246,0x41)
                and previous[5]==t[-1] and previous[6]==SOURCE_XYZX
                and previous[7]==previous[5]+1):
            # Both private sums must be initialized once with literal zero.
            private=(previous[5],previous[7])
            for register in private:
                initializers=[j for j,q in enumerate(instructions[:i-1])
                              if q[0]&OPCODE_MASK==54 and q[1:]==(TEMP_XYZ,register,0x4001,0)]
                if len(initializers)!=1:
                    break
            else:
                matches.append((i,t[2]))
    if len(matches)!=1:
        raise ValueError(f'Expected unique fused mix, found {len(matches)}')
    return matches[0]


def patch_program(code):
    validate_loops(code)
    validate_light_guards(code)  # Validate layer/index/attenuation relationships; discard its rewrite.
    version,ins=decode_program(code)
    mix,rgb=locate_mix(ins)
    sites=[i for i,t in enumerate(ins) if len(t)==10 and t[0]&OPCODE_MASK==56
           and t[5]&~0xFF0==0x06208006 and t[6:8]==(1,256)]
    if len(sites)!=6:
        raise ValueError('Expected six stock light loops')
    check_shadow_inputs(ins,sites)
    stack,owners,ends=[],{},{}
    for i,t in enumerate(ins):
        if t[0]&OPCODE_MASK==48:
            stack.append(i)
        elif t[0]&OPCODE_MASK==22:
            ends[stack.pop()]=i
        if stack:
            owners[i]=stack[-1]
    loops=[owners[i] for i in sites]
    start,remove=loops[0]-2,loops[2]-2
    if ends[loops[-1]]!=mix-2:
        raise ValueError('Unexpected final loop/mix relationship')
    for loop in loops[::2]:
        if any(ins[loop-j][0]&OPCODE_MASK!=54 or ins[loop-j][-1]!=0 for j in (1,2)):
            raise ValueError('Directional accumulators must start at zero')
        if ins[loop+1][0]&OPCODE_MASK!=80 or ins[loop+1][-2:]!=ins[loops[0]+1][-2:]:
            raise ValueError('Different directional light count')
    for loop in loops[1::2]:
        if any(ins[loop-j][0]&OPCODE_MASK!=54 for j in range(1,6)):
            raise ValueError('Unexpected cluster descriptor initialization')
        if [ins[loop-j][3:] for j in range(2,6)] != [ins[loops[1]-j][3:] for j in range(2,6)]:
            raise ValueError('Different clustered-light descriptor inputs')
    normal=ins[sites[2]+1][3:5]
    if normal[0]!=SOURCE_XYZX:
        raise ValueError('Expected XYZ later normal')
    if {(normal[1],c) for c in range(3)} & written_components(ins[start:mix-1]):
        raise ValueError('Later normal is modified after first traversal starts')
    fade=ins[sites[0]-3][3:5]
    if any(ins[i-3][0]&OPCODE_MASK!=50 or ins[i-3][3:5]!=fade for i in sites):
        raise ValueError('Different per-light shadow fade')
    if fade[0]&0xFFFFFFCF!=0x0010000A:
        raise ValueError('Expected scalar temp shadow fade')
    if (fade[1],fade[0]>>4&3) in written_components(ins[start:mix-1]):
        raise ValueError('Shadow fade is modified between traversals')
    declaration,=[i for i,t in enumerate(ins) if t[0]&OPCODE_MASK==DECLARE_TEMPS]
    header,lambert=ins[declaration]
    wrapped,scratch=lambert+1,lambert+2
    before={start:[emit(54,TEMP_XYZ,lambert,*imm32(0)),emit(54,TEMP_XYZ,wrapped,*imm32(0))]}
    for first,second,third in zip(sites[:2],sites[2:4],sites[4:]):
        first_dot,second_dot,third_dot=ins[first+1],ins[second+1],ins[third+1]
        if (any(t[0]&OPCODE_MASK!=16 or not t[0]&0x2000 for t in (first_dot,second_dot))
                or third_dot[0]&OPCODE_MASK!=16 or third_dot[0]&0x2000
                or second_dot[3:5]!=normal or third_dot[5:7]!=normal
                or ins[third+2][0]&OPCODE_MASK!=50
                or ins[third+2][-4:]!=(*imm32(.5),*imm32(.5))):
            raise ValueError('Unexpected three-lobe response')
        light=ins[first]
        channels=[c for c in range(4) if light[1] & (16<<c)]
        if len(channels)!=3:
            raise ValueError('Unexpected light RGB channels')
        color=(0x00100006|sum(c<<(4+2*n) for n,c in enumerate(channels+channels[:1])),light[2])
        gate=ins[first-2]
        component=((gate[1]>>4)&15).bit_length()-1
        mask=(0x00100006|(component*0x55<<4),gate[2])
        direction=first_dot[5:7]
        before[first+1]=[
            emit(16|0x2000,0x00100082,scratch,*normal,*direction),
            emit(50,TEMP_XYZ,scratch,*color,0x00100FF6,scratch,SOURCE_XYZX,lambert),
            emit(55,TEMP_XYZ,lambert,*mask,SOURCE_XYZX,scratch,SOURCE_XYZX,lambert),
            emit(16,0x00100082,scratch,*direction,*normal),
            emit(50,0x00100082,scratch,0x0010003A,scratch,*imm32(.5),*imm32(.5)),
            emit(50,TEMP_XYZ,scratch,0x00100FF6,scratch,*color,SOURCE_XYZX,wrapped),
            emit(55,TEMP_XYZ,wrapped,*mask,SOURCE_XYZX,scratch,SOURCE_XYZX,wrapped),
        ]
    allowed=written_components([ins[ends[loops[3]]-1],ins[ends[loops[5]]-1]])
    check_liveouts(ins,remove,mix,allowed)
    ins[declaration]=(header,lambert+3)
    ins[mix-1]=emit(0,TEMP_XYZ,rgb,0x80100246,0x41,lambert,SOURCE_XYZX,wrapped)
    ins[mix]=(*ins[mix][:-2],SOURCE_XYZX,lambert)
    result=[]
    for i,t in enumerate(ins):
        if remove<=i<=mix-2:
            continue
        result.extend(before.get(i,()))
        result.append(t)
    locate_fused_mix(result)
    return encode_program(version,result)
