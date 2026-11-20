"""Read manifest stages from Unity or replace those stages with compiled Slang."""

import argparse
import hashlib
import json
from pathlib import Path
import struct
from tempfile import NamedTemporaryFile

from build_skin_assets import (
    ROW, SKIN, SOURCE, STOCK, SURFACES, U32, containers, copy_stock_shaders,
    file_sha, index, load, parts, repack,
)

from patch_skin_light_shoulder import decode_stage


MATERIALS = {76: "Face", 146: "Body", 129: "Hair", 131: "Cloth", 136: "ClothAlpha"}
MANIFEST = Path(__file__).resolve().parents[1] / "shaders/programs.json"


def manifest_stages(tree, material, manifest, stock):
    form = tree["m_ParsedForm"]
    subshader, = form["m_SubShaders"]
    for unity_pass in subshader["m_Passes"]:
        for stage, suffix in (("progVertex", "VS"), ("progFragment", "PS")):
            name = material + unity_pass["m_State"]["m_Name"] + suffix
            if name not in manifest:
                continue
            record = manifest[name]
            original = record.get("stock", {}) if stock else {}
            keywords = set(original.get("keywords", record["keywords"]))
            matches = [variant for group in unity_pass[stage]["m_PlayerSubPrograms"] for variant in group
                       if {form["m_KeywordNames"][i] for i in variant["m_KeywordIndices"]} == keywords]
            slots = {variant["m_BlobIndex"] for variant in matches}
            if len(slots) != 1:
                raise ValueError(f"{name}: expected one program for {sorted(keywords)}, found {slots}")
            yield name, slots.pop(), original.get("sha256", record["original"]), matches


def signature(chunk):
    count = U32.unpack_from(chunk)[0]
    fields = []
    for i in range(count):
        name, semantic, system, kind, register, mask = struct.unpack_from("<5IB", chunk, 8 + 24 * i)
        fields.append((chunk[name:chunk.index(0, name)].upper(), semantic, system, kind, register, mask))
    return sorted(fields)


def bindings(code):
    """Read texture dimensions/types, sampler modes and constant-buffer ranges."""
    declarations = {}
    _, instructions = decode_stage(code)
    for words in instructions:
        opcode = words[0] & 0x7ff
        if opcode in (88, 90):  # dcl_resource, dcl_sampler
            declarations[opcode, words[2]] = (words[0] & 0xfff800, *words[3:])
        elif opcode == 89:       # dcl_constantbuffer, indexed by slot then register count
            declarations[opcode, words[2]] = words[3]
        elif 156 <= opcode <= 162:
            raise ValueError("The Unity material has no UAV, raw or structured buffer bindings")
    return declarations


def replace_program(wrapper, info, compiled, name):
    original = dict(parts(wrapper[info.start:info.end]))
    updated = dict(parts(compiled))
    for tag in (b"ISGN", b"OSGN"):
        if signature(original[tag]) != signature(updated[tag]):
            raise ValueError(f"{name}: incompatible {tag.decode()} signature")
    if original[b"SHEX"][:4] != updated[b"SHEX"][:4]:
        raise ValueError(f"{name}: incompatible shader stage or model")
    layout = bindings(original[b"SHEX"])
    for key, value in bindings(updated[b"SHEX"]).items():
        if key not in layout or (value > layout[key] if key[0] == 89 else value != layout[key]):
            raise ValueError(f"{name}: resource {key} exceeds the Unity binding layout")
    header = bytearray(wrapper[:info.start])
    field, = [i for i in range(0, len(header) - 3, 4)
              if U32.unpack_from(header, i)[0] == info.end - i - 4]
    U32.pack_into(header, field, len(header) - field - 4 + len(compiled))
    return header + compiled + bytes((-(len(header) + len(compiled))) % 4) + wrapper[(info.end + 3) & ~3:]


