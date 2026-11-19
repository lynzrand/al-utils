"""Package the six Windows release downloads from Release builds."""
import argparse
import hashlib
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


ROOT = Path(__file__).resolve().parents[1]


def package(output, name, files):
    archive = output / (name + ".zip")
    with ZipFile(archive, "w", ZIP_DEFLATED) as zipped:
        for source, destination in files:
            zipped.write(source, destination)
    with ZipFile(archive) as zipped:
        if zipped.testzip() or set(zipped.namelist()) != {dst for _, dst in files}:
            raise RuntimeError(f"Invalid package: {archive}")
    return archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("lighting_patch", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    archives = []
    for name, project in (("AL_PovX", "."), ("AL_NPR", "AL_NPR"), ("AL_VR", "AL_VR"),
                          ("AL_Performance", "AL_Performance"), ("AL_DevRepl", "AL_DevRepl"),
                          ("AL_RenderDocPreloader", "AL_Performance/RenderDocPreloader")):
        directory = ROOT / project
        prefix = f"BepInEx/plugins/{name}/"
        if name == "AL_RenderDocPreloader":
            prefix = "BepInEx/patchers/AL_RenderDocPreloader/"
        dll_target = ("BepInEx/patchers/" if name == "AL_RenderDocPreloader" else prefix) + name + ".dll"
        items = [(directory / f"bin/Release/net6.0/{name}.dll", dll_target),
                 (ROOT / "LICENSE", prefix + "LICENSE.txt"),
                 (directory / "README.md", prefix + "README.md")]
        if name == "AL_NPR":
            items += [(directory / "Prepare AL Lighting.cmd", "Prepare AL Lighting.cmd"),
                      (directory / "tools/release_delta.py", prefix + "release_delta.py"),
                      (args.lighting_patch, prefix + "lighting.patch"),
                      (ROOT / "LICENSES/MPL-2.0.txt", prefix + "MPL-2.0.txt"),
                      (ROOT / "LICENSES/README.md", prefix + "LICENSE-NOTICE.md")]
        elif name == "AL_VR":
            items += [(directory / "Launch AL VR.bat", "Launch AL VR.bat")]
            for filename in ("AL_VR_Native.dll", "OpenVR-LICENSE.txt"):
                items.append((directory / "artifacts/plugin/AL_VR" / filename, prefix + filename))
        elif name == "AL_DevRepl":
            for filename in ("Invoke.ps1", "InspectSkinLighting.csx"):
                items.append((directory / filename, prefix + filename))
        elif name == "AL_Performance":
            for filename in ("run-sweep.ps1", "summarize-sweep.py"):
                items.append((directory / "tools" / filename, prefix + "tools/" + filename))
        elif name == "AL_PovX":
            items.append((ROOT / "docs/key-bindings.md", prefix + "docs/key-bindings.md"))
        archives.append(package(args.output, name, items))
    sums = [hashlib.sha256(path.read_bytes()).hexdigest() + "  " + path.name for path in archives]
    (args.output / "SHA256SUMS.txt").write_text("\n".join(sums) + "\n", encoding="ascii")
    print("\n".join(sums))


if __name__ == "__main__":
    main()
