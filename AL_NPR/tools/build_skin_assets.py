"""Build a runtime shader bundle for the audited AL 1.0.4 skin shaders."""

import argparse
import hashlib
from attrs import evolve
from pathlib import Path
import tempfile

from patch_skin_light_shoulder import (
    OPCODE_MASK, build_container, decode_program, dxbc_checksum, locate_mix, parts,
)
from patch_al_full_light_fusion import locate_fused_mix, patch_program as fuse_all_lobes
from patch_early_shadow_reject import patch as reject_zero_lights
from patch_material_shadow_reject import validate_loops
from patch_skin_sh_environment import patch as patch_environment_program
from patch_skin_fused_lobes import patch_program as fuse_skin_lobes
from patch_skin_map_layer import patch_program as use_map_layer
from patch_skin_map_params import append_common_metadata, append_map_buffer
from patch_skin_map_directionals import patch_program as use_authored_directionals
from patch_skin_map_ray_visibility import patch_program as use_ray_visibility
from patch_skin_cap_profile import PROFILES, patch_program as apply_cap_profile
from patch_surface_map_lighting import patch_program as use_surface_map_lights
from patch_cloth_response import patch_program as adjust_cloth_response
from map_shader_bytecode import GAME, ROW, U32, blob_references, containers, load, lz4, segments
from patch_map_shader import file_sha


STOCK = "c11860706e6666da0718c2e4b7d97af5b5808a003806ca289387eeb4ba8a93aa"
SKIN = {76: "AL/skin_head", 146: "AL/skin_body"}
SURFACES = {129: "AL/hair", 131: "AL/cloth", 136: "AL/cloth_alpha"}
WORKSPACE = Path(__file__).resolve().parents[2]
SOURCE = GAME / "AmanatsuLocation_Data/globalgamemanagers.assets"
TEMPLATE = GAME / "lib/ma/te/c/000_08/00.unity3d"
TYPE_TREE_SOURCE = GAME / "lib/ma/pre/sc/000_08/02.unity3d"


def constant_buffer_register_count(code):
    _, instructions = decode_program(code)
    return 1 + max(instruction[2] for instruction in instructions
                   if instruction[0] & OPCODE_MASK == 89)


def index(snapshot):
    d = segments(snapshot, 0)
    count = U32.unpack_from(d[0])[0]
    return d, list(ROW.iter_unpack(d[0][4:4 + count * ROW.size]))


def patches_for(snapshot, data, rows, fuse_skin, full_fusion, shader_map_lights, authored_direction, map_directionals=False, map_ray_visibility=False, cap_profile="legacy", surface_map_lights=False, map_raster_shadows=False, cloth_aggregate_cap=False, cloth_preserve_color=False):
    name = snapshot["m_ParsedForm"]["m_Name"]
    count = {"AL/skin_head": 64, "AL/skin_body": 64, "AL/hair": 128,
             "AL/cloth": 320, "AL/cloth_alpha": 320}[name]
    replacements = {}
    for slot, references in blob_references(snapshot["m_ParsedForm"]).items():
        eligible = [keywords for _, _, pass_name, stage, keywords in references
                    if pass_name == "UniversalForward" and stage == "progFragment"
                    and "_FORWARD_PLUS" in keywords and "DOTS_INSTANCING_ON" not in keywords]
        if not eligible:
            continue
        offset, size, segment = rows[slot]
        wrapper = data[segment][offset:offset + size]
        info, = containers(wrapper, 0, len(wrapper))
        if info.shader_model != 0x50 or info.code_tag != "SHEX":
            raise ValueError(f"Unexpected DXBC program at entry {slot}")
        original = wrapper[info.start:info.end]
        if dxbc_checksum(original[20:]) != original[4:20]:
            raise ValueError(f"Unexpected DXBC checksum at entry {slot}")
        length_field, = [pos for pos in range(0, info.start - 3, 4)
                         if U32.unpack_from(wrapper, pos)[0] == info.end - pos - 4]
        is_skin = name in SKIN.values()
        # Conventional instancing uses a different loop layout in cloth and
        # hair. Keep their audited early rejection and original traversal.
        full = full_fusion and (is_skin or all("INSTANCING_ON" not in k for k in eligible))
        code = info.code
        expected_lights, max_tail = 6, 7
        if full:
            code = fuse_all_lobes(code)
            expected_lights, max_tail = 2, 12
        elif is_skin and fuse_skin:
            code = fuse_skin_lobes(code)
            expected_lights, max_tail = 4, 11
        validate_loops(code, expected_lights=expected_lights, max_tail=max_tail)
        code = reject_zero_lights(code, expected_lights=expected_lights, max_tail=max_tail)
        if is_skin:
            code = patch_environment_program(code, expected_lights=expected_lights,
                                             locate_light_mix=locate_fused_mix if full else locate_mix,
                                             authored_direction=authored_direction or map_raster_shadows)
        if shader_map_lights and is_skin:
            code = use_map_layer(code, expected_lights=expected_lights, early_reject=True)
        if map_directionals and is_skin:
            code = use_authored_directionals(code, main_shadow=map_raster_shadows)
        if is_skin:
            code = apply_cap_profile(code, cap_profile)
        elif surface_map_lights:
            code = use_surface_map_lights(code, expected_lights=expected_lights,
                                          early_reject=True, cap_profile=cap_profile)
        if name in ('AL/cloth', 'AL/cloth_alpha'):
            code = adjust_cloth_response(code, fused=full, aggregate=cloth_aggregate_cap,
                                         preserve_color=cloth_preserve_color, cap_profile=cap_profile)
        chunks = list(parts(original))
        signature = None
        if map_ray_visibility and is_skin:
            signature, = [old for tag,old in chunks if tag == b'ISGN']
            code, signature = use_ray_visibility(code, signature, 14 if name == 'AL/skin_head' else 13)
        replacement = build_container([(tag, code if tag == b"SHEX" else
                                        signature if tag == b'ISGN' and signature is not None else old)
                                       for tag, old in chunks])
        header = bytearray(wrapper[:info.start])
        if (authored_direction or map_directionals) and is_skin:
            # Unity builds the input binding ranges from the platform wrapper
            # in addition to the DXBC declarations and parameter records.
            cb_count = info.start - 36
            if cb_count < 0 or header[cb_count] != constant_buffer_register_count(info.code):
                raise ValueError(f"Unexpected constant-buffer range in shader entry {slot}")
            header[cb_count] = constant_buffer_register_count(code)
        U32.pack_into(header, length_field, len(header) - length_field - 4 + len(replacement))
        padding = (-(len(header) + len(replacement))) % 4
        replacements[slot] = header + replacement + bytes(padding) + wrapper[(info.end + 3) & ~3:]
    if len(replacements) != count:
        raise ValueError(f"Expected {count} supported {name} variants, found {len(replacements)}")
    return replacements


