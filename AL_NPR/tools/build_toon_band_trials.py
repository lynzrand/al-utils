"""Build two skin-only band-order trials from the measured map000 runtime bundle."""
import argparse
import hashlib
from pathlib import Path

from build_skin_assets import SKIN, U32, blob_references, containers, index, load, repack
from patch_al_full_light_fusion import locate_fused_mix
from patch_skin_light_shoulder import (SOURCE_XYZX, TEMP_XYZ, build_container,
    decode_program, emit, encode_program, imm32, parts, shoulder)


BASE = "6276d7d13594b9919688d06c88dd00f976f36ce64ee5ceeb1bc88577e03feba7"
LUMA = (0x4002, *(imm32(x)[1] for x in (.212673, .715152, .072175, 0)))
LIT = .18  # The original aggregate cap's neutral knee.


def band_color(rgb, scratch):
    # Scale all three channels together. A fully lit neutral reaches LIT;
    # unlike a per-channel step, this preserves warm and cool sources.
    x, y = (0x10000a, scratch), (0x10001a, scratch)
    dx, dy = (0x100012, scratch), (0x100022, scratch)
    return [emit(16, *dx, SOURCE_XYZX, rgb, *LUMA),
            emit(50 | 0x2000, *dy, *x, *imm32(25), *imm32(-1)),  # 0.04..0.08
            emit(56, *dy, *y, *imm32(LIT)),
            emit(52, *dx, *x, *imm32(1e-6)),
            emit(14, *dy, *y, *x),
            emit(56, TEMP_XYZ, rgb, SOURCE_XYZX, rgb, *y)]


def patch(code, name, individual):
    version, ins = decode_program(code)
    op = lambda t: t[0] & 2047
    decl, = [i for i,t in enumerate(ins) if op(t) == 104]
    header, total = ins[decl]
    scratch, contribution = total + 1, total + 2
    mix, rgb = locate_fused_mix(ins)
    lambert = ins[mix-1][5]
    direct, = [i for i,t in enumerate(ins) if op(t)==50 and t[1:3]==(TEMP_XYZ,lambert)]
    local, = [i for i,t in enumerate(ins) if op(t)==55 and t[1:3]==(TEMP_XYZ,lambert)]
    loops, stack = {}, []
    for i,t in enumerate(ins):
        if op(t)==48: stack.append(i)
        if i in (direct,local): loops[i]=[stack[-1]]
        if op(t)==22:
            begin=stack.pop()
            for pair in loops.values():
                if pair==[begin]: pair.append(i)
    end=loops[local][1]
    bands=[i for i,t in enumerate(ins[:direct]) if op(t)==56 and t[0]&0x2000
           and t[-2:]==imm32(5) and ins[i-1][-2:]==imm32(-.05)]
    if len(bands)!=(1 if name==76 else 2) or not bands[-1]<loops[direct][0]<direct<local<end<mix:
        raise ValueError("Unexpected palette or light-loop ordering")
    if [op(t) for t in ins[mix+1:mix+8]] != [52,52,0,52,50,14,56] or ins[mix+3][-2:]!=imm32(-.18) or ins[mix+5][-4:]!=(*imm32(4.5),*imm32(1)):
        raise ValueError("Expected the current bundle's aggregate shoulder")
    # The original material needs its band before the Forward+ traversal.
    # Evaluate its input prefix once to collect light, then replay the material
    # with the result in a private register. Skip both light loops on replay.
    # This comparison prioritizes identical sampling over instruction count.
    prefix=[]
    for i in range(decl+1,end+1):
        t=ins[i]
        if op(t) in (13,62) or t[1:2] and (t[1]&0xfffff000)==0x00102000:
            raise ValueError("Unexpected side effect in evaluation prefix")
        if individual and i in (direct,local-1):
            if op(t)!=50 or ins[i-1][0]&0x27ff!=0x2010 or t[-1]!=lambert:
                raise ValueError("Expected capped, shadowed RGB times facing term")
            prefix += [emit(56,TEMP_XYZ,contribution,*t[3:7]),
                       *band_color(contribution,scratch),
                       emit(0,*t[1:3],SOURCE_XYZX,contribution,*t[7:])]
        else:
            prefix.append(t)
    prefix.append(emit(54,TEMP_XYZ,total,SOURCE_XYZX,lambert))
    if not individual: prefix.extend(band_color(total,scratch))
    prefix.extend(shoulder(total,scratch,.18,4.5))
    prefix.extend([emit(16,0x100082,total,SOURCE_XYZX,total,*LUMA),
                   emit(56|0x2000,0x100082,total,0x10003a,total,*imm32(1/LIT))])
    late=ins[end+1:end+3]
    if op(late[0])!=16 or op(late[1])!=50 or not late[1][0]&0x2000:
        raise ValueError("Unrecognized original extra-light brightness mix")
    result=ins[:decl]+[(header,contribution+1)]+prefix
    for i,t in enumerate(ins[decl+1:],decl+1):
        if i in bands or i==end+2:
            result.append(emit(54,*t[1:3],0x10003a,total))
        elif i==mix:
            # The merged hue has already passed through the aggregate shoulder.
            result.append(emit(54,TEMP_XYZ,rgb,SOURCE_XYZX,total))
        elif mix<i<=mix+7:
            continue
        else:
            result.append(t)
        if i in (loops[direct][0],loops[local][0]):
            result.append(emit(2))  # Zero iterations in the palette evaluation.
    return encode_program(version,result)


