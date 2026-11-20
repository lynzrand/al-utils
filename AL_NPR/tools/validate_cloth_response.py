"""Validate isolated clothing candidates against the saved raster checkpoint."""

import argparse
import hashlib
import json
from pathlib import Path

from build_cloth_response_trial import BASELINE_SHA256
from build_skin_assets import blob_references, containers, index, load
from patch_cloth_response import patch_program
from validate_surface_map_lighting import validate


def validate_cloth(baseline, trial, output, fxc, aggregate, preserve_color):
    if hashlib.sha256(baseline.read_bytes()).hexdigest() != BASELINE_SHA256:
        raise ValueError('Baseline differs from the accepted raster checkpoint')
    original = next(iter(load(str(baseline)).file.files.values()))
    candidate = next(iter(load(str(trial)).file.files.values()))
    if set(original.objects) != set(candidate.objects):
        raise ValueError('Bundle object inventory changed')
    count = 0
    for path_id, obj in original.objects.items():
        if path_id not in (131, 136):
            if obj.get_raw_data() != candidate.objects[path_id].get_raw_data():
                raise ValueError(f'Non-clothing object changed: {path_id}')
            continue
        before = obj.read_typetree()
        after = candidate.objects[path_id].read_typetree()
        old_data, old_rows = index(before)
        new_data, new_rows = index(after)
        for slot, refs in blob_references(before['m_ParsedForm']).items():
            keywords = [k for _, _, p, s, k in refs if p == 'UniversalForward' and s == 'progFragment'
                        and '_FORWARD_PLUS' in k and 'DOTS_INSTANCING_ON' not in k]
            if not keywords:
                continue
            offset, size, segment = old_rows[slot]
            old_wrapper = old_data[segment][offset:offset + size]
            offset, size, segment = new_rows[slot]
            new_wrapper = new_data[segment][offset:offset + size]
            old_program, = containers(old_wrapper, 0, len(old_wrapper))
            new_program, = containers(new_wrapper, 0, len(new_wrapper))
            expected = patch_program(old_program.code, fused=all('INSTANCING_ON' not in k for k in keywords),
                                     aggregate=aggregate, preserve_color=preserve_color)
            if new_program.code != expected:
                raise ValueError(f'Clothing response differs from selected experiment: {path_id}/{slot}')
            count += 1
    if count != 640:
        raise ValueError(f'Expected 640 clothing variants, got {count}')

    # Shared validation checks noneligible programs, signatures, bindings and
    # metadata, then independently disassembles every supported surface variant.
    validate(baseline, trial, output, fxc)
    report = {
        'sha256': hashlib.sha256(trial.read_bytes()).hexdigest(),
        'cloth_aggregate_cap': aggregate,
        'cloth_preserve_color': preserve_color,
        'clothing_variants': count,
        'all_non_clothing_objects_byte_identical': True,
    }
    (output / 'cloth-validation.json').write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('trial', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--fxc', type=Path, default=Path('C:/Program Files (x86)/Windows Kits/10/bin/10.0.26100.0/x64/fxc.exe'))
    parser.add_argument('--cloth-aggregate-cap', action='store_true')
    parser.add_argument('--cloth-preserve-color', action='store_true')
    args = parser.parse_args()
    if not args.cloth_aggregate_cap and not args.cloth_preserve_color:
        parser.error('Select at least one clothing experiment')
    validate_cloth(args.baseline, args.trial, args.output, args.fxc,
                   args.cloth_aggregate_cap, args.cloth_preserve_color)
