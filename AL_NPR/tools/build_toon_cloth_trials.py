"""Pair the two tested skin trials with camera-key-independent cloth/cloth_alpha."""
import argparse
import hashlib
import struct
from pathlib import Path

from build_skin_assets import (SKIN, U32, blob_references, build_container, constant_buffer_register_count,
                              containers, index, load, parts, repack)
from build_toon_band_trials import band_color, LIT, LUMA
from patch_skin_light_shoulder import (decode_program, encode_program, emit, imm32, shoulder,
                                      SOURCE_XYZX, TEMP_XYZ)
from patch_skin_map_params import append_common_metadata, append_map_buffer
from patch_skin_sh_environment import redirect


def patch(code, individual, bright_fabric=False):
    ver,ins=decode_program(code)
    op=lambda t:t[0]&2047
    decl,=[i for i,t in enumerate(ins) if op(t)==104]
    h,total=ins[decl]
    rgb,sc,direction,key,ctr,ld=range(total+1,total+7)
    reads=[i for i,t in enumerate(ins) if op(t)==56 and len(t)==10 and
           t[5]&~0xff0==0x06208006 and t[6:8]==(1,256)]
    if len(reads) not in (4,12): raise ValueError("Expected two light reads per AL/Map-routed loop")
    stack,loops,ends=[],{},{}
    for i,t in enumerate(ins):
        if op(t)==48: stack.append(i)
        if i in reads: loops[i]=stack[-1]
        if op(t)==22: ends[stack.pop()]=i
    raw,lit=reads[2:4]
    start,end=loops[reads[0]],ends[loops[raw]]
    if loops[lit]!=loops[raw] or not start<reads[1]<raw<lit<end:
        raise ValueError("Unexpected Forward+ loop order")
    if any(op(t) in (13,62) for t in ins[decl+1:end]): raise ValueError("Side effect in lighting prefix")
    for i in reads[1:4:2]:
        if [op(x) for x in ins[i:i+3]]!=[56,56,16] or not ins[i+2][0]&8192:
            raise ValueError("Expected shadowed light followed by capped RGB and facing term")
    shadow,=[i-1 for i,t in enumerate(ins) if op(t)==52 and t[3:6]==(0x20801a,0,6)]
    if op(ins[shadow])!=55 or ins[shadow][5:7]!=imm32(1):
        raise ValueError("Old key shadow output not recognized")
    bands=[i for i,t in enumerate(ins[:start]) if op(t)==56 and t[0]&8192 and
           (t[-2:]==imm32(5) or (0x4002 in t and imm32(5)[1] in t and imm32(2.5)[1] in t))]
    if len(bands)!=2: raise ValueError("Expected primary and secondary cloth bands")
    if bright_fabric:
        # Reuse the cloth shader's own per-normal ambient probe and processed
        # fabric color. A white thread reflects more fill than a dark print.
        probe,=[i+10 for i in range(shadow-10) if [op(t) for t in ins[i:i+11]]==
                [17,17,17,56,17,17,17,56,50,50,0] and ins[i+10][1]==TEMP_XYZ]
        surface,=[i for i,t in enumerate(ins[:-2]) if t[0]&0x27ff==0x2036 and len(t)==5
                  and t[1] in (TEMP_XYZ,0x1000d2) and t[2]==t[4] and
                  [op(k) for k in ins[i+1:i+3]]==[50,50]]
        combine=ins[surface+2]
        if combine[4]!=ins[surface][2] or combine[1:3]!=(0x1000d2,combine[-1]):
            raise ValueError("Expected processed fabric RGB times irradiance")
    def facing_add(normal,light_dir):
        seq=[emit(16|8192,0x100082,sc,*normal,*light_dir),
             emit(56,TEMP_XYZ,rgb,SOURCE_XYZX,rgb,0x10003a,sc)]
        if individual: seq+=band_color(rgb,sc)
        # Only the specular/material direction uses a weighted vector. The band
        # is decided separately from the arriving RGB, so opposite lights add.
        return seq+[emit(16,0x100082,sc,SOURCE_XYZX,rgb,*LUMA),
                    emit(50,TEMP_XYZ,direction,*light_dir,0x10003a,sc,SOURCE_XYZX,direction),
                    emit(0,TEMP_XYZ,total,SOURCE_XYZX,total,SOURCE_XYZX,rgb)]
    xyz=lambda r:(SOURCE_XYZX,r)
    def reroute(i):
        t=ins[i]
        if i==shadow:return emit(54,*t[1:3],*imm32(1))
        if not (5 in t or 6 in t) or 0 not in t:return t
        return redirect(redirect(t,6,key),5,direction)
    result=ins[:decl]+[emit(89|0x800,0x00208e46,10,65),(h,ld+1),
        emit(54,TEMP_XYZ,total,*imm32(0)),emit(54,0x1000f2,key,*imm32(.1)),
        emit(54,0x1000f2,direction,0x4002,0,imm32(.0001)[1],0,0)]
    for i in range(decl+1,end+1):
        if i==start:
            # Use the same authored list as the skin, including a map sun if
            # URP placed it in the primary slot. The legacy skin trial has no
            # directional visibility; both materials still use punctual maps.
            result += [emit(54,0x100012,ctr,0x4001,0),
                       emit(84,0x100022,ctr,0x20800a,10,0,0x4001,32),
                       emit(48),emit(80,0x100082,ctr,0x10000a,ctr,0x10001a,ctr),
                       emit(3|0x40000,0x10003a,ctr),emit(41,0x100042,ctr,0x10000a,ctr,0x4001,1),
                       emit(54,TEMP_XYZ,ld,0x06208246,10,1,0x10002a,ctr),
                       emit(54,TEMP_XYZ,rgb,0x06208246,10,2,0x10002a,ctr),
                       *shoulder(rgb,sc,.1,7),*facing_add(ins[reads[1]+2][3:5],xyz(ld)),
                       emit(30,0x100012,ctr,0x10000a,ctr,0x4001,1),emit(22)]
        result.append(reroute(i))
        if i==start: result.append(emit(2))
        if i==raw:
            result += [emit(54,TEMP_XYZ,rgb,SOURCE_XYZX,ins[raw][2]),*shoulder(rgb,sc,.1,7)]
        if i==lit:
            result += [emit(56,TEMP_XYZ,rgb,SOURCE_XYZX,ins[lit][2],0x10000a,sc),
                       *facing_add(ins[lit+2][3:5],ins[lit+2][5:7])]
    if not individual: result+=band_color(total,sc)
    result += [*shoulder(total,sc,.18,4.5),emit(16,0x100082,total,*xyz(total),*LUMA),
               emit(56|8192,0x100082,total,0x10003a,total,*imm32(1/LIT)),
               emit(52,TEMP_XYZ,key,*xyz(total),*imm32(.015)),
               emit(16,0x100082,sc,*xyz(direction),*xyz(direction)),
               emit(49,0x100082,sc,0x10003a,sc,*imm32(1e-12)),
               emit(55,TEMP_XYZ,direction,0x10003a,sc,0x4002,0,imm32(1)[1],0,0,*xyz(direction)),
               emit(16,0x100082,sc,*xyz(direction),*xyz(direction)),emit(68,0x100082,sc,0x10003a,sc),
               emit(56,TEMP_XYZ,direction,*xyz(direction),0x10003a,sc)]
    for i in range(decl+1,len(ins)):
        t=ins[i]
        result.append(emit(54,*t[1:3],0x10003a,total) if i in bands else reroute(i))
        if bright_fabric and i==probe:
            result.extend([emit(16|8192,0x100012,ld,SOURCE_XYZX,t[2],*LUMA),
                           emit(50,0x100012,ld,0x10000a,ld,*imm32(1.20),*imm32(0)),
                           emit(50,0x100012,ld,0x10003a,total,*imm32(.70),0x10000a,ld)])
        if bright_fabric and i==surface+2:
            result.append(emit(50,*t[1:5],0x10000a,ld,*t[7:]))
        if i in loops.values():result.append(emit(2))
    return encode_program(ver,result)


