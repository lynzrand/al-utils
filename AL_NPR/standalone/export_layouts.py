"""Refresh the D3D11 material ABI from the audited reference during development.

The release builder consumes the checked-in JSON. Only properties, render state,
bindings and mesh channel assignments belong here. Stage code comes from Slang.
"""
import argparse
import json
from pathlib import Path
import struct
import sys

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent / "tools"), str(HERE.parents[1] / "AL_Performance/tools")]
from slang_bundle import MANIFEST, MATERIALS, containers, index, load, manifest_stages
from patch_skin_map_params import decode


def save_layout(path, document):
    # Keep each binding on its own line while keeping scalar arrays together.
    def format_value(value, depth):
        compact = json.dumps(value, ensure_ascii=False)
        if len(compact) < 160:
            return compact
        if isinstance(value, dict):
            items = [json.dumps(k) + ": " + format_value(v, depth + 1) for k, v in value.items()]
            opening, closing = "{", "}"
        elif isinstance(value, (list, tuple)):
            items = [format_value(v, depth + 1) for v in value]
            opening, closing = "[", "]"
        else:
            return compact
        indent = "  " * (depth + 1)
        return opening + "\n" + indent + (",\n" + indent).join(items) + "\n" + "  " * depth + closing

    path.write_text(format_value(document, 0) + "\n", encoding="utf-8")


def extract(tree, family, manifest):
    blocks, rows = index(tree)
    def blob(slot):
        offset, size, segment = rows[slot]
        return bytes(blocks[segment][offset:offset + size])

    form = tree["m_ParsedForm"]
    stages = {name: (slot, variants) for name, slot, _, variants
              in manifest_stages(tree, family, manifest, False)}
    interfaces = {}
    for shader_pass in form["m_SubShaders"][0]["m_Passes"]:
        shader_pass["m_HasInstancingVariant"] = False
        for program_key, suffix in (("progVertex", "VS"), ("progFragment", "PS")):
            name = family + shader_pass["m_State"]["m_Name"] + suffix
            program = shader_pass[program_key]
            slot, matches = stages[name]
            (tier, variant_index), = [(tier, i) for tier, group in enumerate(program["m_PlayerSubPrograms"])
                                      for i, variant in enumerate(group) if variant is matches[0]]
            variant = matches[0]
            params = program["m_ParameterBlobIndices"][tier][variant_index]
            wrapper = blob(slot)
            dxbc, = containers(wrapper, 0, len(wrapper))
            # The 38-byte D3D11 header carries resource counts and flags.
            # Everything after the aligned DXBC container maps mesh channels.
            resource_header = wrapper[dxbc.start - 38:dxbc.start]
            tail = wrapper[(dxbc.end + 3) & ~3:]
            if int.from_bytes(wrapper[dxbc.start - 42:dxbc.start - 38], "little") != 38 + dxbc.end - dxbc.start:
                raise ValueError(f"{name}: unexpected D3D program header")
            interfaces[name] = dict(
                tier=tier, requirements=variant["m_ShaderRequirements"],
                gpu_type=variant["m_GpuProgramType"], resource_header=list(resource_header),
                channels=list(struct.unpack(f"<{len(tail)//4}I", tail)), parameters=decode(blob(params)))
            program["m_PlayerSubPrograms"] = []
            program["m_ParameterBlobIndices"] = []
        for key in ("progVertex", "progFragment", "progGeometry", "progHull", "progDomain", "progRayTracing"):
            shader_pass[key]["m_SerializedKeywordStateMask"] = []
    form.update(m_KeywordNames=[], m_KeywordFlags=[], m_CustomEditorName="", m_FallbackName="",
                m_CustomEditorForRenderPipelines=[])
    return dict(form=form, stages=interfaces)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference", type=Path)
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    asset, = load(args.reference.read_bytes()).file.files.values()
    for path_id, family in MATERIALS.items():
        layout = extract(asset.objects[path_id].read_typetree(), family, manifest)
        save_layout(HERE / "layouts" / (family + ".json"), layout)