def attach_map_parameters(snapshot, data, rows, replacements, *, directionals=False, ray_visibility=False, expected_tables=32):
    selected, other = set(), set()
    passes = []
    for sub in snapshot["m_ParsedForm"]["m_SubShaders"]:
        for index, pass_data in enumerate(sub["m_Passes"]):
            for stage, program in pass_data.items():
                if not stage.startswith("prog"):
                    continue
                for variants, params in zip(program["m_PlayerSubPrograms"], program["m_ParameterBlobIndices"], strict=True):
                    for item, slot in zip(variants, params, strict=True):
                        if stage == "progFragment" and item["m_BlobIndex"] in replacements:
                            selected.add(slot)
                            if not any(owner is sub and pos == index for owner, pos in passes):
                                passes.append((sub, index))
                        else:
                            other.add(slot)
    if len(selected) != expected_tables or selected & other or len(passes) != 1:
        raise ValueError(f"Expected {expected_tables} exclusive Forward+ parameter tables, found {len(selected)}")
    if selected & replacements.keys():
        raise ValueError("Shader program and parameter blob indices overlap")
    sub, index = passes[0]
    sub["m_Passes"][index] = append_common_metadata(sub["m_Passes"][index], directionals=directionals, ray_visibility=ray_visibility)
    for slot in selected:
        offset, size, segment = rows[slot]
        replacements[slot] = append_map_buffer(data[segment][offset:offset + size], directionals=directionals, ray_visibility=ray_visibility)


def repack(snapshot, data, rows, replacements):
    updated = list(rows)
    blocks = []
    for segment, original in enumerate(data):
        cursor = 0
        dest = bytearray()
        for offset, size, slot in sorted((o, n, i) for i, (o, n, s) in enumerate(rows) if s == segment):
            if offset < cursor or offset + size > len(original):
                raise ValueError(f"Overlapping or out-of-range program {slot}")
            dest.extend(original[cursor:offset])
            program = replacements.get(slot, original[offset:offset + size])
            updated[slot] = (len(dest), len(program), segment)
            dest.extend(program)
            cursor = offset + size
        dest.extend(original[cursor:])
        blocks.append(dest)
    for i, row in enumerate(updated):
        ROW.pack_into(blocks[0], 4 + i * ROW.size, *row)
    packed = bytearray()
    for i, block in enumerate(blocks):
        compressed = lz4.block.compress(bytes(block), store_size=False)
        snapshot["offsets"][0][i] = len(packed)
        snapshot["compressedLengths"][0][i] = len(compressed)
        snapshot["decompressedLengths"][0][i] = len(block)
        packed.extend(compressed)
    snapshot["compressedBlob"] = bytes(packed)


