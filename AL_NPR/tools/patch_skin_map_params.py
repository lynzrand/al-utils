"""Bounded decoder/append experiment for AL's 202012090 parameter blobs.

No asset publication or runtime changes. Only explicitly decoded record forms
are accepted; every untouched blob must round-trip byte-identically.
"""

import copy
import struct


class Reader:
    def __init__(self,data):
        self.data=data
        self.position=0

    def integer(self):
        if self.position+4>len(self.data):
            raise ValueError('Truncated integer')
        value,=struct.unpack_from('<I',self.data,self.position)
        self.position+=4
        return value

    def count(self):
        value=self.integer()
        if value>4096:
            raise ValueError('Record count exceeds audited bound')
        return value

    def string(self):
        size=self.integer()
        if size>4096 or self.position+size>len(self.data):
            raise ValueError(f'Invalid string at {self.position-4}')
        value=self.data[self.position:self.position+size].decode('utf-8')
        self.position+=size
        end=(self.position+3)&~3
        if any(self.data[self.position:end]):
            raise ValueError('Nonzero string padding')
        self.position=end
        return value


def decode(data):
    r=Reader(data)
    version=r.integer()
    if version!=202012090:
        raise ValueError('Unsupported parameter format')
    buffers=[]
    for _ in range(r.count()):
        name,size=r.string(),r.integer()
        parameters=[]
        for _ in range(r.count()):
            parameters.append(dict(name=r.string(),fields=[r.integer() for _ in range(6)]))
        structs=[]
        for _ in range(r.count()):
            struct_name=r.string()
            fields=[r.integer() for _ in range(3)]
            members=[dict(name=r.string(),fields=[r.integer() for _ in range(6)])
                     for _ in range(r.count())]
            structs.append(dict(name=struct_name,fields=fields,parameters=members))
        buffers.append(dict(name=name,size=size,parameters=parameters,structs=structs))
    bindings=[]
    for _ in range(r.count()):
        name,kind=r.string(),r.integer()
        if kind not in (0,1):
            raise ValueError(f'Unsupported binding {name} kind {kind}')
        bindings.append(dict(name=name,kind=kind,fields=[r.integer() for _ in range(3 if kind==0 else 2)]))
    if r.position!=len(data):
        raise ValueError(f'Trailing bytes: {len(data)-r.position}')
    return dict(version=version,buffers=buffers,bindings=bindings)


def encode(document):
    out=bytearray()
    def integer(value):out.extend(struct.pack('<I',value))
    def string(value):
        raw=value.encode('utf-8')
        integer(len(raw));out.extend(raw)
        out.extend(bytes((-len(out))%4))
    integer(document['version']);integer(len(document['buffers']))
    for buffer in document['buffers']:
        string(buffer['name']);integer(buffer['size']);integer(len(buffer['parameters']))
        for parameter in buffer['parameters']:
            string(parameter['name'])
            for value in parameter['fields']:integer(value)
        integer(len(buffer['structs']))
        for item in buffer['structs']:
            string(item['name'])
            for value in item['fields']:integer(value)
            integer(len(item['parameters']))
            for parameter in item['parameters']:
                string(parameter['name'])
                for value in parameter['fields']:integer(value)
    integer(len(document['bindings']))
    for binding in document['bindings']:
        string(binding['name']);integer(binding['kind'])
        for value in binding['fields']:integer(value)
    return bytes(out)


def append_map_buffer(data, *, directionals=False, ray_visibility=False):
    original=decode(data)
    if encode(original)!=data:
        raise ValueError('Original parameter blob did not round-trip')
    document=copy.deepcopy(original)
    if any(b['name']=='ALMapLighting' for b in document['buffers']+document['bindings']):
        raise ValueError('Map buffer already declared')
    if any(b['kind']==1 and b['fields'][0]==10 for b in document['bindings']):
        raise ValueError('Constant-buffer slot10 occupied')
    # The common pass owns parameter names and offsets. A variant contributes
    # only its binding and buffer header, as the original layouts do.
    document['buffers'].append(dict(name='ALMapLighting',size=1040 if directionals else 48,structs=[],parameters=[]))
    document['bindings'].append(dict(name='ALMapLighting',kind=1,fields=[10,0]))
    if ray_visibility:
        if not directionals: raise ValueError('Visibility requires authored directional list')
        texture, = [b for b in document['bindings'] if b['name']=='_MainLightShadowmapTexture']
        if texture['kind']!=0 or texture['fields'] not in ([13,0xffffffff,4],[14,0xffffffff,4]):
            raise ValueError('Unexpected main-shadow texture binding')
        texture['name']='_ALDirectionalVisibility'
    output=encode(document)
    if encode(decode(output))!=output:
        raise ValueError('Appended parameter blob did not round-trip')
    check=decode(output)
    check['buffers'].pop();check['bindings'].pop()
    if ray_visibility:
        texture, = [b for b in check['bindings'] if b['name']=='_ALDirectionalVisibility']
        texture['name']='_MainLightShadowmapTexture'
    if encode(check)!=data:
        raise ValueError('Existing parameter data changed')
    return output


