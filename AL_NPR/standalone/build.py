"""Build AL-NPR's D3D11 bundle from compiled project shaders and their Unity material ABI."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys
from tempfile import NamedTemporaryFile

import lz4.block
import UnityPy

from unity_bundle import aligned, unity_bundle

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "tools"))
from patch_skin_map_params import encode

MATERIALS = {"Face": "skin_head", "Body": "skin_body", "Cloth": "cloth",
             "ClothAlpha": "cloth_alpha", "Hair": "hair"}


def mesh_program(interface, dxbc):
    header = bytes(interface["resource_header"])
    channels = interface["channels"]
    # Unity's subprogram version, GPU program type, four statistics and
    # keyword count precede the length-prefixed Direct3D container.
    prefix = struct.pack("<8I", 202012090, interface["gpu_type"], 0, 0, 0, 0, 0, len(header) + len(dxbc))
    return aligned(prefix + header + dxbc, 4) + struct.pack(f"<{len(channels)}I", *channels)


def shader(family, programs):
    layout = json.loads((HERE / "layouts" / (family + ".json")).read_text(encoding="utf-8"))
    form = layout["form"]
    blobs = []
    for shader_pass in form["m_SubShaders"][0]["m_Passes"]:
        for key, suffix in (("progVertex", "VS"), ("progFragment", "PS")):
            name = family + shader_pass["m_State"]["m_Name"] + suffix
            interface = layout["stages"][name]
            dxbc = (programs / (name + ".dxbc")).read_bytes()
            if dxbc[:4] != b"DXBC" or struct.unpack_from("<I", dxbc, 24)[0] != len(dxbc):
                raise ValueError(f"Invalid compiler output for {name}")
            variant = dict(m_BlobIndex=len(blobs), m_KeywordIndices=[],
                           m_ShaderRequirements=interface["requirements"], m_GpuProgramType=interface["gpu_type"])
            tier = interface["tier"]
            shader_pass[key]["m_PlayerSubPrograms"] = [[] for _ in range(tier)] + [[variant]]
            shader_pass[key]["m_ParameterBlobIndices"] = [[] for _ in range(tier)] + [[len(blobs) + 1]]
            blobs.extend((mesh_program(interface, dxbc), encode(interface["parameters"])))
    index = bytearray(struct.pack("<I", len(blobs)))
    offset = 4 + 12 * len(blobs)
    for blob in blobs:
        index.extend(struct.pack("<III", offset, len(blob), 0))
        offset += len(blob)
    raw = bytes(index) + b"".join(blobs)
    compressed = lz4.block.compress(raw, store_size=False)
    guid = struct.unpack("<4I", hashlib.sha256(form["m_Name"].encode()).digest()[:16])
    return dict(m_Name="", m_ParsedForm=form, platforms=[4], offsets=[[0]],
                compressedLengths=[[len(compressed)]], decompressedLengths=[[len(raw)]],
                compressedBlob=compressed, stageCounts=[2], m_Dependencies=[], m_NonModifiableTextures=[],
                m_ShaderIsBaked=True, m_AssetGUID={f"data[{i}]": part for i, part in enumerate(guid)})


def bundle_catalog():
    pointers = [dict(m_FileID=0, m_PathID=i) for i in range(2, 2 + len(MATERIALS))]
    assets = [(f"assets/al_npr/{name}.shader", dict(preloadIndex=i, preloadSize=1, asset=pointers[i]))
              for i, name in enumerate(MATERIALS.values())]
    return dict(m_Name="al-skin-lighting", m_PreloadTable=pointers, m_Container=assets,
                m_MainAsset=dict(preloadIndex=0, preloadSize=0, asset=dict(m_FileID=0, m_PathID=0)),
                m_RuntimeCompatibility=1, m_AssetBundleName="al-skin-lighting", m_Dependencies=[],
                m_IsStreamedSceneAssetBundle=False, m_ExplicitDataLayout=0, m_PathFlags=7, m_SceneHashes=[])


def build(programs, output):
    catalog = bundle_catalog()
    shaders = [shader(family, programs) for family in MATERIALS]
    payload = unity_bundle([(142, catalog), *((48, value) for value in shaders)])
    asset, = UnityPy.load(payload).file.files.values()
    if asset.externals or asset.objects[1].read_typetree() != catalog:
        raise ValueError("Serialized bundle catalog differs from the standalone build")
    for i, expected in enumerate(shaders, 2):
        # UnityPy represents serialized maps as pairs of tuples.
        actual = asset.objects[i].read_typetree()
        actual_blob = bytes(actual.pop("compressedBlob"))
        expected_blob = expected.pop("compressedBlob")
        if actual_blob != expected_blob or json.dumps(actual, sort_keys=True) != json.dumps(expected, sort_keys=True):
            raise ValueError(f"Serialized shader {i} differs from the standalone build")
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = NamedTemporaryFile(dir=output.parent, delete=False)
    temp = Path(temporary.name)
    try:
        with temporary:
            temporary.write(payload)
        temp.replace(output)
    finally:
        temp.unlink(missing_ok=True)
    print(f"{output} ({len(payload):,} bytes, SHA-256 {hashlib.sha256(payload).hexdigest()})")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("programs", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    build(args.programs, args.output)
