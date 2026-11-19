"""Compile the character shader programs listed in the Slang source manifest."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


SOURCE = Path(__file__).resolve().parents[1] / "shaders" / "slang"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--slangc", default="slangc")
    parser.add_argument("--fxc", default="fxc", help="Windows SDK FXC executable for DXBC output")
    parser.add_argument("--target", choices=["dxbc", "dxil"], default="dxbc")
    parser.add_argument("--program", action="append", help="Build just this manifest entry (repeatable)")
    parser.add_argument("--filter-body-oil", action="store_true", help="Use cubic reconstruction for the painted body mask")
    args = parser.parse_args()
    programs = json.loads((SOURCE / "programs.json").read_text())
    selected = args.program or list(programs)
    for name in selected:
        if name not in programs:
            parser.error(f"Unknown program {name}")
    args.output.mkdir(parents=True, exist_ok=True)
    profile = "sm_6_0" if args.target == "dxil" else "sm_5_0"
    sources = {programs[name]["file"]: programs[name]["stage"] for name in selected}
    with tempfile.TemporaryDirectory(dir=args.output) as temporary:
        def compile_stage(source):
            stage = sources[source]
            path = Path(temporary) / Path(source).with_suffix("." + args.target)
            path.parent.mkdir(parents=True, exist_ok=True)
            dxbc = args.target == "dxbc"
            intermediate = path.with_suffix(".hlsl") if dxbc else path
            defines = ["-DFILTER_BODY_OIL=1"] if args.filter_body_oil and source == "Body/ForwardPS.slang" else []
            subprocess.run([args.slangc, str(SOURCE / source), "-I", str(SOURCE),
                            "-stage", stage, "-entry", "main", "-profile", profile,
                            *defines, "-fp-mode", "precise", "-target", "hlsl" if dxbc else "dxil",
                            "-o", str(intermediate)], check=True)
            if dxbc:
                # FXC's optimizer folds loops carrying Unity's integer masks in float lanes.
                # Keep the bit-preserving build for comparison against the native programs.
                shader_profile = "vs_5_0" if stage == "vertex" else "ps_5_0"
                subprocess.run([args.fxc, "/nologo", "/Od", "/Gis", "/T", shader_profile,
                                "/E", "main", "/Fo", str(path), str(intermediate)], check=True,
                               stdout=subprocess.DEVNULL)
            return path

        with ThreadPoolExecutor(max_workers=4) as pool:
            binaries = dict(zip(sources, pool.map(compile_stage, sources)))
        for name in selected:
            binary = binaries[programs[name]["file"]]
            shutil.copyfile(binary, args.output / (name + binary.suffix))
    print(f"Compiled {len(sources)} distinct stage entries for {len(selected)} programs ({profile}).")


if __name__ == "__main__":
    main()
