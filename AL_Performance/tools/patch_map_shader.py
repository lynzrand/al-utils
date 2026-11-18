from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import shutil
import tempfile

import lz4.block
from UnityPy import load
from UnityPy.streams import EndianBinaryReader

from map_shader_bytecode import GAME, MAP, ROW, U32, containers, segments, sha


SOURCE_HASH = 'cc014c4111b17d1b3b60400d5446023a058a6098ef46383574fb21feb78d7414'
STOCK_DXBC_HASH = '5dda33fdd6ad3621007047ddd7b86b42f8cfd4e310644402d7abd7864784d34d'
SERIALIZED_FILE = 'BuildPlayer-map002.sharedAssets'
SHADER_PATH_ID = 206
BLOB_INDEX = 620
PROGRAM_LENGTH_OFFSET = 28
DXBC_OFFSET = 70
WORKSPACE = Path(__file__).resolve().parents[2]


def file_sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def open_bundle(path):
    with path.open('rb') as stream:
        bundle = load(stream).file
    if (bundle.signature, bundle.version, int(bundle.dataflags)) != ('UnityFS', 8, 579):
        raise ValueError('Unexpected UnityFS header')
    return bundle


def shader_object(bundle):
    obj = bundle.files[SERIALIZED_FILE].objects[SHADER_PATH_ID]
    if obj.type.name != 'Shader':
        raise ValueError('Unexpected object class at the shader path ID')
    return obj


def read_program(shader):
    if shader['m_ParsedForm']['m_Name'] != 'AL/Map' or shader['platforms'] != [4]:
        raise ValueError('Unexpected shader name or platform list')
    data = segments(shader, 0)
    table = bytearray(data[0])
    count = U32.unpack_from(table)[0]
    if count != 640 or len(table) != 4 + count * ROW.size:
        raise ValueError('Unexpected shader index layout')
    entries = list(ROW.iter_unpack(table[4:]))
    for index, (start, size, segment) in enumerate(entries):
        if segment == 0 or segment >= len(data) or start + size > len(data[segment]):
            raise ValueError(f'Invalid shader index row {index}')
    start, size, segment = entries[BLOB_INDEX]
    program = data[segment][start:start + size]
    return table, entries, data, program


def shader_chunks(raw):
    records = list(containers(raw, 0, len(raw)))
    if len(records) != 1 or records[0].start != 0 or records[0].end != len(raw):
        raise ValueError('Expected one complete DXBC container')
    if records[0].shader_model != 0x50 or records[0].code_tag != 'SHEX':
        raise ValueError('Expected a Shader Model 5.0 pixel shader')
    for index in range(U32.unpack_from(raw, 28)[0]):
        start = U32.unpack_from(raw, 32 + index * 4)[0]
        size = U32.unpack_from(raw, start + 4)[0]
        yield raw[start:start + 4], raw[start + 8:start + 8 + size]


def signature(chunk):
    count, start = U32.unpack_from(chunk, 0)[0], U32.unpack_from(chunk, 4)[0]
    fields = []
    for index in range(count):
        entry = start + 24 * index
        name = U32.unpack_from(chunk, entry)[0]
        end = chunk.index(0, name)
        fields.append((chunk[name:end].upper(), chunk[entry + 4:entry + 22]))
    return fields


def patch_shader(shader, replacement):
    table, entries, data, old_program = read_program(shader)
    start, size, segment = entries[BLOB_INDEX]
    if (start, size, segment) != (6913448, 2160, 3):
        raise ValueError('Unexpected stock subprogram location')
    original = old_program[DXBC_OFFSET:DXBC_OFFSET + 2080]
    if sha(original) != STOCK_DXBC_HASH:
        raise ValueError('Unexpected stock subprogram hash')
    old_chunks = dict(shader_chunks(original))
    new_chunks = dict(shader_chunks(replacement))
    for tag in (b'ISGN', b'OSGN'):
        if signature(old_chunks[tag]) != signature(new_chunks[tag]):
            raise ValueError(f'Replacement has a different {tag.decode()} signature')

    # Unity counts the D3D backend header and DXBC together as one byte array.
    # The next field starts at the following four-byte boundary.
    wrapped_length = U32.unpack_from(old_program, PROGRAM_LENGTH_OFFSET)[0]
    if wrapped_length != DXBC_OFFSET - PROGRAM_LENGTH_OFFSET - U32.size + len(original):
        raise ValueError('Unexpected shader byte-array length')
    padded_end = (DXBC_OFFSET + len(original) + 3) & ~3
    padding = (-DXBC_OFFSET - len(replacement)) % 4
    program = bytearray(old_program[:DXBC_OFFSET] + replacement + bytes(padding) + old_program[padded_end:])
    delta = len(program) - size
    U32.pack_into(program, PROGRAM_LENGTH_OFFSET, wrapped_length + len(replacement) - len(original))
    for index, (offset, length, segment_index) in enumerate(entries):
        if segment_index != segment:
            continue
        if index == BLOB_INDEX:
            length += delta
        elif offset >= start + size:
            offset += delta
        elif offset + length > start:
            raise ValueError(f'Subprogram {index} overlaps the requested patch range')
        ROW.pack_into(table, 4 + ROW.size * index, offset, length, segment_index)

    # Preserve the packed bytes of the two segments whose contents never change.
    original_packed = bytes(shader['compressedBlob'])
    patched_segments = {0: bytes(table), segment: data[segment][:start] + program + data[segment][start + size:]}
    offsets, lengths, sizes = (shader[key][0] for key in ('offsets', 'compressedLengths', 'decompressedLengths'))
    packed = bytearray()
    for index in range(len(offsets)):
        if index in patched_segments:
            raw = patched_segments[index]
            block = lz4.block.compress(raw, store_size=False)
            sizes[index] = len(raw)
        else:
            block = original_packed[offsets[index]:offsets[index] + lengths[index]]
        offsets[index] = len(packed)
        lengths[index] = len(block)
        packed.extend(block)
    shader['compressedBlob'] = bytes(packed)
    return data, entries