def append_programs(tree, data, rows, additions):
    # Several permutations can point to one original blob. Give edited stages
    # their own slots so unrelated passes and keyword combinations keep theirs.
    index_end = 4 + len(rows) * ROW.size
    if any(segment == 0 and offset < index_end for offset, _, segment in rows):
        raise ValueError("Program overlaps the Unity program index")
    segment = len(data) - 1
    payload = bytearray(data[segment])
    for program in additions:
        rows.append((len(payload), len(program), segment))
        payload.extend(program)
    data[segment] = bytes(payload)
    growth = len(additions) * ROW.size
    data[0] = U32.pack(len(rows)) + data[0][4:index_end] + bytes(growth) + data[0][index_end:]
    rows = [(offset + growth if segment == 0 else offset, size, segment)
            for offset, size, segment in rows]
    repack(tree, data, rows, {})


def write_atomic(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile(dir=path.parent, delete=False) as f:
        temp = Path(f.name)
    try:
        temp.write_bytes(payload)
        temp.replace(path)
    finally:
        temp.unlink(missing_ok=True)


def stock_bundle():
    targets = {**SKIN, **SURFACES}
    bundle, asset, originals, _ = copy_stock_shaders(SOURCE, targets, "al-skin-lighting")
    for path_id, tree in originals.items():
        if path_id in targets:
            tree["m_ParsedForm"]["m_Name"] = targets[path_id] + "/Environment"
        asset.objects[path_id].save_typetree(tree)
    return bundle, asset, originals


def save_bundle(bundle, asset, output):
    identity = hashlib.sha256()
    for path_id in MATERIALS:
        identity.update(asset.objects[path_id].data)
    bundle.files = {"CAB-" + identity.hexdigest()[:32]: asset}
    write_atomic(output, bundle.save(packer="lz4"))


def build(args):
    manifest = json.loads(MANIFEST.read_text())
    stock = args.command != "bundle" or args.shading == "stock"
    extract = args.command == "stock-reference"
    if stock and file_sha(SOURCE) != STOCK:
        raise ValueError(f"Expected Amanatsu Location 1.0.4 assets at {SOURCE}")
    if args.command == "original-bundle":
        bundle, asset, _ = stock_bundle()
        save_bundle(bundle, asset, args.output)
        print(f"{args.output} (original game shaders)")
        return
    originals = {}
    if extract:
        asset = load(str(SOURCE)).file
    elif stock:
        bundle, asset, originals = stock_bundle()
    else:
        if not args.base or args.base.resolve() == args.output.resolve():
            raise ValueError("Specify a distinct NPR base bundle")
        bundle = load(args.base.read_bytes()).file
        asset, = bundle.files.values()

    seen = set()
    for path_id, material in MATERIALS.items():
        obj = asset.objects[path_id]
        # UnityPy reads the original stream when an object has pending edits.
        tree = originals[path_id] if originals else obj.read_typetree(check_read=not extract)
        data, rows = index(tree)
        additions = {}
        for name, slot, digest, variants in manifest_stages(tree, material, manifest, stock):
            offset, size, segment = rows[slot]
            wrapper = data[segment][offset:offset + size]
            info, = containers(wrapper, 0, size)
            if stock and hashlib.sha256(wrapper[info.start:info.end]).hexdigest() != digest:
                raise ValueError(f"{name}: unexpected stock program")
            if extract:
                write_atomic(args.output / (name + ".dxbc"), wrapper[info.start:info.end])
            else:
                binary = (args.programs / (name + ".dxbc")).read_bytes()
                replacement = replace_program(wrapper, info, binary, name)
                new_slot = additions.setdefault(bytes(replacement), len(rows) + len(additions))
                for variant in variants:
                    variant["m_BlobIndex"] = new_slot
            seen.add(name)
        if additions:
            append_programs(tree, data, rows, additions)
            obj.save_typetree(tree)
    if seen != manifest.keys():
        raise ValueError(f"Missing manifest stages: {sorted(manifest.keys() - seen)}")
    if not extract:
        save_bundle(bundle, asset, args.output)
    print(f"{args.output} ({len(seen)} stages)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    reference = commands.add_parser("stock-reference")
    reference.add_argument("output", type=Path)
    original = commands.add_parser("original-bundle")
    original.add_argument("output", type=Path)
    pack = commands.add_parser("bundle")
    pack.add_argument("output", type=Path)
    pack.add_argument("--programs", type=Path, required=True)
    pack.add_argument("--shading", choices=["stock", "npr"], required=True)
    pack.add_argument("--base", type=Path)
    build(parser.parse_args())
