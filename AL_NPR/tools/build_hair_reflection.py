"""Bind each map light's stylized specular lobe into the stock hair palette."""
import argparse
from copy import deepcopy
import hashlib
from pathlib import Path

from compiled_material_entry import bind_entry, compile_entry
from build_skin_assets import (WORKSPACE, U32, ROW, attach_map_parameters, blob_references,
                               build_container, constant_buffer_register_count, containers,
                               index, load, parts, repack)
from patch_skin_light_shoulder import SOURCE_XYZX, TEMP_XYZ, decode_program, emit, encode_program, imm32, shoulder

BASE = "55564e271bcd3feb5b1f9105a83ebed4cd9bbe70184e97d7217896d2481e9271"
X, Y, Z, W = (0x10000a + 16 * i for i in range(4))
DX, DY, DZ, DW = (0x100002 + (16 << i) for i in range(4))


def patch(code, entries, style, specular_only=False):
    lobe, diffuse, finish = entries
    version, ins = decode_program(code)
    ops = [t[0] & 2047 for t in ins]
    decl = ops.index(104)
    first = ins[decl][1]
    normal, tangent, light, view, rgb, total, value, ctr, mask, uv, dx, dy, gain, scratch = range(first, first+14)
    xyz = lambda r: (SOURCE_XYZX, r)
    def unit(reg):
        return [emit(16, DX, value, *xyz(reg), *xyz(reg)), emit(52, DX, value, X, value, *imm32(1e-8)),
                emit(68, DX, value, X, value), emit(56, TEMP_XYZ, reg, *xyz(reg), X, value)]
    def accumulate():
        return [*bind_entry(lobe[1], [normal, tangent, light, view, uv, dx, dy], value, scratch),
                emit(50, TEMP_XYZ, total, *xyz(rgb), X, value, *xyz(total))]

    reads = [i for i,t in enumerate(ins) if ops[i] == 56 and len(t) == 10 and
             t[5] & ~0xff0 == 0x06208006 and t[6:8] == (1,256)]
    if len(reads) not in (4,12):
        raise ValueError("Unrecognized hair light traversal")
    raw_reads = set(reads[::2])
    capped_reads = {item + 1 for item in reads[1::2]}
    lit = reads[3]
    if ops[lit:lit+3] != [56,56,16] or ins[lit][1] != TEMP_XYZ or ins[lit+2][5] != SOURCE_XYZX:
        raise ValueError("Expected shadowed punctual RGB followed by facing")
    # Unity already selects perspective or orthographic V for this pixel.
    view_site, = [i for i in range(decl+1, reads[0]) if ops[i] == 55 and ins[i-1][-2:] == (0,72)]
    t = ins[view_site]
    masks = {TEMP_XYZ: SOURCE_XYZX, 0x1000e2: 0x100396}
    view_src = masks[t[1]], t[2]
    sample = lambda resource: next(i for i,t in enumerate(ins) if ops[i] == 69 and
                                    any(t[j] >> 12 & 0xffff == 0x107 and t[j+1] == resource
                                        for j in range(1,len(t)-1)))
    painted, detail = sample(1), sample(4)
    material = ins[painted+1][4]
    if ins[painted+1][3:6] != (0x208246,material,11):
        raise ValueError("Hair highlight color binding changed")
    texture_token = next(j for j in range(3,len(ins[detail])-1) if ins[detail][j] >> 12 & 0xffff == 0x107 and ins[detail][j+1] == 4)
    lanes = [i for i in range(4) if ins[detail][3] & (16 << i) and (ins[detail][texture_token] >> (4 + 2*i)) & 3 == 0]
    detail_lane, = lanes
    final, = [i for i,t in enumerate(ins) if ops[i] == 50 and t[1] == 0x102072]
    result = []
    for i,t in enumerate(ins):
        if i == decl:
            result.extend([emit(89|0x800,0x208e46,10,65), (t[0],scratch+max(entry[0] for entry in entries))])
            continue
        if i == final:
            # Same stock HDR output and alpha coverage, with the scene specular
            # added after the painted palette. Bound overlapping colored lamps.
            result.extend([emit(50,TEMP_XYZ,light,*t[3:]),
                           emit(54,DW,total,X,mask),emit(54,0x1000f2,rgb,0x208e46,material,11),
                           *bind_entry(finish[1],[total,rgb],value,scratch)])
            if specular_only:
                result.append(emit(54,*t[1:3],*xyz(value)))
            else:
                result.append(emit(0,*t[1:3],*xyz(value),*xyz(light)))
            continue
        if i in capped_reads:
            # Save the old shadowed RGB for the independent specular response
            # before replacing the palette's compression with its diffuse cap.
            if i == lit + 1:
                result.append(emit(56,TEMP_XYZ,rgb,*t[3:]))
            result.append(emit(56,*t[1:5],X,gain))
        else:
            result.append(t)
        if i in raw_reads:
            result.extend(bind_entry(diffuse[1],[t[2]],gain,scratch))
        if i == view_site:
            if style == "painted":
                result.extend([emit(54,0x100032,uv,0x101046,6), emit(11,0x100032,dx,0x100046,uv),
                               emit(12,0x100032,dy,0x100046,uv)])
            result.extend([emit(54,TEMP_XYZ,view,*view_src), emit(54,TEMP_XYZ,normal,0x101246,2),
                           *unit(normal),emit(54,TEMP_XYZ,tangent,0x101246,3),
                           emit(16,DX,value,*xyz(tangent),*xyz(normal)),
                           emit(50,TEMP_XYZ,tangent,0x80100246,0x41,normal,X,value,*xyz(tangent)),
                           *unit(tangent),emit(54,TEMP_XYZ,total,*imm32(0)),
                           emit(54,DX,ctr,0x4001,0),emit(84,DY,ctr,0x20800a,10,0,0x4001,32),
                           emit(48),emit(80,DW,ctr,X,ctr,Y,ctr),emit(3|0x40000,W,ctr),
                           emit(41,DZ,ctr,X,ctr,0x4001,1),
                           emit(54,TEMP_XYZ,light,0x06208246,10,1,Z,ctr),
                           emit(54,TEMP_XYZ,rgb,0x06208246,10,2,Z,ctr),
                           *shoulder(rgb,value,.5,1.2), *accumulate(),
                           emit(30,DX,ctr,X,ctr,0x4001,1),emit(22)])
        if i == painted:
            result.append(emit(56,*t[3:5],0x100e46,t[4],*imm32(.26 if style == "painted" else .22)))
        if i == lit+1:
            result.extend([emit(54,TEMP_XYZ,light,*ins[lit+2][5:7]),*accumulate()])
        if i == detail:
            result.append(emit(54,DX,mask,X+16*detail_lane,t[4]))
    return encode_program(version,result)


