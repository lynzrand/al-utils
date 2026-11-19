from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import struct

import lz4.block
from UnityPy import load

GAME = Path(os.environ.get('AL_GAME_PATH', r'H:\Programs\gal\amanatsu-location'))
MAP = GAME / 'lib/ma/pre/sc/000_08/02.unity3d'
DXBC = re.compile(b'DXBC')
ROW = struct.Struct('<III')
U32 = struct.Struct('<I')


@dataclass(frozen=True)
class Container:
    start: int
    end: int
    code: bytes
    code_tag: str
    shader_model: int
    instructions: bytes


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def containers(data: bytes, start: int, end: int):
    for match in DXBC.finditer(data, start, end):
        offset = match.start()
        if offset + 32 > end:
            continue
        version, length, chunks = ROW.unpack_from(data, offset + 20)
        stop = offset + length
        if version != 1 or stop > end or chunks > 128 or length < 32 + chunks * 4:
            continue
        code = None
        valid = True
        for index in range(chunks):
            relative = U32.unpack_from(data, offset + 32 + index * 4)[0]
            chunk = offset + relative
            if relative < 32 + chunks * 4 or chunk + 8 > stop:
                valid = False
                break
            tag = data[chunk:chunk + 4]
            size = U32.unpack_from(data, chunk + 4)[0]
            if chunk + 8 + size > stop:
                valid = False
                break
            if tag in (b'SHDR', b'SHEX', b'DXIL'):
                code = (tag.decode('ascii'), data[chunk + 8:chunk + 8 + size])
        if not valid or code is None or len(code[1]) < 8:
            continue
        tag, payload = code
        shader_model = U32.unpack_from(payload)[0]
        instructions = payload[8:] if tag in ('SHDR', 'SHEX') else payload
        yield Container(offset, stop, payload, tag, shader_model, instructions)


def segments(shader, platform_index):
    packed = bytes(shader['compressedBlob'])
    rows = zip(shader['offsets'][platform_index], shader['compressedLengths'][platform_index],
               shader['decompressedLengths'][platform_index], strict=True)
    return [lz4.block.decompress(packed[off:off + comp], uncompressed_size=uncomp)
            for off, comp, uncomp in rows]


def blob_references(form):
    keywords = form['m_KeywordNames']
    references = defaultdict(set)
    for subshader_index, subshader in enumerate(form['m_SubShaders']):
        for pass_index, shader_pass in enumerate(subshader['m_Passes']):
            tags = dict(shader_pass['m_State']['m_Tags']['tags'])
            for stage, group in shader_pass.items():
                if not stage.startswith('prog'):
                    continue
                for programs in group['m_PlayerSubPrograms']:
                    for item in programs:
                        kw = tuple(keywords[index] for index in item['m_KeywordIndices'])
                        references[item['m_BlobIndex']].add(
                            (subshader_index, pass_index, tags.get('LIGHTMODE', ''), stage, kw))
    return references


def shader_records(source: Path, asset_name: str | None = None):
    env = load(str(source))
    for obj in env.objects:
        if obj.type.name != 'Shader':
            continue
        shader = obj.read_typetree(check_read=False)
        form = shader['m_ParsedForm']
        name = form['m_Name']
        if asset_name and name != asset_name:
            continue
        references = blob_references(form)
        for i, platform in enumerate(shader['platforms']):
            data = segments(shader, i)
            count = U32.unpack_from(data[0])[0]
            if 4 + count * ROW.size > len(data[0]):
                raise ValueError(f'Unsupported shader table for {name}')
            for blob_index, (offset, length, segment_index) in enumerate(
                    ROW.iter_unpack(data[0][4:4 + count * ROW.size])):
                if segment_index >= len(data) or offset + length > len(data[segment_index]):
                    raise ValueError(f'Out of bounds blob {blob_index} for {name}')
                segment = data[segment_index]
                for dxbc in containers(segment, offset, offset + length):
                    raw = segment[dxbc.start:dxbc.end]
                    record = dict(shader=name, file=obj.assets_file.name, path_id=obj.path_id, platform=platform,
                                  blob=blob_index, segment=segment_index, offset=dxbc.start, length=len(raw),
                                  dxbc_sha256=sha(raw), checksum=raw[4:20].hex(),
                                  program_sha256=sha(dxbc.code), instructions_sha256=sha(dxbc.instructions),
                                  tag=dxbc.code_tag, model=hex(dxbc.shader_model),
                                  references=sorted(references[blob_index]))
                    yield record, raw


def main():
    parser = argparse.ArgumentParser(description='Locate or extract a compiled shader in a Unity bundle or serialized file.')
    parser.add_argument('--source', type=Path, default=MAP)
    parser.add_argument('--shader')
    parser.add_argument('--match', help='DXBC SHA256, container checksum, program SHA256 or instruction SHA256')
    parser.add_argument('--bytecode', type=Path, help='Match a raw DXBC file to the asset')
    parser.add_argument('--extract', type=Path, help='Write matching raw DXBC files into this directory')
    parser.add_argument('--output', type=Path, help='Write JSON Lines instead of standard output')
    args = parser.parse_args()
    matches = set()
    if args.match:
        matches.add(args.match.lower().removeprefix('0x'))
    if args.bytecode:
        raw = args.bytecode.read_bytes()
        found = next(containers(raw, 0, len(raw)), None)
        if found is None:
            raise SystemExit('No DXBC shader container found in requested file')
        matches.update((sha(raw[found.start:found.end]), sha(found.code), sha(found.instructions)))
    if args.extract:
        args.extract.mkdir(parents=True, exist_ok=True)
    stream = args.output.open('w', encoding='utf-8') if args.output else None
    total = 0
    try:
        for record, raw in shader_records(args.source, args.shader):
            hashes = (record['dxbc_sha256'], record['checksum'], record['program_sha256'], record['instructions_sha256'])
            if matches and not matches.intersection(hashes):
                continue
            if args.extract:
                name = f"{record['path_id']}-{record['platform']}-{record['blob']}-{record['checksum'][:8]}.dxbc"
                (args.extract / name).write_bytes(raw)
            row = json.dumps(record, separators=(',', ':'), ensure_ascii=True)
            if stream:
                stream.write(row + '\n')
            else:
                print(row)
            total += 1
    finally:
        if stream:
            stream.close()
    if matches and total == 0:
        raise SystemExit('No matching shader bytecode in source')


if __name__ == '__main__':
    main()
