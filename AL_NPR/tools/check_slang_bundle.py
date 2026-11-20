"""Verify rebuilt Unity permutations, their input tables and the preserved base programs."""

import argparse
import json
from pathlib import Path

from slang_bundle import MANIFEST, MATERIALS, SOURCE, containers, index, load, manifest_stages


def blob(data, row):
    offset, size, segment = row
    return data[segment][offset:offset + size]


def verify(bundle, programs, base):
    manifest = json.loads(MANIFEST.read_text())
    rebuilt, = load(str(bundle)).file.files.values()
    original = next(iter(load(str(base)).file.files.values())) if base else load(str(SOURCE)).file
    count = 0
    for path_id, material in MATERIALS.items():
        before = original.objects[path_id].read_typetree(check_read=bool(base))
        after = rebuilt.objects[path_id].read_typetree()
        data, rows = index(after)
        original_data, original_rows = index(before)
        if any(blob(data, row) != blob(original_data, old) for row, old in zip(rows, original_rows)):
            raise ValueError(f"{material}: original program or parameter table changed")
        if len(rows) <= len(original_rows):
            raise ValueError(f"{material}: missing edited program slots")

        stages = list(manifest_stages(before, material, manifest, not base))
        compiled_stages = manifest_stages(after, material, manifest, not base)
        for (name, original_slot, _, _), (compiled_name, slot, _, variants) in zip(stages, compiled_stages, strict=True):
            wrapper = blob(data, rows[slot])
            info, = containers(wrapper, 0, len(wrapper))
            if (compiled_name != name or slot < len(original_rows) or
                    wrapper[info.start:info.end] != (programs / (name + ".dxbc")).read_bytes()):
                raise ValueError(f"{name}: selected Unity permutation differs from its compiled stage")
            for variant in variants:
                variant["m_BlobIndex"] = original_slot
            count += 1

        original_form = before["m_ParsedForm"]
        if not base:
            original_form["m_Name"] += "/Environment"
        if after["m_ParsedForm"] != original_form:
            raise ValueError(f"{material}: other passes, keyword tables or shader metadata changed")
    if count != len(manifest):
        raise ValueError(f"Only {count} of {len(manifest)} stages verified")
    print(f"{bundle}: verified all {count} stages, original program slots and Unity pass tables")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--programs", type=Path, required=True)
    parser.add_argument("--base", type=Path, help="Original NPR variant bundle. Omit for a stock build.")
    args = parser.parse_args()
    verify(args.bundle, args.programs, args.base)
