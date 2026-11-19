"""Ask D3D11 WARP to create every modified Forward+ pixel program from the saved bundle."""
import ctypes as c
from pathlib import Path
import sys
from build_skin_assets import blob_references, containers, index, load

v=c.c_void_p
device,context=v(),v()
hr=c.WinDLL("d3d11").D3D11CreateDevice(None,5,None,0,None,0,7,c.byref(device),None,c.byref(context))
if hr:raise RuntimeError(f"D3D11CreateDevice: {hr:#x}")
def method(ptr,slot,rt,*args):
    table=c.cast(ptr,c.POINTER(c.POINTER(v))).contents
    return c.WINFUNCTYPE(rt,v,*args)(table[slot])
create=method(device,15,c.c_long,v,c.c_size_t,v,c.POINTER(v))
for arg in sys.argv[1:]:
    path=Path(arg)
    asset,=load(str(path)).file.files.values()
    targets = [76,146,131,136] if 131 in asset.objects else [76,146]
    if any(row[0] == "assets/al_npr/hair.shader" for row in asset.objects[1].read_typetree()["m_Container"]):
        targets.append(129)
    for id in targets:
        t=asset.objects[id].read_typetree();d,r=index(t);count=0
        prepass = set()
        if id == 129:
            base = t["m_ParsedForm"]["m_SubShaders"][0]["m_Passes"][0]
            if base["m_State"]["m_Name"] != "ExtraPrePass":
                raise ValueError("Expected a hair base color pass")
            prepass = {program["m_BlobIndex"] for variants in base["progFragment"]["m_PlayerSubPrograms"]
                       for program in variants}
        for slot,refs in blob_references(t['m_ParsedForm']).items():
            if slot not in prepass and not any(k=='UniversalForward' and s=='progFragment' and '_FORWARD_PLUS' in kw
                       and 'DOTS_INSTANCING_ON' not in kw for _,_,k,s,kw in refs):continue
            o,n,j=r[slot];w=d[j][o:o+n];e,=containers(w,0,n);b=w[e.start:e.end];obj=v()
            hr=create(device,b,len(b),None,c.byref(obj))
            if hr:raise RuntimeError(f"{path}/{id}/{slot}: {hr:#x}")
            method(obj,2,c.c_ulong)(obj);count+=1
        if count!={76:64,146:64,129:128+len(prepass),131:320,136:320}[id]:raise RuntimeError(f"Unexpected count: {count}")
        print(path.name,id,count,flush=True)