def prepass_blob(blob):
    container, = containers(blob, 0, len(blob))
    version, ins = decode_program(container.code)
    # The underlying color pass uses the binary dither coverage. The forward
    # overlay additionally limits alpha by UnityPerMaterial[21].y.
    caps = [i for i,t in enumerate(ins) if t[0] & 0x27ff == 0x2036 and
            t[3] == 0x20801a and t[-1] == 21 and
            ins[i+1][0] & 2047 == 52 and ins[i+1][-2:] == imm32(.01)]
    at, = caps
    ins[at] = emit(54,*ins[at][1:3],*imm32(1))
    code = encode_program(version, ins)
    dx = build_container([(tag,code if tag == b"SHEX" else v) for tag,v in parts(blob[container.start:container.end])])
    head = bytearray(blob[:container.start])
    pos, = [i for i in range(0,len(head)-3,4) if U32.unpack_from(head,i)[0] == container.end-i-4]
    U32.pack_into(head,pos,len(head)+len(dx)-pos-4)
    return head + dx + bytes((-(len(head)+len(dx)))%4) + blob[(container.end+3)&~3:]


def pair_color_passes(tree, data, rows, changes):
    # Both hair passes draw the same geometry. Preserve the base pass state
    # and its opaque dither, and bind the same clustered-light inputs in both.
    passes, = [s["m_Passes"] for s in tree["m_ParsedForm"]["m_SubShaders"]]
    base, forward = passes[:2]
    if [p["m_State"]["m_Name"] for p in (base,forward)] != ["ExtraPrePass","Forward"]:
        raise ValueError("Unexpected hair color passes")
    clone = deepcopy(forward)
    clone["m_State"] = base["m_State"]
    clone["m_Tags"] = base["m_Tags"]
    passes[0] = clone
    locations = {}
    additions = bytearray()
    segment = len(data)-1
    for variants in clone["progFragment"]["m_PlayerSubPrograms"]:
        for program in variants:
            old = program["m_BlobIndex"]
            if old not in locations:
                offset, size, seg = rows[old]
                blob = changes.get(old,data[seg][offset:offset+size])
                new = prepass_blob(blob)
                locations[old] = len(rows)
                rows.append((len(data[segment])+len(additions),len(new),segment))
                additions.extend(new)
            program["m_BlobIndex"] = locations[old]
    if len(locations) != 192 or any(seg == 0 for _,_,seg in rows):
        raise ValueError("Unexpected hair program table layout")
    data[segment] += additions
    old_count = U32.unpack_from(data[0])[0]
    if len(data[0]) != 4 + old_count * ROW.size:
        raise ValueError("Unexpected program index padding")
    data[0] = U32.pack(len(rows)) + data[0][4:] + bytes((len(rows)-old_count)*ROW.size)


