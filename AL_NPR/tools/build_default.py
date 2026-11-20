"""Prepare AL 1.0.4 Unity variants for the shared Slang lighting functions."""

import argparse
from pathlib import Path

from build_skin_assets import SOURCE, STOCK, WORKSPACE, build as build_assets, file_sha
from build_toon_band_trials import BASE, build as skin
from build_toon_cloth_trials import build as cloth, retune
from build_view_band_trial import build as view
from build_material_response import UNBENT_SHA, build as material_response


def prepare_variants(out):
    if file_sha(SOURCE) != STOCK:
        raise ValueError(f"Expected Amanatsu Location 1.0.4 assets at {SOURCE}")
    out.mkdir(parents=True, exist_ok=True)
    stock_skin = out / "skin-source.unity3d"
    stock_cloth = out / "cloth-source.unity3d"
    common = dict(fuse_skin=False, full_fusion=True, shader_map_lights=True,
                  map_directional=False, map_directionals=True)
    build_assets(SOURCE, stock_skin, skin_only=True, **common)
    build_assets(SOURCE, stock_cloth, skin_only=False, map_raster_shadows=True,
                 cap_profile="color-aware", surface_map_lights=True, cloth_aggregate_cap=True,
                 cloth_preserve_color=True, **common)
    if file_sha(stock_skin) != BASE or file_sha(stock_cloth) != "e2639d68a0950dc05ff7eda1dff8ebed45ffa2c2e20ee179f3370640792344a1":
        raise ValueError("Unexpected intermediate game variants")
    skin(stock_skin, out / "individual.unity3d", True)
    cloth(stock_cloth, out, "individual", bright_fabric=True)
    retune(out, "individual", .70)
    unbent = out / "paired-individual-soft.unity3d"
    if file_sha(unbent) != UNBENT_SHA:
        raise ValueError("Unexpected input to the Slang variant linker")
    return unbent


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=WORKSPACE / "artifacts/npr/default-build")
    parser.add_argument("--prepare-only", action="store_true", help="Build the input for the Slang variant linker")
    args = parser.parse_args()
    out = args.output_dir
    unbent = prepare_variants(out)
    if not args.prepare_only:
        previous = out / "per-light-nov18.unity3d"
        view(unbent, previous)
        material_response(previous, out / "per-light-camera-bend.unity3d")
        final = out / "al-skin-lighting.unity3d"
        material_response(unbent, final)
        print(final)
