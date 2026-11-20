"""Verify a rebuilt ray bundle combines the audited skin and clothing objects."""

import argparse
import json
from pathlib import Path

from build_skin_assets import SKIN, load


def objects(path):
    return next(iter(load(str(path)).file.files.values())).objects


def validate(ray_skin, clothing, candidate):
    skin, cloth, result = (objects(path) for path in (ray_skin, clothing, candidate))
    if set(skin) != set(cloth) or set(cloth) != set(result):
        raise ValueError('Bundle object inventories differ')
    report = {}
    for path_id, obj in result.items():
        # The catalog carries the ray bundle name as well as shader references.
        use_ray_source = path_id in SKIN or path_id == 1
        expected = skin[path_id] if use_ray_source else cloth[path_id]
        if obj.get_raw_data() != expected.get_raw_data():
            raise ValueError(f'Object {path_id} differs from its audited source')
        report[path_id] = 'ray skin/catalog' if use_ray_source else 'accepted clothing bundle'
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ray_skin', type=Path)
    parser.add_argument('clothing', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    report = validate(args.ray_skin, args.clothing, args.candidate)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(f'{len(report)} objects match their audited source byte-for-byte')