def append_common_metadata(shader_pass, *, directionals=False, ray_visibility=False):
    """Return independent pass metadata with the matching named buffer contract.

    This does not update parameter blobs or executable code. Those are separate
    required pieces. m_NameIndices values are pass-local, not fixed identifiers.
    """
    result=copy.deepcopy(shader_pass)
    names=result['m_NameIndices']
    additions=(['ALMapLighting','_ALMapDirectionalData'] if directionals else
               ['ALMapLighting','_ALMapDirection','_ALMapColor','_ALMapSource'])
    if ray_visibility:
        if not directionals: raise ValueError('Visibility requires authored directional list')
        additions.append('_ALDirectionalVisibility')
    if any(name in additions for name,_ in names):
        raise ValueError('Map metadata already present')
    base=max(index for _,index in names)+1
    names.extend((name,base+i) for i,name in enumerate(additions))
    names.sort(key=lambda entry: entry[0])
    common=result['progFragment']['m_CommonParameters']
    if any(b['m_Index']==10 for b in common['m_ConstantBufferBindings']):
        raise ValueError('Common slot10 already occupied')
    vectors = ([dict(m_NameIndex=base+1,m_Index=0,m_ArraySize=65,m_Type=0,m_Dim=4)]
               if directionals else [
            dict(m_NameIndex=base+i+1,m_Index=i*16,m_ArraySize=0,m_Type=0,m_Dim=4)
            for i in range(3)])
    common['m_ConstantBuffers'].append(dict(
        m_NameIndex=base,m_MatrixParams=[],m_VectorParams=vectors,
        m_StructParams=[],m_Size=1040 if directionals else 48,m_IsPartialCB=True))
    return result


def main():
    import argparse
    import ctypes
    import hashlib
    import json
    from pathlib import Path
    import sys
    root=Path(__file__).resolve().parents[2]
    sys.path[:0]=[str(root/'artifacts/static/deps'),str(root/'AL_Performance/tools')]
    from map_shader_bytecode import load,segments,U32,ROW
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    affinity=ctypes.windll.kernel32.SetProcessAffinityMask
    affinity.argtypes=[ctypes.c_void_p,ctypes.c_size_t]
    if not affinity(ctypes.c_void_p(-1),0x0FFF):
        raise OSError('Could not reserve user CPU cores')
    args.output.mkdir(parents=True,exist_ok=True)
    env=load(str(args.source))
    report=[]
    for path_id in (76,146):
        shader=next(o for o in env.objects if o.path_id==path_id and o.type.name=='Shader').read_typetree()
        form=shader['m_ParsedForm'];shader_pass=form['m_SubShaders'][0]['m_Passes'][1]
        if dict(shader_pass['m_State']['m_Tags']['tags']).get('LIGHTMODE')!='UniversalForward':
            raise ValueError('Unexpected audited pass')
        program=shader_pass['progFragment']
        player=program['m_PlayerSubPrograms'][3]
        parameters=program['m_ParameterBlobIndices'][3]
        if len(player)!=len(parameters):
            raise ValueError('Parameter/program reference counts differ')
        selected=[]
        for item,slot in zip(player,parameters):
            keywords=[form['m_KeywordNames'][i] for i in item['m_KeywordIndices']]
            if '_FORWARD_PLUS' in keywords and 'DOTS_INSTANCING_ON' not in keywords:
                selected.append(slot)
        if len(selected)!=64:
            raise ValueError('Expected64 regular variants per skin shader')
        data=segments(shader,0);count=U32.unpack_from(data[0])[0]
        rows=list(ROW.iter_unpack(data[0][4:4+count*ROW.size]))
        for slot in sorted(set(selected)):
            offset,size,segment=rows[slot];raw=data[segment][offset:offset+size]
            decoded=decode(raw)
            if encode(decoded)!=raw:
                raise ValueError('Nonidentical untouched round trip')
            patched=append_map_buffer(raw)
            prefix=args.output/f'{path_id}-{slot}'
            prefix.with_suffix('.original.bin').write_bytes(raw)
            prefix.with_suffix('.appended.bin').write_bytes(patched)
            prefix.with_suffix('.json').write_text(json.dumps(decode(patched),indent=2))
            report.append(dict(path_id=path_id,slot=slot,variant_references=selected.count(slot),
                               original_sha256=hashlib.sha256(raw).hexdigest(),
                               appended_sha256=hashlib.sha256(patched).hexdigest(),
                               original_bytes=len(raw),appended_bytes=len(patched),
                               roundtrip_exact=True,existing_records_unchanged=True))
        metadata=append_common_metadata(shader_pass)
        (args.output/f'{path_id}-pass-metadata.json').write_text(json.dumps(metadata,indent=2))
    (args.output/'validation.json').write_text(json.dumps(dict(
        scope='Binary/metadata only. No DXBC declaration, bundle repack, Unity binding or GPU validation.',
        parameter_blobs=report),indent=2))
    print(f'Exact round trips and append checks: {len(report)} blobs, {sum(x["variant_references"] for x in report)} variants')


if __name__=='__main__':
    main()
