"""Standalone cb10 authored-direction seed for full-fused AL skin shaders.

Apply after full fusion and SH/environment light shoulders. The existing three
accumulators are seeded inside a valid flag branch; inactive input executes no
new lighting arithmetic. No material/SH/palette operations are replaced.

cb10[0]: toward-light direction.xyz, valid.w
cb10[1]: pipeline finalColor.rgb, unused.w
cb10[2].x: optional same-source shadow enable, ignored without shadow_source

shadow_source, when supplied, is an already saved per-fragment temp operand.
The caller must prove its lifetime and same-light identity. It is NOT a global
shadow attenuation scalar; cb10[2].x selects that saved result versus one.
"""

from patch_skin_light_shoulder import (
    decode_program, encode_program, emit, imm32, DECLARE_TEMPS, OPCODE_MASK,
    TEMP_XYZ, SOURCE_XYZX,
)
from patch_al_full_light_fusion import locate_fused_mix


def patch_program(code, *, shadow_source=None):
    version,ins=decode_program(code)
    for t in ins:
        for i,token in enumerate(t[1:],1):
            if token&0x7FFFF000==0x00208000:
                argument=i+1+int(bool(token&0x80000000))
                if t[argument:argument+2] in ((0,5),(0,6)):
                    raise ValueError('Apply the SH/environment patch before authored-direction seeding')
    mix,_=locate_fused_mix(ins)
    lambert,wrapped=ins[mix-1][5],ins[mix-1][7]
    # The first injected fusion kernel retains both its later-normal responses
    # and the original first-normal dot immediately afterward.
    selections=[i for i,t in enumerate(ins) if t[0]&OPCODE_MASK==55
                and t[1:3]==(TEMP_XYZ,lambert)]
    if len(selections)!=2:
        raise ValueError('Expected two full-fusion Lambert update sites')
    first=selections[0]
    kernel=ins[first-2:first+8]
    if [t[0]&OPCODE_MASK for t in kernel] != [16,50,55,16,50,50,55,16,50,55]:
        raise ValueError('Unexpected full-fusion response instruction sequence')
    if kernel[6][1:3]!=(TEMP_XYZ,wrapped):
        raise ValueError('Unexpected wrapped accumulator')
    normal=kernel[0][3:5]
    first_normal=kernel[7][3:5]
    original_mask,original_accumulator=kernel[9][1:3]
    if any(t[0]&OPCODE_MASK!=16 or not t[0]&0x2000 for t in (kernel[0],kernel[7])):
        raise ValueError('Expected saturated first and later Lambert dots')
    if normal[0]!=SOURCE_XYZX or first_normal[0]!=SOURCE_XYZX:
        raise ValueError('Expected ordinary XYZ normal operands')
    initializers=[]
    for register,mask in ((lambert,TEMP_XYZ),(wrapped,TEMP_XYZ),(original_accumulator,original_mask)):
        matches=[i for i,t in enumerate(ins[:first]) if t[0]&OPCODE_MASK==54
                 and t[1:3]==(mask,register)
                 and (t[3:]==(0x4001,0) or t[3:]==(0x4002,0,0,0,0))]
        if len(matches)!=1:
            raise ValueError('Expected one zero initializer for each accumulator')
        initializers.append(matches[0])
    insertion=max(initializers)+1
    if max(initializers)-min(initializers)!=2:
        raise ValueError('Expected adjacent private/private/original initializers')
    if any(t[0]&OPCODE_MASK in (31,48,55) for t in ins[min(initializers):insertion]):
        raise ValueError('Accumulator initialization is not unconditional')
    declaration,=[i for i,t in enumerate(ins) if t[0]&OPCODE_MASK==DECLARE_TEMPS]
    header,light=ins[declaration]
    direction=light+1
    if any(t[0]&OPCODE_MASK==89 and t[2]==10 for t in ins):
        raise ValueError('cb10 is already declared')
    if shadow_source is not None:
        if (len(shadow_source)!=2 or shadow_source[0]&0xFFFFFFCF!=0x0010000A
                or not 0<=shadow_source[1]<light):
            raise ValueError('Expected an existing scalar temp shadow operand')
    ins[declaration]=(header,light+2)
    color=(SOURCE_XYZX,light)
    scalar=(0x0010003A,light)
    scalar_dest=(0x00100082,light)
    emitted=[
        emit(31|0x40000,0x0020803A,10,0),
        emit(54,TEMP_XYZ,light,0x00208246,10,1),
        emit(52,*scalar_dest,0x0010000A,light,0x0010001A,light),
        emit(52,*scalar_dest,*scalar,0x0010002A,light),
        emit(0,*scalar_dest,*scalar,*imm32(-.10)),
        emit(52,*scalar_dest,*scalar,*imm32(0)),
        emit(50,*scalar_dest,*scalar,*imm32(7),*imm32(1)),
        emit(14,*scalar_dest,*imm32(1),*scalar),
        emit(56,TEMP_XYZ,light,*color,*scalar),
    ]
    if shadow_source is not None:
        emitted += [emit(55,*scalar_dest,0x0020800A,10,2,*shadow_source,*imm32(1)),
                    emit(56,TEMP_XYZ,light,*color,*scalar)]
    emitted += [
        emit(54,TEMP_XYZ,direction,0x00208246,10,0),
        emit(16,0x00100082,direction,SOURCE_XYZX,direction,SOURCE_XYZX,direction),
        emit(52,0x00100082,direction,0x0010003A,direction,*imm32(1e-20)),
        emit(68,0x00100082,direction,0x0010003A,direction),
        emit(56,TEMP_XYZ,direction,SOURCE_XYZX,direction,0x0010003A,direction),
    ]
    def add_response(mask,register,response_normal,wrapped_response):
        channels=[c for c in range(4) if mask&(16<<c)]
        if len(channels)!=3:
            raise ValueError('Expected three-component accumulator')
        mapping={channel:n for n,channel in enumerate(channels)}
        swizzle=0x00100006|sum(mapping.get(c,0)<<(4+2*c) for c in range(4))
        if wrapped_response:
            emitted.append(emit(16,*scalar_dest,SOURCE_XYZX,direction,*response_normal))
            emitted.append(emit(50,*scalar_dest,*scalar,*imm32(.5),*imm32(.5)))
            emitted.append(emit(50,mask,register,0x00100FF6,light,swizzle,light,0x00100E46,register))
        else:
            emitted.append(emit(16|0x2000,*scalar_dest,*response_normal,SOURCE_XYZX,direction))
            emitted.append(emit(50,mask,register,swizzle,light,0x00100FF6,light,0x00100E46,register))
    add_response(original_mask,original_accumulator,first_normal,False)
    add_response(TEMP_XYZ,lambert,normal,False)
    add_response(TEMP_XYZ,wrapped,normal,True)
    emitted.append(emit(21))
    result=[]
    for i,t in enumerate(ins):
        if i==insertion:
            result.extend(emitted)
        if i==declaration:
            result.append(emit(89,0x00208E46,10,3))
        result.append(t)
    return encode_program(version,result)