def build(base, directory, mode, bright_fabric=False):
    bundle=load(base.read_bytes()).file
    asset,=bundle.files.values()
    skin,=load((directory/(mode+'.unity3d')).read_bytes()).file.files.values()
    for id in SKIN:asset.objects[id].set_raw_data(skin.objects[id].get_raw_data())
    # Old hair is intentionally left stock; this pair only replaces skin and fabric.
    cat=asset.objects[1]; catalog=cat.read_typetree()
    catalog['m_Container']=[row for row in catalog['m_Container'] if row[0]!='assets/al_npr/hair.shader']
    cat.save_typetree(catalog)
    for id in (131,136):
        obj=asset.objects[id];tree=obj.read_typetree();data,rows=index(tree); changes={}
        for slot,refs in blob_references(tree['m_ParsedForm']).items():
            if not any(p=='UniversalForward' and s=='progFragment' and '_FORWARD_PLUS' in k
                       and 'DOTS_INSTANCING_ON' not in k for _,_,p,s,k in refs):continue
            o,n,j=rows[slot];w=data[j][o:o+n];c,=containers(w,0,n);head=bytearray(w[:c.start])
            if head[-36]!=constant_buffer_register_count(c.code) or head[-36]>10:raise ValueError("CB binding range")
            head[-36]=11
            dx=build_container([(tag,patch(v,mode=='individual',bright_fabric) if tag==b'SHEX' else v)
                                for tag,v in parts(w[c.start:c.end])])
            at,=[i for i in range(0,c.start-3,4) if U32.unpack_from(head,i)[0]==c.end-i-4]
            U32.pack_into(head,at,len(head)+len(dx)-at-4)
            changes[slot]=head+dx+bytes((-(len(head)+len(dx)))%4)+w[(c.end+3)&~3:]
        if len(changes)!=320:raise ValueError("Missing cloth variants")
        selected,others=set(),set()
        for sub in tree['m_ParsedForm']['m_SubShaders']:
            for i,p in enumerate(sub['m_Passes']):
                matched=False
                for stage,g in p.items():
                    if not stage.startswith('prog'):continue
                    for programs,params in zip(g['m_PlayerSubPrograms'],g['m_ParameterBlobIndices'],strict=True):
                        for v,s in zip(programs,params,strict=True):
                            yes=stage=='progFragment' and v['m_BlobIndex'] in changes
                            (selected if yes else others).add(s)
                            matched|=yes
                if matched:sub['m_Passes'][i]=append_common_metadata(p,directionals=True)
        if len(selected)!={131:64,136:48}[id] or selected&others:raise ValueError("Shared binding tables")
        for slot in selected:
            o,n,j=rows[slot];changes[slot]=append_map_buffer(data[j][o:o+n],directionals=True)
        repack(tree,data,rows,changes);obj.save_typetree(tree)
    cab='CAB-'+hashlib.sha256(b''.join(asset.objects[i].data for i in (76,146,131,136))).hexdigest()[:32]
    bundle.files={cab:asset}
    path=directory/('paired-'+mode+('-bright' if bright_fabric else '')+'.unity3d')
    payload=bundle.save(packer='lz4')
    check=load(payload).file.files[cab]
    for i in (1,76,146,131,136):
        if check.objects[i].get_raw_data()!=asset.objects[i].data:raise ValueError(f"Repack mismatch at {i}")
    path.write_bytes(payload);print(path,flush=True)


