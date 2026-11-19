"""Build the current per-light skin and clothing default from local AL 1.0.4 assets."""
import hashlib
from pathlib import Path
import subprocess
import sys

from build_skin_assets import WORKSPACE
from build_toon_band_trials import BASE, build as skin
from build_toon_cloth_trials import build as cloth, retune
from build_view_band_trial import build as view
from build_material_response import build as material_response


if __name__ == "__main__":
    out = WORKSPACE / "artifacts/npr/default-build"
    out.mkdir(parents=True, exist_ok=True)
    stock_skin, stock_cloth = (out / f"{name}.unity3d" for name in ("skin-source", "cloth-source"))
    builder = [sys.executable, str(Path(__file__).with_name("build_skin_assets.py")),
               "--full-light-fusion", "--shader-map-lights", "--map-directionals"]
    subprocess.run([*builder, "--skin-only", "--output", stock_skin], check=True)
    subprocess.run([*builder, "--map-raster-shadows", "--cap-profile", "color-aware", "--surface-map-lights",
                    "--cloth-aggregate-cap", "--cloth-preserve-color", "--output", stock_cloth], check=True)
    digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    if digest(stock_skin) != BASE or digest(stock_cloth) != "e2639d68a0950dc05ff7eda1dff8ebed45ffa2c2e20ee179f3370640792344a1":
        raise ValueError("Unexpected intermediate bundle")
    skin(stock_skin, out / "individual.unity3d", True)
    cloth(stock_cloth, out, "individual", bright_fabric=True)
    retune(out, "individual", .70)
    final = out / "al-skin-lighting.unity3d"
    previous = out / "per-light-nov18.unity3d"
    view(out / "paired-individual-soft.unity3d", previous)
    material_response(previous, final)
    if digest(final) != "eae7b1bf2fc63a742e1d09848a661eb927495643aee9e8f95b757085ed0f1a88":
        raise ValueError("Default differs from the live-tested bundle")
    print(final)