def copy_stock_shaders(source, targets, bundle_name):
    """Create the Unity bundle catalog and copy the stock shaders and their dependencies."""
    stock = load(str(source)).file
    map_bundle = load(str(TYPE_TREE_SOURCE)).file
    shader_type = map_bundle.files["BuildPlayer-map002.sharedAssets"].objects[206].serialized_type
    bundle = load(str(TEMPLATE)).file
    asset_file = next(f for f in bundle.files.values() if hasattr(f, "objects"))
    catalog = asset_file.objects[1]
    catalog_tree = catalog.read_typetree()
    asset_file.types = [catalog.serialized_type, shader_type]
    catalog.type_id = 0
    asset_file.objects = {1: catalog}

    # These dependencies are compiled support shaders living in the same
    # serialized file. Leave their names and inter-object references intact.
    assets = {80, 100, 153, *targets}
    if any(path_id in SURFACES for path_id in targets):
        default_resource = stock.externals[0]
        if default_resource.path != "Library/unity default resources":
            raise ValueError("Unexpected built-in shader resource path")
        asset_file.externals = [default_resource]
    expected = {}
    for path_id in sorted(assets):
        obj = stock.objects[path_id]
        snapshot = obj.read_typetree(check_read=False)
        dependencies = snapshot["m_Dependencies"] + [v for _, v in snapshot["m_NonModifiableTextures"]]
        if any(not (p["m_FileID"] == 0 and p["m_PathID"] in assets
                    or path_id in SURFACES and p == {"m_FileID": 1, "m_PathID": 17})
               for p in dependencies):
            raise ValueError(f"Unpackaged shader dependency at {path_id}")
        copy = evolve(obj, assets_file=asset_file, serialized_type=shader_type, type_id=1)
        asset_file.objects[path_id] = copy
        expected[path_id] = snapshot

    names = [f"assets/al_npr/{name.split('/')[1]}.shader" for name in targets.values()]
    pointer = lambda path_id: {"m_FileID": 0, "m_PathID": path_id}
    preload = [pointer(path_id) for path_id in sorted(assets)]
    catalog_tree.update(m_Name=bundle_name, m_AssetBundleName=bundle_name,
                        m_PreloadTable=preload, m_Container=[
                            (name, dict(preloadIndex=0, preloadSize=len(preload), asset=pointer(path_id)))
                            for name, path_id in zip(names, targets, strict=True)])
    catalog.save_typetree(catalog_tree)
    return bundle, asset_file, expected, catalog_tree


