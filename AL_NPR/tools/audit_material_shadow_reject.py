"""Offline structural/FXC coverage audit; does not establish rendered equivalence.

Reads extracted shipped metadata and bytecode. Unnamed passes and DOTS programs
remain in the report but are never treated as regular UniversalForward coverage.
No game assets or GPU resources are opened.
"""

import argparse
import collections
import ctypes
import hashlib
import json
from pathlib import Path
import subprocess

from patch_material_shadow_reject import validate_loops, patch_skin_structure
from patch_skin_light_shoulder import parts, build_container, dxbc_checksum


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stock', type=Path, default=Path('artifacts/npr/stock'))
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--fxc', type=Path, required=True)
    args = parser.parse_args()
    affinity = ctypes.windll.kernel32.SetProcessAffinityMask
    affinity.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    if not affinity(ctypes.c_void_p(-1), 0x0FFF):
        raise OSError('Could not reserve user CPU cores')
    args.output.mkdir(parents=True, exist_ok=True)
    rows = []
    for family in ('cloth', 'hair'):
        for line in (args.stock / (family + '.jsonl')).read_text().splitlines():
            metadata = json.loads(line)
            refs = [r for r in metadata['references']
                    if r[3] == 'progFragment' and '_FORWARD_PLUS' in r[4]]
            if not refs:
                continue
            name = '{}-4-{}-{}.dxbc'.format(metadata['path_id'], metadata['blob'], metadata['checksum'][:8])
            source = args.stock / family / name
            raw = source.read_bytes()
            row = dict(family=family, source=str(source), references=refs,
                       sha256=hashlib.sha256(raw).hexdigest(),
                       regular_forward=any(r[2] == 'UniversalForward' and 'DOTS_INSTANCING_ON' not in r[4] for r in refs))
            try:
                if row['sha256'] != metadata['dxbc_sha256'] or dxbc_checksum(raw[20:]) != raw[4:20]:
                    raise ValueError('Stock fingerprint/checksum mismatch')
                sections = list(parts(raw))
                code, = [v for k, v in sections if k == b'SHEX']
                validate_loops(code)
                changed = patch_skin_structure(code)
                result = build_container([(k, changed if k == b'SHEX' else v) for k, v in sections])
                if [(k, v) for k, v in parts(result) if k != b'SHEX'] != [(k, v) for k, v in sections if k != b'SHEX']:
                    raise ValueError('Nonexecutable sections changed')
                target = args.output / (family + '-' + name)
                target.write_bytes(result)
                validation = subprocess.run([str(args.fxc), '/dumpbin', str(target)], capture_output=True)
                if validation.returncode:
                    raise ValueError('FXC failed: ' + validation.stderr.decode(errors='replace'))
                row.update(status='structural_and_fxc_pass', output=str(target),
                           patched_sha256=hashlib.sha256(result).hexdigest())
            except Exception as error:
                row.update(status='rejected', reason=type(error).__name__ + ': ' + str(error))
            rows.append(row)
    counts = collections.Counter((r['family'], r['regular_forward'], r['status']) for r in rows)
    report = dict(scope='Offline structural matching and FXC parsing only; no GPU replay or performance claim',
                  counts=[dict(family=f, regular_forward=u, status=s, count=n) for (f, u, s), n in counts.items()],
                  programs=rows)
    (args.output / 'coverage.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report['counts'], indent=2))


if __name__ == '__main__':
    main()
