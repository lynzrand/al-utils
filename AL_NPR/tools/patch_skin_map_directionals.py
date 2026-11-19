"""Experimental uniform authored directional list for full-fused AL skin.

Apply last, after SH shoulders, early rejection and both map-layer gates. The
clustered punctual loop remains byte-identical. The optional main-shadow mode
retains the stock main atlas filter and applies it only to its matching entry.
ALMapLighting b10: raw uint count in [0].x, then 32 direction/color float4 pairs.
In main-shadow mode [0].y enables the filter and the owning color.w is nonzero.
"""
from patch_skin_light_shoulder import decode_program, encode_program, emit, TEMP_XYZ, SOURCE_XYZX
from patch_skin_authored_direction import patch_program as seed_direction
from patch_al_full_light_fusion import locate_fused_mix


def light_loops(ins):
    mix, _ = locate_fused_mix(ins)
    lambert = ins[mix - 1][5]
    selections = [i for i,t in enumerate(ins) if t[0]&2047 == 55 and t[1:3] == (TEMP_XYZ,lambert)]
    if len(selections) != 2:
        raise ValueError('Expected fused directional and punctual response sites')
    stack, owners, ends = [], {}, {}
    for i,t in enumerate(ins):
        op = t[0]&2047
        if op == 48: stack.append(i)
        if stack: owners[i] = stack[-1]
        if op == 22: ends[stack.pop()] = i
    if stack: raise ValueError('Unclosed loop')
    loops = [(owners[i], ends[owners[i]]) for i in selections]
    if loops[0][1] >= loops[1][0]: raise ValueError('Light loops overlap')
    start,end = loops[0]
    if (ins[start+1][0]&2047 != 80 or ins[start+2][0]&2047 != 3
            or not ins[start+2][0]&0x40000):
        raise ValueError('Expected bounded stock directional loop')
    if ins[end-1][0]&2047 != 30 or ins[end-1][-2:] != (0x4001,1):
        raise ValueError('Expected directional index increment')
    if ins[start-1][0]&2047 != 54 or ins[start-1][-2:] != (0x4001,0):
        raise ValueError('Expected directional index initializer')
    compare, stop, increment, initialize = ins[start+1], ins[start+2], ins[end-1], ins[start-1]
    def scalar_source(destination):
        mask = destination[0] >> 4 & 15
        if mask not in (1,2,4,8): raise ValueError('Expected scalar loop state')
        return (0x0010000A | ((mask.bit_length()-1) << 4), destination[1])
    if (increment[1:3] != initialize[1:3]
            or increment[3:5] != scalar_source(initialize[1:3])
            or compare[3:5] != increment[3:5]
            or stop[1:3] != scalar_source(compare[1:3])):
        raise ValueError('Directional zero-iteration state is not the audited iterator/predicate')
    # The audited loop may contain PCF conditionals but no nested traversals,
    # texture writes, discard or return. The three response accumulators are
    # initialized outside it, including in the zero-directional stock case.
    if any(t[0]&2047 in (48,62,13,164,165,166) for t in ins[start+1:end]):
        raise ValueError('Unexpected directional side effect/nested traversal')
    return loops


def patch_program(code, *, main_shadow=False):
    version, baseline = decode_program(code)
    loops = light_loops(baseline)
    punctual = baseline[loops[1][0]:loops[1][1]+1]
    # Reuse the proven per-light shoulder and three response emission. A raster
    # build already contains the seed and its retained main-shadow source.
    # Private temps avoid touching loop state.
    _, ins = decode_program(code if main_shadow else seed_direction(code))
    (start,end), _ = light_loops(ins)
    # Preserve the zero-iteration loop's exit predicate as well as its existing
    # zero index initializer. This retains the stock zero-directional live-outs
    # rather than assuming every directional scratch register is dead afterward.
    ins[start:end+1] = [emit(54,*ins[start+1][1:3],0x4001,0xffffffff)]
    branch, = [i for i,t in enumerate(ins) if t == emit(31|0x40000,0x0020803A,10,0)]
    finish = next(i for i in range(branch+1,len(ins)) if ins[i][0]&2047 == 21)
    body = ins[branch+1:finish]
    if any(t[0]&2047 in (31,48,22) for t in body):
        raise ValueError('Seed response must be straight-line')
    decl, = [i for i,t in enumerate(ins) if t[0]&2047 == 104]
    header, counter = ins[decl]
    ins[decl] = (header,counter+1)
    cb, = [i for i,t in enumerate(ins) if t[0]&2047 == 89 and t[2] == 10]
    if ins[cb][3] != 3: raise ValueError('Unexpected seed buffer size')
    ins[cb] = emit(89|0x800,0x00208E46,10,65)
    reads = []
    for i,t in enumerate(body):
        if t[0]&2047 == 54 and t[3:6] in ((0x00208246,10,0),(0x00208246,10,1)):
            slot = 1 if t[5] == 0 else 2
            body[i] = emit(54,*t[1:3],0x06208246,10,slot,0x0010002A,counter)
            reads.append(slot)
    if sorted(reads) != [1,2]: raise ValueError('Expected exactly direction and color reads')
    if main_shadow:
        # The stock filter runs once per fragment when header.y is nonzero.
        # color.w identifies the one list entry owning that atlas; other
        # authored directionals must never inherit a different light's shadow.
        filters = [i for i,t in enumerate(ins) if t == emit(31|0x40000,0x0020800A,10,2)]
        if len(filters) != 1: raise ValueError('Expected one retained main shadow filter')
        ins[filters[0]] = emit(31|0x40000,0x0020801A,10,0)
        selectors = [i for i,t in enumerate(body) if t[0]&2047 == 55 and t[3:6] == (0x0020800A,10,2)]
        if len(selectors) != 1: raise ValueError('Expected one main shadow response selector')
        i = selectors[0]
        body[i] = emit(55,*body[i][1:3],0x0620803A,10,2,0x0010002A,counter,*body[i][6:])
    # x=index, y=bounded count, z=2*index, w=termination comparison.
    replacement = [emit(54,0x00100012,counter,0x4001,0),
        emit(84,0x00100022,counter,0x0020800A,10,0,0x4001,32),
        emit(48),emit(80,0x00100082,counter,0x0010000A,counter,0x0010001A,counter),
        emit(3|0x40000,0x0010003A,counter),
        emit(41,0x00100042,counter,0x0010000A,counter,0x4001,1),
        *body,emit(30,0x00100012,counter,0x0010000A,counter,0x4001,1),emit(22)]
    ins[branch:finish+1] = replacement
    # All original instructions outside the removed directional loop and the
    # new private declaration/seed are retained; assert punctual bytes directly.
    matches = [i for i in range(len(ins)-len(punctual)+1) if ins[i:i+len(punctual)] == punctual]
    if len(matches) != 1: raise ValueError('Punctual loop was not retained exactly')
    return encode_program(version,ins)
