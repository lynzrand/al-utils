"""Bend each light's band direction in the selected per-light skin/fabric pair."""
import argparse
import hashlib
from pathlib import Path

from build_skin_assets import U32, blob_references, build_container, containers, index, load, parts, repack
from build_toon_band_trials import LUMA
from patch_skin_light_shoulder import SOURCE_XYZX, TEMP_XYZ, decode_program, emit, encode_program, imm32


def patch(code):
    version, ins = decode_program(code)
    decl, = [i for i,t in enumerate(ins) if t[0]&2047 == 104]
    header, view = ins[decl]
    bent = view + 1
    # Match the facing dot at the two individual-band sites. No shadow, falloff,
    # or highlight directions are changed. v1 is the stock world-space position.
    sites = [i for i,t in enumerate(ins[:-2]) if t[0]&0x27ff == 0x2010 and
             ins[i+1][0]&2047 == 56 and ins[i+2][-5:] == LUMA and ins[i+2][0]&2047 == 16]
    if len(sites)!=2 or not any(t[0]&2047==0 and t[3:]==(0x101246,1,0x80208246,0x41,0,25) for t in ins):
        raise ValueError("Band sites or world-to-camera position unrecognized")
    def normalize(r):
        return [emit(16,0x100082,r,SOURCE_XYZX,r,SOURCE_XYZX,r),
                emit(52,0x100082,r,0x10003a,r,*imm32(1e-12)),
                emit(68,0x100082,r,0x10003a,r),
                emit(56,TEMP_XYZ,r,SOURCE_XYZX,r,0x10003a,r)]
    out=ins[:decl]+[(header,bent+1),
        emit(0,TEMP_XYZ,view,0x208246,0,25,0x80101246,0x41,1),*normalize(view)]
    for i,t in enumerate(ins[decl+1:],decl+1):
        if i in sites:
            light=t[5:7]
            # Stretch the camera-axis component of L. Its sign chooses the
            # hemisphere continuously, including exactly side-on lights.
            out += [emit(16,0x100082,bent,*light,SOURCE_XYZX,view),
                    emit(56,0x100082,bent,0x10003a,bent,*imm32(1.4)),
                    emit(50,TEMP_XYZ,bent,0x10003a,bent,SOURCE_XYZX,view,*light),*normalize(bent),
                    emit(16|8192,*t[1:5],SOURCE_XYZX,bent)]
        else: out.append(t)
    return encode_program(version,out)


def build(source,output):
    if source.resolve()==output.resolve():raise ValueError("Keep the original comparison bundle")
    bundle=load(source.read_bytes()).file;asset,=bundle.files.values()
    targets=(76,146,131,136)
    for id in targets:
        obj=asset.objects[id];tree=obj.read_typetree();data,rows=index(tree);changes={}
        for slot,refs in blob_references(tree['m_ParsedForm']).items():
            if not any(p=='UniversalForward' and s=='progFragment' and '_FORWARD_PLUS' in k
                       and 'DOTS_INSTANCING_ON' not in k for _,_,p,s,k in refs):continue
            o,n,j=rows[slot];w=data[j][o:o+n];c,=containers(w,0,n)
            dx=build_container([(tag,patch(v) if tag==b'SHEX' else v) for tag,v in parts(w[c.start:c.end])])
            head=bytearray(w[:c.start]);at,=[i for i in range(0,c.start-3,4) if U32.unpack_from(head,i)[0]==c.end-i-4]
            U32.pack_into(head,at,len(head)+len(dx)-at-4)
            changes[slot]=head+dx+bytes((-(len(head)+len(dx)))%4)+w[(c.end+3)&~3:]
        if len(changes)!=(64 if id in (76,146) else 320):raise ValueError("Incomplete variant coverage")
        repack(tree,data,rows,changes);obj.save_typetree(tree)
    cab='CAB-'+hashlib.sha256(b''.join(asset.objects[i].data for i in targets)).hexdigest()[:32]
    bundle.files={cab:asset};payload=bundle.save(packer='lz4');check=load(payload).file.files[cab]
    if any(check.objects[i].get_raw_data()!=asset.objects[i].data for i in targets):raise ValueError("Repack mismatch")
    output.write_bytes(payload)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('source',type=Path);p.add_argument('output',type=Path)
    args=p.parse_args();build(args.source,args.output)