def build(source, output, individual):
    bundle=load(source.read_bytes()).file
    asset,=bundle.files.values()
    verified={}
    for shader in SKIN:
        obj=asset.objects[shader]
        tree=obj.read_typetree()
        data,rows=index(tree)
        changes={}
        for slot,refs in blob_references(tree["m_ParsedForm"]).items():
            if not any(p=="UniversalForward" and s=="progFragment" and "_FORWARD_PLUS" in k
                       and "DOTS_INSTANCING_ON" not in k for _,_,p,s,k in refs): continue
            o,n,seg=rows[slot]
            w=data[seg][o:o+n]
            c,=containers(w,0,n)
            old=w[c.start:c.end]
            new=build_container([(t,patch(v,shader,individual) if t==b'SHEX' else v) for t,v in parts(old)])
            hdr=bytearray(w[:c.start])
            at,=[i for i in range(0,c.start-3,4) if U32.unpack_from(hdr,i)[0]==c.end-i-4]
            U32.pack_into(hdr,at,len(hdr)+len(new)-at-4)
            changes[slot]=hdr+new+bytes((-(len(hdr)+len(new)))%4)+w[(c.end+3)&~3:]
        if len(changes)!=64: raise ValueError("Incomplete skin variant coverage")
        verified[shader]=(data,rows,changes)
        repack(tree,data,rows,changes)
        obj.save_typetree(tree)
    cab="CAB-"+hashlib.sha256(b''.join(asset.objects[i].data for i in SKIN)).hexdigest()[:32]
    bundle.files={cab:asset}
    payload=bundle.save(packer="lz4")
    check=load(payload).file.files[cab]
    for shader,(old,rows,changes) in verified.items():
        data,new_rows=index(check.objects[shader].read_typetree())
        for i,((o,n,s),(a,b,c)) in enumerate(zip(rows,new_rows,strict=True)):
            if data[c][a:a+b]!=changes.get(i,old[s][o:o+n]):
                raise ValueError(f"Round-trip mismatch: {shader}/{i}")
    output.write_bytes(payload)
    print(output,hashlib.sha256(payload).hexdigest(),flush=True)


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path)
    p.add_argument("directory",type=Path)
    args=p.parse_args()
    if hashlib.sha256(args.source.read_bytes()).hexdigest()!=BASE: p.error("Unexpected baseline")
    args.directory.mkdir(parents=True,exist_ok=True)
    for mode in ("sum-first","individual"):
        dest=args.directory/(mode+".unity3d")
        if dest.resolve()==args.source.resolve(): p.error("Refusing to overwrite baseline")
        build(args.source,dest,mode=="individual")