def build(source, output, skin_only, fuse_skin, full_fusion, shader_map_lights, map_directional, map_directionals=False, map_ray_visibility=False, cap_profile="legacy", surface_map_lights=False, map_raster_shadows=False, cloth_aggregate_cap=False, cloth_preserve_color=False):
    targets = SKIN if skin_only else {**SKIN, **SURFACES}
    bundle_name = ("al-skin-map-ray-visibility" if map_ray_visibility else
                   "al-skin-map-directionals" if map_directionals else "al-skin-lighting")
    bundle, asset_file, expected, catalog_tree = copy_stock_shaders(source, targets, bundle_name)
    requirements = {}
    for path_id, name in targets.items():
        snapshot = expected[path_id]
        if snapshot["m_ParsedForm"]["m_Name"] != name or snapshot["platforms"] != [4]:
            raise ValueError(f"Unexpected shader object {path_id}")
        data, rows = index(snapshot)
        is_skin = name in SKIN.values()
        authored_direction = map_directional and is_skin
        replacements = patches_for(snapshot, data, rows, fuse_skin, full_fusion, shader_map_lights, authored_direction, map_directionals, map_ray_visibility, cap_profile, surface_map_lights, map_raster_shadows, cloth_aggregate_cap, cloth_preserve_color)
        if authored_direction or map_directionals and is_skin:
            attach_map_parameters(snapshot, data, rows, replacements, directionals=map_directionals, ray_visibility=map_ray_visibility)
        requirements[path_id] = (data, rows, replacements)
        repack(snapshot, data, rows, replacements)
        suffix = "Environment"
        if map_ray_visibility and is_skin:
            suffix = "MapRayVisibilityEnvironment"
        elif map_raster_shadows and is_skin:
            suffix = "MapRasterShadowsEnvironment"
        elif map_directionals and is_skin:
            suffix = "MapDirectionalsEnvironment"
        elif authored_direction:
            suffix = "MapDirectionalEnvironment"
        elif shader_map_lights and is_skin or surface_map_lights and not is_skin:
            suffix = "MapEnvironment"
        snapshot["m_ParsedForm"]["m_Name"] = f"{name}/{suffix}"

    for path_id, snapshot in expected.items():
        asset_file.objects[path_id].save_typetree(snapshot)

    cab = "CAB-" + hashlib.sha256(b"".join(asset_file.objects[p].data for p in targets)).hexdigest()[:32]
    bundle.files = {cab: asset_file}
    output.write_bytes(bundle.save(packer="lz4"))
    result = load(output.read_bytes()).file.files[cab]
    if set(result.objects) != {1, *expected} or result.objects[1].read_typetree() != catalog_tree:
        raise ValueError("Unexpected shader bundle inventory")
    for path_id, snapshot in expected.items():
        edited = result.objects[path_id].read_typetree()
        different = [key for key in snapshot if key != "compressedBlob" and edited[key] != snapshot[key]]
        if different or bytes(edited["compressedBlob"]) != bytes(snapshot["compressedBlob"]):
            raise ValueError(f"Unexpected shader round-trip at path {path_id}: {different}")
        if path_id not in targets:
            continue
        data, old_rows, replacements = requirements[path_id]
        new_data, new_rows = index(edited)
        for slot, ((o, n, s), (o2, n2, s2)) in enumerate(zip(old_rows, new_rows, strict=True)):
            expected = replacements.get(slot, data[s][o:o + n])
            if new_data[s2][o2:o2 + n2] != expected:
                raise ValueError(f"Round-trip failed at path {path_id}, entry {slot}")
        print(f"{targets[path_id]}: {len(replacements)} updated pixel program or parameter blobs")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--skin-only", action="store_true", help="Omit the early-rejection cloth and hair variants")
    fusion = parser.add_mutually_exclusive_group()
    fusion.add_argument("--fuse-skin-lobes", action="store_true", help="Share the last two stock skin light traversals")
    fusion.add_argument("--full-light-fusion", action="store_true", help="Share all three light traversals in audited variants")
    parser.add_argument("--shader-map-lights", action="store_true", help="Select map lights inside the Forward+ skin shaders")
    directional = parser.add_mutually_exclusive_group()
    directional.add_argument("--map-directional", action="store_true", help="Include an authored map directional omitted from Forward+")
    directional.add_argument("--map-directionals", action="store_true", help="Replace stock directional traversal with an authored map list")
    parser.add_argument("--map-ray-visibility", action="store_true", help="Use depth-matched directional visibility texture (experimental)")
    parser.add_argument("--map-raster-shadows", action="store_true", help="Sample the main shadow atlas for its matching authored directional")
    parser.add_argument("--cap-profile", choices=PROFILES, default="legacy")
    parser.add_argument("--surface-map-lights", action="store_true", help="Experimental map additional lights and per-light cap for hair and clothing")
    parser.add_argument("--cloth-aggregate-cap", action="store_true", help="Bound summed extra lighting in clothing only")
    parser.add_argument("--cloth-preserve-color", action="store_true", help="Remove clothing's extra-light material-color gain and floor")
    args = parser.parse_args()
    if args.surface_map_lights and (args.skin_only or not args.shader_map_lights or args.cap_profile == "legacy"):
        parser.error("Surface map lights require a full-character shader-map build and an experimental cap profile")
    if (args.cloth_aggregate_cap or args.cloth_preserve_color) and not args.surface_map_lights:
        parser.error("Cloth response experiments require --surface-map-lights")
    if args.cap_profile != "legacy" and not args.map_directionals:
        parser.error("Experimental cap profiles require --map-directionals")
    if args.map_ray_visibility and not args.map_directionals:
        parser.error('--map-ray-visibility requires --map-directionals')
    if args.map_raster_shadows and (not args.map_directionals or args.map_ray_visibility):
        parser.error('--map-raster-shadows requires --map-directionals and cannot combine with ray visibility')
    if (args.map_directional or args.map_directionals) and not (args.full_light_fusion and args.shader_map_lights):
        parser.error("Directional modes require --full-light-fusion and --shader-map-lights")
    source, output = args.source.resolve(strict=True), args.output.resolve()
    if source == output or not output.is_relative_to(WORKSPACE):
        parser.error("Use a distinct output inside the workspace")
    if file_sha(source) != STOCK:
        parser.error("Source SHA-256 differs from the audited AL 1.0.4 assets")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=output.parent, prefix=output.name + ".", delete=False) as f:
        temp = Path(f.name)
    try:
        build(source, temp, args.skin_only, args.fuse_skin_lobes, args.full_light_fusion, args.shader_map_lights, args.map_directional, args.map_directionals, args.map_ray_visibility, args.cap_profile, args.surface_map_lights, args.map_raster_shadows, args.cloth_aggregate_cap, args.cloth_preserve_color)
        digest = file_sha(temp)
        temp.replace(output)
        print(f"{digest}  {output}")
    finally:
        temp.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
