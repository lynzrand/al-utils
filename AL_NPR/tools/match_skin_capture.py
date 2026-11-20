"""Match rendered DXBC instructions to regular skin variants in a built bundle."""

import argparse
import hashlib
from collections import defaultdict
from pathlib import Path

from build_skin_assets import SKIN, blob_references, containers, index, load
from patch_skin_light_shoulder import parts


def skin_programs(path):
    bundle = load(path.read_bytes()).file
    asset, = (file for file in bundle.files.values()
              if hasattr(file, "objects") and SKIN.keys() <= file.objects.keys())
    programs = {}
    for path_id, name in SKIN.items():
        tree = asset.objects[path_id].read_typetree()
        segments, rows = index(tree)
        for slot, references in blob_references(tree["m_ParsedForm"]).items():
            if not any(pass_name == "UniversalForward" and stage == "progFragment"
                       and "_FORWARD_PLUS" in keywords and "DOTS_INSTANCING_ON" not in keywords
                       for _, _, pass_name, stage, keywords in references):
                continue
            offset, size, segment = rows[slot]
            wrapper = segments[segment][offset:offset + size]
            info, = containers(wrapper, 0, size)
            programs[name, slot] = (hashlib.sha256(info.code).digest(), wrapper[info.start:info.end])
    return programs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("capture_shaders", type=Path)
    parser.add_argument("--reference", type=Path)
    parser.add_argument("--replay-inputs", type=Path)
    args = parser.parse_args()
    if bool(args.reference) != bool(args.replay_inputs):
        parser.error("--reference and --replay-inputs must be supplied together")
    if args.replay_inputs:
        args.replay_inputs.mkdir(parents=True, exist_ok=True)

    keys_by_hash = defaultdict(list)
    for key, (digest, _) in skin_programs(args.bundle).items():
        keys_by_hash[digest].append(key)
    reference = skin_programs(args.reference) if args.reference else None
    families = set()
    for shader in sorted(args.capture_shaders.glob("*-ps.dxbc")):
        code, = (payload for tag, payload in parts(shader.read_bytes())
                 if tag in (b"SHDR", b"SHEX"))
        keys = keys_by_hash.get(hashlib.sha256(code).digest())
        if not keys:
            continue
        print(shader.name, ", ".join(f"{name} variant {slot}" for name, slot in keys))
        families.update(name for name, _ in keys)
        if reference is not None:
            candidates = {reference[key][1] for key in keys}
            if len(candidates) != 1:
                raise ValueError(f"Ambiguous reference variant for {shader.name}")
            (args.replay_inputs / shader.name).write_bytes(candidates.pop())
    if families != set(SKIN.values()):
        parser.exit(1, f"Capture did not contain both replacement skin shaders; found {sorted(families)}\n")


if __name__ == "__main__":
    main()