def build(source, output, style, specular_only=False):
    if source.resolve() == output.resolve():
        raise ValueError("Keep the approved skin and cloth baseline")
    payload = source.read_bytes()
    if hashlib.sha256(payload).hexdigest() != BASE:
        raise ValueError("Expected the tested normal-bend skin and cloth bundle")
    bundle = load(payload).file
    asset, = bundle.files.values()
    shader = asset.objects[129]
    tree = shader.read_typetree()
    data, rows = index(tree)
    changes = {}
    defines = {"ribbon": ("HAIR_RIBBON",), "painted": ("HAIR_PAINTED",), "gloss": ()}
    path = WORKSPACE / "AL_NPR/shaders/HairReflection.hlsl"
    entries = (compile_entry(path,"HairReflection",defines[style]),
               compile_entry(path,"HairDiffuseGain"), compile_entry(path,"HairFinish"))
    for slot, refs in blob_references(tree["m_ParsedForm"]).items():
        if not any(p == "UniversalForward" and s == "progFragment" and "_FORWARD_PLUS" in k
                   and "DOTS_INSTANCING_ON" not in k for _,_,p,s,k in refs):
            continue
        offset, size, segment = rows[slot]
        blob = data[segment][offset:offset+size]
        c, = containers(blob,0,size)
        header = bytearray(blob[:c.start])
        if header[-36] != constant_buffer_register_count(c.code) or header[-36] > 10:
            raise ValueError("Unexpected hair constant buffer range")
        header[-36] = 11
        dx = build_container([(tag,patch(v,entries,style,specular_only) if tag == b"SHEX" else v) for tag,v in parts(blob[c.start:c.end])])
        pos, = [i for i in range(0,c.start-3,4) if U32.unpack_from(header,i)[0] == c.end-i-4]
        U32.pack_into(header,pos,len(header)+len(dx)-pos-4)
        changes[slot] = header + dx + bytes((-(len(header)+len(dx)))%4) + blob[(c.end+3)&~3:]
    if len(changes) != 128:
        raise ValueError("Incomplete hair variant coverage")
    attach_map_parameters(tree,data,rows,changes,directionals=True,expected_tables=16)
    pair_color_passes(tree,data,rows,changes)
    repack(tree,data,rows,changes)
    shader.save_typetree(tree)
    catalog = asset.objects[1].read_typetree()
    record = deepcopy(catalog["m_Container"][0][1])
    record["asset"]["m_PathID"] = 129
    catalog["m_Container"].append(("assets/al_npr/hair.shader",record))
    asset.objects[1].save_typetree(catalog)
    cab = "CAB-" + hashlib.sha256(payload[:64] + shader.data).hexdigest()[:32]
    bundle.files = {cab:asset}
    output.write_bytes(bundle.save(packer="lz4"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source",type=Path)
    parser.add_argument("output",type=Path)
    parser.add_argument("--style",choices=("gloss","ribbon","painted"),default="painted")
    parser.add_argument("--specular-only", action="store_true", help="Show just the new hair reflection in the existing draw")
    args = parser.parse_args()
    build(args.source,args.output,args.style,args.specular_only)
