"""Prepare or apply the Windows release delta for Amanatsu Location 1.0.4."""
import argparse
import ctypes as ct
import hashlib
import json
from pathlib import Path
import tempfile
from zipfile import ZipFile, ZIP_DEFLATED

from attrs import evolve
import lz4.block
import UnityPy


STOCK = "c11860706e6666da0718c2e4b7d97af5b5808a003806ca289387eeb4ba8a93aa"
SHADERS = (76, 80, 100, 129, 131, 136, 146, 153)


class Input(ct.Structure):
    _fields_ = [("data", ct.c_char_p), ("size", ct.c_size_t), ("editable", ct.c_int)]

    @classmethod
    def buffer(cls, data):
        return cls(data, len(data), False)


class Output(ct.Structure):
    _fields_ = [("data", ct.c_void_p), ("size", ct.c_size_t)]


def delta(source, payload, create):
    dll = ct.WinDLL("msdelta", use_last_error=True)
    output = Output()
    args = (Input.buffer(source), Input.buffer(payload))
    if create:
        ok = dll.CreateDeltaB(ct.c_int64(1), ct.c_int64(0), ct.c_int64(0), *args,
                              Input(), Input(), Input(), None, 0, ct.byref(output))
    else:
        ok = dll.ApplyDeltaB(ct.c_int64(0), *args, ct.byref(output))
    if not ok:
        raise ct.WinError(ct.get_last_error())
    try:
        return ct.string_at(output.data, output.size)
    finally:
        dll.DeltaFree(ct.c_void_p(output.data))


def stock_inputs(game):
    source = game / "AmanatsuLocation_Data/globalgamemanagers.assets"
    if hashlib.sha256(source.read_bytes()).hexdigest() != STOCK:
        raise ValueError("This patch requires the Amanatsu Location 1.0.4 game assets.")
    stock = UnityPy.load(str(source)).file
    maps = UnityPy.load(str(game / "lib/ma/pre/sc/000_08/02.unity3d")).file
    shader_type = maps.files["BuildPlayer-map002.sharedAssets"].objects[206].serialized_type
    template = UnityPy.load(str(game / "lib/ma/te/c/000_08/00.unity3d")).file
    asset = next(f for f in template.files.values() if hasattr(f, "objects"))
    catalog = asset.objects[1]
    asset.types = [catalog.serialized_type, shader_type]
    catalog.type_id = 0
    asset.objects = {1: catalog}
    asset.externals = [stock.externals[0]]
    programs = {}
    for key in SHADERS:
        obj = stock.objects[key]
        tree = obj.read_typetree(check_read=False)
        programs[key] = bytes(tree["compressedBlob"]), tree["offsets"][0], tree["compressedLengths"][0], tree["decompressedLengths"][0]
        tree["compressedBlob"] = b""
        copy = evolve(obj, assets_file=asset, serialized_type=shader_type, type_id=1)
        copy.save_typetree(tree)
        asset.objects[key] = copy
    template.files = {"CAB-local-source": asset}
    return template.save(packer="none"), programs


def blocks(tree):
    data, offsets, sizes, lengths = tree
    data = bytes(data)
    for offset, size, length in zip(offsets, sizes, lengths, strict=True):
        yield lz4.block.decompress(data[offset:offset + size], uncompressed_size=length)


def create_patch(game, target, patch):
    seed, original = stock_inputs(game)
    payload = target.read_bytes()
    bundle = UnityPy.load(payload).file
    asset, = bundle.files.values()
    manifest = {"sha256": hashlib.sha256(payload).hexdigest(), "modified": []}
    with ZipFile(patch, "w", ZIP_DEFLATED) as archive:
        for key in SHADERS:
            obj = asset.objects[key]
            tree = obj.read_typetree()
            if bytes(tree["compressedBlob"]) != original[key][0]:
                manifest["modified"].append(key)
                target_blocks = blocks((tree["compressedBlob"], tree["offsets"][0], tree["compressedLengths"][0], tree["decompressedLengths"][0]))
                for i, (before, after) in enumerate(zip(blocks(original[key]), target_blocks, strict=True)):
                    archive.writestr(f"{key}-{i}", delta(before, after, True))
            tree["compressedBlob"] = b""
            obj.save_typetree(tree)
        archive.writestr("layout", delta(seed, bundle.save(packer="none"), True))
        archive.writestr("manifest.json", json.dumps(manifest))


def install(game, patch, output):
    seed, original = stock_inputs(game)
    with ZipFile(patch) as archive:
        manifest = json.loads(archive.read("manifest.json"))
        bundle = UnityPy.load(delta(seed, archive.read("layout"), False)).file
        asset, = bundle.files.values()
        for key in SHADERS:
            obj = asset.objects[key]
            tree = obj.read_typetree()
            if key in manifest["modified"]:
                tree["compressedBlob"] = b"".join(
                    lz4.block.compress(delta(block, archive.read(f"{key}-{i}"), False), store_size=False)
                    for i, block in enumerate(blocks(original[key])))
            else:
                tree["compressedBlob"] = original[key][0]
            obj.save_typetree(tree)
        payload = bundle.save(packer="lz4")
    digest = hashlib.sha256(payload).hexdigest()
    if digest != manifest["sha256"]:
        raise ValueError(f"Rebuilt shader bundle failed verification: {digest}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=output.parent, delete=False) as temporary:
        temporary.write(payload)
    try:
        Path(temporary.name).replace(output)
    finally:
        Path(temporary.name).unlink(missing_ok=True)
    print(f"Verified {output} ({digest}).")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game", type=Path)
    parser.add_argument("patch", type=Path)
    parser.add_argument("--create-from", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.create_from:
        create_patch(args.game, args.create_from, args.patch)
    else:
        install(args.game, args.patch, args.output or args.game / "BepInEx/plugins/AL_NPR/al-skin-lighting.unity3d")
