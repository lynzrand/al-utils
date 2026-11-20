"""Compare a surface-light trial with its baseline and disassemble every variant."""

import argparse
import json
from pathlib import Path
import subprocess

from build_skin_assets import SURFACES, blob_references, containers, index, load, parts


def validate(baseline, trial, output, fxc):
    original = next(iter(load(str(baseline)).file.files.values()))
    candidate = next(iter(load(str(trial)).file.files.values()))
    if set(original.objects) != set(candidate.objects):
        raise ValueError('Bundle object inventory changed')
    output.mkdir(parents=True, exist_ok=True)
    report = {}
    for path_id in original.objects:
        if path_id == 1:
            continue
        old = original.objects[path_id].read_typetree()
        new = candidate.objects[path_id].read_typetree()
        if path_id not in SURFACES:
            if old != new:
                raise ValueError(f'Non-surface object changed: {path_id}')
            continue
        old_data, old_rows = index(old)
        new_data, new_rows = index(new)
        if len(old_rows) != len(new_rows):
            raise ValueError('Shader blob inventory changed')
        eligible = {slot for slot, refs in blob_references(old['m_ParsedForm']).items()
                    if any(p == 'UniversalForward' and s == 'progFragment'
                           and '_FORWARD_PLUS' in k and 'DOTS_INSTANCING_ON' not in k
                           for _, _, p, s, k in refs)}
        count = 0
        for slot, ((o, n, seg), (o2, n2, seg2)) in enumerate(zip(old_rows, new_rows)):
            before, after = old_data[seg][o:o+n], new_data[seg2][o2:o2+n2]
            if slot not in eligible:
                if before != after:
                    raise ValueError(f'Unaudited program/parameter changed: {path_id}/{slot}')
                continue
            a, = containers(before, 0, len(before))
            b, = containers(after, 0, len(after))
            a_chunks = dict(parts(before[a.start:a.end]))
            b_chunks = dict(parts(after[b.start:b.end]))
            if a_chunks.keys() != b_chunks.keys() or any(a_chunks[t] != b_chunks[t] for t in a_chunks if t != b'SHEX'):
                raise ValueError(f'Shader signatures or bindings changed: {path_id}/{slot}')
            target = output / f'{path_id}-{slot}.dxbc'
            target.write_bytes(after[b.start:b.end])
            run = subprocess.run([str(fxc), '/dumpbin', '/nologo', str(target)], capture_output=True)
            if run.returncode:
                raise RuntimeError(run.stderr.decode(errors='replace'))
            target.with_suffix('.asm').write_bytes(run.stdout)
            count += 1
        expected = 128 if path_id == 129 else 320
        if count != expected:
            raise ValueError(f'Expected {expected} surface variants, got {count}')
        # The surface trial changes no pass, keyword, property, alpha, blend,
        # depth, resource-binding or shadow-caster metadata.
        expected_name = SURFACES[path_id] + '/MapEnvironment'
        if new['m_ParsedForm']['m_Name'] != expected_name:
            raise ValueError('Unexpected trial shader name')
        new['m_ParsedForm']['m_Name'] = old['m_ParsedForm']['m_Name']
        packed_fields = {'compressedBlob', 'offsets', 'compressedLengths', 'decompressedLengths'}
        if any(old[k] != new[k] for k in old if k not in packed_fields):
            raise ValueError(f'Shader metadata changed: {path_id}')
        report[SURFACES[path_id]] = {'disassembled_variants': count, 'other_programs_and_metadata_unchanged': True}
    (output / 'validation.json').write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('trial', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--fxc', type=Path, default=Path('C:/Program Files (x86)/Windows Kits/10/bin/10.0.26100.0/x64/fxc.exe'))
    args = parser.parse_args()
    validate(args.baseline, args.trial, args.output, args.fxc)