def retune(directory,mode,gain):
    # Both constants live in one unique, consecutive MAD pair. Retune the
    # already validated program without re-emitting the long light traversal.
    src=directory/('paired-'+mode+'-bright.unity3d')
    bundle=load(src.read_bytes()).file;asset,=bundle.files.values()
    for id in (131,136):
        obj=asset.objects[id];tree=obj.read_typetree();data,rows=index(tree);changes={}
        for slot,refs in blob_references(tree['m_ParsedForm']).items():
            if not any(p=='UniversalForward' and s=='progFragment' and '_FORWARD_PLUS' in k
                       and 'DOTS_INSTANCING_ON' not in k for _,_,p,s,k in refs):continue
            o,n,j=rows[slot];w=data[j][o:o+n];c,=containers(w,0,n);code=c.code
            pos=code.find(struct.pack('<f',1.20));hits=[]
            while pos!=-1:
                if pos>=24:
                    ld=U32.unpack_from(code,pos-16)[0];total=ld-6
                    def pair(g):
                        words=(*emit(50,0x100012,ld,0x10000a,ld,*imm32(1.2*g),*imm32(0)),
                               *emit(50,0x100012,ld,0x10003a,total,*imm32(.70*g),0x10000a,ld))
                        return struct.pack('<18I',*words)
                    if total>=0 and code[pos-24:pos+48]==pair(1):hits.append((pos-24,pair(gain)))
                pos=code.find(struct.pack('<f',1.20),pos+4)
            if len(hits)!=1:raise ValueError(f"Unexpected fabric fill at {id}/{slot}")
            at,new=hits[0];changed=code[:at]+new+code[at+len(new):]
            dx=build_container([(tag,changed if tag==b'SHEX' else v) for tag,v in parts(w[c.start:c.end])])
            if len(dx)!=c.end-c.start:raise ValueError("Changed shader length")
            changes[slot]=w[:c.start]+dx+w[c.end:]
        if len(changes)!=320:raise ValueError("Expected all fabric variants")
        repack(tree,data,rows,changes);obj.save_typetree(tree)
    cab='CAB-'+hashlib.sha256(asset.objects[131].data+asset.objects[136].data).hexdigest()[:32]
    bundle.files={cab:asset};payload=bundle.save(packer='lz4')
    check=load(payload).file.files[cab]
    if any(check.objects[i].get_raw_data()!=asset.objects[i].data for i in (131,136)):raise ValueError("Repack mismatch")
    (directory/('paired-'+mode+'-soft.unity3d')).write_bytes(payload)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('base',type=Path);p.add_argument('directory',type=Path)
    p.add_argument('--bright-fabric',action='store_true')
    p.add_argument('--retune-fill',type=float,help='Scale the bright fabric contribution into a separate soft trial')
    args=p.parse_args()
    # Direct build and two-stage trial have identical serialized objects,
    # but different outer archive names.
    if hashlib.sha256(args.base.read_bytes()).hexdigest() not in (
        'eff057297a9860aa354b2c5c906e1876c3ed0f4f41345f63dc6e58f721595266',
        'e2639d68a0950dc05ff7eda1dff8ebed45ffa2c2e20ee179f3370640792344a1'):p.error("Unexpected cloth baseline")
    for mode in ('sum-first','individual'):
        if args.retune_fill is None:build(args.base,args.directory,mode,args.bright_fabric)
        elif 0<args.retune_fill<1:retune(args.directory,mode,args.retune_fill)
        else:p.error('Retuned fill must be between zero and one')