def verify_program(output_shader, replacement, stock_segments, stock_entries):
    _, entries, data, program = read_program(output_shader)
    if program[DXBC_OFFSET:DXBC_OFFSET + len(replacement)] != replacement:
        raise ValueError('Output did not round-trip the replacement DXBC')
    for index, ((offset, size, segment), (old_offset, old_size, old_segment)) in enumerate(zip(entries, stock_entries, strict=True)):
        if index == BLOB_INDEX:
            continue
        if data[segment][offset:offset + size] != stock_segments[old_segment][old_offset:old_offset + old_size]:
            raise ValueError(f'Output altered another shader subprogram, row {index}')


def verify_output(path, replacement, baseline, stock_segments, stock_entries):
    result = open_bundle(path)
    if set(result.files) != set(baseline.files):
        raise ValueError('Output bundle directory differs')
    target = shader_object(result)
    patched_shader = target.read_typetree(check_read=False)
    verify_program(patched_shader, replacement, stock_segments, stock_entries)
    stock_shader = shader_object(baseline).read_typetree(check_read=False)
    storage_fields = {'offsets', 'compressedLengths', 'decompressedLengths', 'compressedBlob'}
    if any(patched_shader[key] != stock_shader[key] for key in stock_shader.keys() - storage_fields):
        raise ValueError('Output changed the shader metadata')
    changed_file = result.files[SERIALIZED_FILE]
    stock_file = baseline.files[SERIALIZED_FILE]
    if set(changed_file.objects) != set(stock_file.objects):
        raise ValueError('Output changed the serialized object inventory')
    for path_id, obj in changed_file.objects.items():
        if path_id == SHADER_PATH_ID:
            continue
        stock_obj = stock_file.objects[path_id]
        if obj.type != stock_obj.type or obj.get_raw_data() != stock_obj.get_raw_data():
            raise ValueError(f'Output changed an unrelated object at path ID {path_id}')
    for name, original in baseline.files.items():
        if name != SERIALIZED_FILE:
            patched = result.files[name]
            original_reader = getattr(original, 'reader', original)
            patched_reader = getattr(patched, 'reader', patched)
            if patched_reader.bytes != original_reader.bytes:
                raise ValueError(f'Output changed an unrelated embedded file {name}')


def patch(source, replacement, output):
    bundle = open_bundle(source)
    obj = shader_object(bundle)
    shader = obj.read_typetree(check_read=False)
    stock_segments, stock_entries = patch_shader(shader, replacement)
    obj.save_typetree(shader)
    original_files = bundle.files.copy()
    # BundleFile.save otherwise reserializes every embedded SerializedFile.
    for name, original in original_files.items():
        if name != SERIALIZED_FILE and not isinstance(original, EndianBinaryReader):
            raw = original.reader
            raw.flags = original.flags
            bundle.files[name] = raw
    output.write_bytes(bundle.save(packer='original'))
    bundle.files = original_files
    verify_output(output, replacement, bundle, stock_segments, stock_entries)


def main():
    parser = argparse.ArgumentParser(description='Patch or restore a workspace copy of the map002 AL/Map shader bundle.')
    parser.add_argument('--source', type=Path, default=MAP, help='SHA-256-verified original map bundle')
    parser.add_argument('--output', type=Path, required=True, help='Output file inside the workspace')
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument('--replace', type=Path, help='Compatible SM5 pixel shader in a DXBC container')
    action.add_argument('--restore', action='store_true', help='Copy the verified original bundle to the output')
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    output = args.output.resolve()
    if source == output or not output.is_relative_to(WORKSPACE) or output.is_relative_to(GAME.resolve()):
        parser.error('Output must be inside the workspace and must differ from the verified source')
    if file_sha(source) != SOURCE_HASH:
        parser.error('Source bundle SHA-256 does not match the stock map002 bundle')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=output.parent, prefix=output.name + '.', delete=False) as stream:
        temporary = Path(stream.name)
    try:
        if args.restore:
            shutil.copyfile(source, temporary)
            if file_sha(temporary) != SOURCE_HASH:
                raise ValueError('Restored copy SHA-256 does not match the verified source')
        else:
            patch(source, args.replace.read_bytes(), temporary)
        result_hash = file_sha(temporary)
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)
    print(f'{result_hash}  {output}')


if __name__ == '__main__':
    main()
