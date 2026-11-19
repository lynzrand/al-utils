"""Opt-in depth-matched uint2 visibility for the authored directional list.

Apply after patch_skin_map_directionals. Reuses the now-unused main shadow SRV
slot, with new uint return type/name. Gate off and rejected samples leave the
original list arithmetic intact; all changes use private temporaries.
"""
import struct
from patch_skin_light_shoulder import decode_program, encode_program, emit, imm32

NAME = '_ALDirectionalVisibility'


def depth_match(sample, position, coord, state):
    """Bound resolved MSAA depth by the fragment's half-pixel depth footprint.

    A depth resolve can select another sample inside the same raster pixel.
    Exact bit equality rejects that surface on sloped triangles. The derivative
    bound covers sample offsets within half a pixel on each axis, plus a small
    relative float-rounding allowance. Different surfaces inside that interval
    remain ambiguous; this is not a receiver-ID test.
    """
    x, y, z = (0x0010000A, coord), (0x0010001A, coord), (0x0010002A, coord)
    return [
        emit(11, 0x00100012, coord, *position),
        emit(12, 0x00100022, coord, *position),
        emit(56, 0x00100042, coord, *x, *imm32(-1)),
        emit(52, 0x00100012, coord, *x, *z),
        emit(56, 0x00100042, coord, *y, *imm32(-1)),
        emit(52, 0x00100022, coord, *y, *z),
        emit(0, 0x00100012, coord, *x, *y),
        emit(56, 0x00100012, coord, *x, *imm32(.5)),
        emit(50, 0x00100012, coord, *position, *imm32(2**-20), *x),
        emit(56, 0x00100042, coord, *position, *imm32(-1)),
        emit(0, 0x00100022, coord, 0x0010001A, sample, *z),
        emit(56, 0x00100042, coord, *y, *imm32(-1)),
        emit(52, 0x00100022, coord, *y, *z),
        emit(29, 0x00100042, state, *x, *y),
    ]


def position_signature(data):
    count,offset = struct.unpack_from('<II',data)
    if offset != 8 or len(data) < 8+24*count:
        raise ValueError('Expected ordinary ISGN input signature')
    candidates = []
    for i in range(count):
        pos = 8+24*i
        name,index,system,kind,register = struct.unpack_from('<5I',data,pos)
        end = data.find(b'\0',name)
        if name >= len(data) or end < name: raise ValueError('Invalid signature name')
        if data[name:end].upper() == b'SV_POSITION':
            if index != 0 or system != 1 or kind != 3 or data[pos+20] != 15:
                raise ValueError('Unsupported SV_Position signature')
            candidates.append((pos,register))
    if len(candidates) != 1: raise ValueError('Expected unique SV_Position')
    pos,register = candidates[0]
    result = bytearray(data)
    result[pos+21] |= 4  # SV_Position.z becomes a live input.
    return register,bytes(result)


def patch_program(code, signature, texture_slot):
    position,signature = position_signature(signature)
    version,ins = decode_program(code)
    resource, = [i for i,t in enumerate(ins) if t[0]&2047 == 88 and t[2] == texture_slot]
    if ins[resource] != (0x04001858,0x00107000,texture_slot,0x5555):
        raise ValueError('Expected stock float Texture2D declaration')
    for i,t in enumerate(ins):
        if i == resource: continue
        if any(token&0x7FFFF000 == 0x00107000 and t[j+1] == texture_slot
               for j,token in enumerate(t[:-1])):
            raise ValueError('Removed main shadow texture still has executable readers')
    ins[resource] = (0x04001858,0x00107000,texture_slot,0x4444)
    input_decl, = [i for i,t in enumerate(ins) if t[0]&2047 == 100 and t[2:] == (position,1)]
    if ins[input_decl][1] != 0x00101032:
        raise ValueError('Expected stock SV_Position.xy declaration')
    ins[input_decl] = (ins[input_decl][0],0x00101072,position,1)
    declaration, = [i for i,t in enumerate(ins) if t[0]&2047 == 104]
    header,coord = ins[declaration]; sample,state = coord+1,coord+2
    ins[declaration] = (header,coord+3)
    bounded, = [i for i,t in enumerate(ins) if t[0]&2047 == 84
                and t[3:] == (0x0020800A,10,0,0x4001,32)]
    counter = ins[bounded][2]
    if ins[bounded-1] != emit(54,0x00100012,counter,0x4001,0):
        raise ValueError('Unexpected authored list initializer')
    loop = bounded+1
    if [t[0]&2047 for t in ins[loop:loop+4]] != [48,80,3,41]:
        raise ValueError('Unexpected authored directional header')
    end = next(i for i in range(loop+1,len(ins)) if ins[i][0]&2047 == 22)
    if ins[end-1] != emit(30,0x00100012,counter,0x0010000A,counter,0x4001,1):
        raise ValueError('Unexpected authored directional increment')
    # One load per fragment, not per light. Check the resolved receiver against
    # this fragment's depth footprint before using any directional mask bits.
    before = [
        emit(54,0x00100012,state,0x4001,0),
        emit(31|0x40000,0x0020801A,10,0),
        emit(54,0x001000F2,coord,0x4001,0),
        emit(28,0x00100032,coord,0x00101046,position),
        emit(79,0x00100032,sample,0x00100046,coord,0x00208AE6,10,0),
        emit(1,0x00100042,state,0x0010000A,sample,0x0010001A,sample),
        emit(31|0x40000,0x0010002A,state),
        # Extended LD tokens mirror FXC's Texture2D<uint2>.Load(int3) encoding.
        emit(45|0x80000000,0x800000C2,0x00111103,0x00100032,sample,
             0x00100E46,coord,0x00107E46,texture_slot),
        *depth_match(sample, (0x0010102A, position), coord, state),
        emit(55,0x00100012,state,0x0010002A,state,0x0010000A,sample,0x4001,0),
        emit(21),emit(21),
    ]
    gate = [emit(85,0x00100022,state,0x0010000A,state,0x0010000A,counter),
            emit(1,0x00100022,state,0x0010001A,state,0x4001,1),
            emit(31,0x0010001A,state)]  # if_z: unoccluded executes stock response.
    result=[]
    for i,t in enumerate(ins):
        if i == bounded-1: result.extend(before)
        if i == loop+4: result.extend(gate)
        if i == end-1: result.append(emit(21))
        result.append(t)
    return encode_program(version,result),signature
