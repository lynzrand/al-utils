"""Extract matching Forward+ pixel programs for inspection in DXBC shader tools."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from build_skin_assets import SOURCE, blob_references, containers, index, load


def export(source, output, compiler=None, spirv_cross=None):
    bundle = load(str(source)).file
    asset = bundle if hasattr(bundle, "objects") else next(iter(bundle.files.values()))
    output.mkdir(parents=True, exist_ok=True)
    manifest = {}
    for shader, name in ((76, "skin_head"), (146, "skin_body"), (131, "cloth"), (136, "cloth_alpha")):
        tree = asset.objects[shader].read_typetree(check_read=False)
        data, rows = index(tree)
        variants = [(slot, kw) for slot, refs in blob_references(tree["m_ParsedForm"]).items()
                    for _, _, lightmode, stage, kw in refs
                    if lightmode == "UniversalForward" and stage == "progFragment"
                    and "_FORWARD_PLUS" in kw and "DOTS_INSTANCING_ON" not in kw]
        # Prefer additional light shadows and cascades with no decals or instancing.
        wanted = {"_FORWARD_PLUS", "_ADDITIONAL_LIGHT_SHADOWS", "_MAIN_LIGHT_SHADOWS_CASCADE"}
        slot, keywords = min(variants, key=lambda v: (len(wanted.symmetric_difference(v[1])), v))
        offset, size, segment = rows[slot]
        wrapper = data[segment][offset:offset + size]
        container, = containers(wrapper, 0, size)
        dxbc = wrapper[container.start:container.end]
        binary = output / f"{name}.dxbc"
        binary.write_bytes(dxbc)
        if compiler:
            spirv = binary.with_suffix(".spv")
            subprocess.run([compiler, "-x", "dxbc-tpf", "-b", "spirv-binary", "-o", spirv, binary], check=True)
            subprocess.run([spirv_cross, spirv, "--hlsl", "--shader-model", "50", "--output",
                            binary.with_suffix(".hlsl")], check=True)
        manifest[name] = dict(slot=slot, keywords=keywords, variants=len({v[0] for v in variants}),
                              sha256=hashlib.sha256(dxbc).hexdigest())
    (output / "programs.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--source", type=Path, default=SOURCE, help="Stock serialized file or replacement bundle")
    parser.add_argument("--vkd3d", help="vkd3d-compiler executable for full HLSL inspection listings")
    parser.add_argument("--spirv-cross", help="SPIRV-Cross executable")
    args = parser.parse_args()
    if bool(args.vkd3d) != bool(args.spirv_cross):
        parser.error("Supply both translators to generate HLSL")
    export(args.source, args.output, args.vkd3d, args.spirv_cross)
