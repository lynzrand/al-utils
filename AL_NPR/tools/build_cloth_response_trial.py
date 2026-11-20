"""Derive clothing experiments from the saved, hash-checked raster checkpoint.

Skin, hair, support shaders and all other passes remain byte-identical. This
short path avoids rebuilding them for each clothing A/B experiment. The full
build_skin_assets.py command exposes the same two clothing switches.
"""

import argparse
import hashlib
from pathlib import Path
import tempfile

from build_skin_assets import WORKSPACE, U32, blob_references, build_container, containers, index, load, parts, repack
from patch_cloth_response import patch_program


BASELINE = WORKSPACE / 'artifacts/npr/cap-comparison/character-map-raster.unity3d'
BASELINE_SHA256 = '22d5c48af7fd57845f436d708a7c9a7a97d35a345c76e8634b2a3cd8a6a90bda'


def build(source, output, aggregate, preserve_color):
    original_bytes = source.read_bytes()
    if hashlib.sha256(original_bytes).hexdigest() != BASELINE_SHA256:
        raise ValueError('Source differs from the accepted raster checkpoint')
    bundle = load(original_bytes).file
    asset, = bundle.files.values()
    unchanged = {pid: obj.get_raw_data() for pid, obj in asset.objects.items() if pid not in (131, 136)}
    for pid, name in ((131, 'AL/cloth'), (136, 'AL/cloth_alpha')):
        tree = asset.objects[pid].read_typetree()
        if tree['m_ParsedForm']['m_Name'] != name + '/MapEnvironment':
            raise ValueError('Unexpected clothing shader identity')
        data, rows = index(tree)
        replacements = {}
        for slot, refs in blob_references(tree['m_ParsedForm']).items():
            keywords = [k for _, _, p, s, k in refs if p == 'UniversalForward' and s == 'progFragment'
                        and '_FORWARD_PLUS' in k and 'DOTS_INSTANCING_ON' not in k]
            if not keywords:
                continue
            offset, size, segment = rows[slot]
            wrapper = data[segment][offset:offset + size]
            info, = containers(wrapper, 0, len(wrapper))
            code = patch_program(info.code, fused=all('INSTANCING_ON' not in k for k in keywords),
                                 aggregate=aggregate, preserve_color=preserve_color)
            original = wrapper[info.start:info.end]
            replacement = build_container([(tag, code if tag == b'SHEX' else old) for tag, old in parts(original)])
            length_field, = [pos for pos in range(0, info.start - 3, 4)
                             if U32.unpack_from(wrapper, pos)[0] == info.end - pos - 4]
            header = bytearray(wrapper[:info.start])
            U32.pack_into(header, length_field, len(header) - length_field - 4 + len(replacement))
            replacements[slot] = header + replacement + bytes((-(len(header) + len(replacement))) % 4) + wrapper[(info.end + 3) & ~3:]
        if len(replacements) != 320:
            raise ValueError(f'Expected 320 {name} variants, got {len(replacements)}')
        repack(tree, data, rows, replacements)
        asset.objects[pid].save_typetree(tree)
        print(f'{name}: {len(replacements)} clothing responses updated')
    # UnityPy leaves unchanged objects lazy; edited bytes live in .data while
    # get_raw_data still reads the original backing stream.
    serialized = [obj.data if obj.data is not None else obj.get_raw_data()
                  for _, obj in sorted(asset.objects.items())]
    cab = 'CAB-' + hashlib.sha256(b''.join(serialized)).hexdigest()[:32]
    bundle.files = {cab: asset}
    output.write_bytes(bundle.save(packer='lz4'))
    result = load(output.read_bytes()).file.files[cab]
    if set(result.objects) != set(asset.objects):
        raise ValueError('Bundle object inventory changed')
    for pid, data in unchanged.items():
        if result.objects[pid].get_raw_data() != data:
            raise ValueError(f'Non-clothing object changed: {pid}')
    for pid in (131, 136):
        if result.objects[pid].get_raw_data() != asset.objects[pid].data:
            raise ValueError(f'Clothing shader round-trip mismatch: {pid}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=BASELINE)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cloth-aggregate-cap', action='store_true')
    parser.add_argument('--cloth-preserve-color', action='store_true')
    args = parser.parse_args()
    if not args.cloth_aggregate_cap and not args.cloth_preserve_color:
        parser.error('Select at least one clothing experiment')
    source, output = args.source.resolve(strict=True), args.output.resolve()
    if source == output or not output.is_relative_to(WORKSPACE):
        parser.error('Use a distinct output inside the workspace')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=output.parent, prefix=output.name + '.', delete=False) as handle:
        temporary = Path(handle.name)
    try:
        build(source, temporary, args.cloth_aggregate_cap, args.cloth_preserve_color)
        temporary.replace(output)
        print(hashlib.sha256(output.read_bytes()).hexdigest(), output)
    finally:
        temporary.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
