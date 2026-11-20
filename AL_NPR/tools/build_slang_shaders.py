"""Build selected Slang programs into a flat output directory using CMake and Ninja."""

import argparse
import json
from pathlib import Path
import shutil
import subprocess

SOURCE = Path(__file__).resolve().parents[1] / "shaders/slang"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--slangc", help="Slang compiler executable")
    parser.add_argument("--fxc", help="Windows SDK compiler executable for DXBC")
    parser.add_argument("--target", choices=["dxbc", "dxil"], default="dxbc")
    parser.add_argument("--shading", choices=["npr", "stock"], default="npr")
    parser.add_argument("--dxil-profile", default="sm_6_0", help="Shader model and optional +capability for DXIL")
    parser.add_argument("--program", action="append", help="Manifest program to build (repeatable)")
    parser.add_argument("--filter-body-oil", action="store_true", help="Use the release's painted body filter")
    args = parser.parse_args()

    programs = json.loads((SOURCE / "programs.json").read_text())
    selected = args.program or list(programs)
    for name in selected:
        if name not in programs:
            parser.error(f"Unknown program {name}")

    work = args.output / ".cmake" / args.target / args.shading
    options = [f"-DSHADER_TARGET={args.target}", f"-DSHADING={args.shading}",
               f"-DDXIL_PROFILE={args.dxil_profile}",
               "-DFILTER_BODY_OIL=" + ("ON" if args.filter_body_oil else "OFF")]
    for variable, executable in [("SLANGC", args.slangc), ("FXC", args.fxc)]:
        if executable:
            path = shutil.which(executable)
            if path is None:
                parser.error(f"Cannot find compiler {executable}")
            options.append(f"-D{variable}={Path(path).resolve()}")
    subprocess.run(["cmake", "-S", SOURCE, "-B", work, "-G", "Ninja", *options], check=True)
    subprocess.run(["cmake", "--build", work, "--parallel", "4", "--target",
                    *(args.program or ["shaders"])], check=True)
    for name in selected:
        binary = work / f"{name}.{args.target}"
        shutil.copyfile(binary, args.output / binary.name)


if __name__ == "__main__":
    main()
