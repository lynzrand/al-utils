"""Compile handwritten material functions and bind them into Unity's original SM5 programs."""
from pathlib import Path
import subprocess
import tempfile

from build_material_response import find_fxc
from build_skin_assets import parts
from patch_skin_light_shoulder import decode_program, emit


def compile_entry(source, entry, defines=()):
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / (entry + ".cso")
        options = ["/D" + name + "=1" for name in defines]
        subprocess.run([find_fxc(), "/nologo", "/O3", "/T", "ps_5_0", "/E", entry,
                        *options, "/Fo", path, source], check=True)
        _, instructions = decode_program(dict(parts(path.read_bytes()))[b"SHEX"])
    decl, = [i for i, t in enumerate(instructions) if t[0] & 2047 == 104]
    if instructions[-1] != emit(62):
        raise ValueError("Expected a single pixel shader return")
    return instructions[decl][1], instructions[decl+1:-1]


def bind_entry(program, inputs, output, scratch, resources=None):
    """Map the compiled SM5 entry's inputs, output and resource slots."""
    result = []
    for t in program:
        args = []
        i = 1
        if t[0] & 0x80000000:
            while t[i-1] & 0x80000000:
                args.append(t[i])
                i += 1
        while i < len(t):
            token = t[i]
            if token in (0x4001, 0x4002):
                size = 2 if token == 0x4001 else 5
                args.extend(t[i:i+size])
                i += size
                continue
            extra = int(bool(token & 0x80000000))
            kind = (token >> 12) & 255
            idx = t[i+1+extra]
            if kind == 0:
                reg = idx + scratch
            elif kind == 1:
                reg = inputs[idx]
            elif kind in (6, 7):
                args.extend([token, resources[kind, idx] if resources is not None else idx])
                i += 2
                continue
            elif kind == 2 and idx == 0 and i == 1 and token in (0x102012, 0x102072):
                reg = output
            else:
                raise ValueError(f"Unexpected compiled entry operand {token:#x}")
            args.extend([token & ~0xff000, *t[i+1:i+1+extra], reg])
            i += 2 + extra
        result.append(emit(t[0] & 0x80ffffff, *args))
    return result
