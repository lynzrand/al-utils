"""Summarize the in-process AL Performance CSVs alongside their scene metadata."""

import argparse
import csv
import json
import math
from pathlib import Path
from statistics import fmean


def percentile(values, fraction):
    return values[math.ceil(len(values) * fraction) - 1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("prefix")
    args = parser.parse_args()

    for metadata_file in sorted(args.directory.glob(f"{args.prefix}*.json")):
        metadata = json.loads(metadata_file.read_text(encoding="utf-8-sig"))
        if "Samples" not in metadata:
            continue
        with metadata_file.with_suffix(".csv").open(newline="", encoding="utf-8") as source:
            rows = list(csv.DictReader(source))
        intervals = sorted(float(row["FrameIntervalMs"]) for row in rows)
        gpu = sorted(float(value) for row in rows if (value := row["UnityGpuFrameMs"]) and float(value) > 0)
        cpu = sorted(float(value) for row in rows if (value := row["UnityMainThreadMs"]) and float(value) > 0)
        start, end = metadata["Start"], metadata["End"]
        urp = start["URP"]
        valid = all(start[k] == end[k] for k in ("Scene", "Width", "Height", "VSync", "TargetFrameRate"))
        status = "" if start["Focused"] and end["Focused"] and valid else " [scene state/focus changed]"
        gpu_stats = (f" GPU p50/p95 {percentile(gpu, 0.5):.2f}/{percentile(gpu, 0.95):.2f} ms"
                     f" ({len(gpu)}/{len(rows)} positive samples)") if gpu else ""
        cpu_stats = f" main p50 {percentile(cpu, 0.5):.2f} ms" if cpu else ""
        print(
            f"{metadata_file.stem:38} {start['Scene']:13} {start['Api']:10} "
            f"{start['Width']}x{start['Height']} scale={urp['renderScale']:.2f} "
            f"MSAA={urp['msaaSampleCount']} n={len(intervals)} "
            f"{1000 / fmean(intervals):6.1f} FPS  "
            f"p50/p95/p99 {percentile(intervals, 0.5):.2f}/{percentile(intervals, 0.95):.2f}/"
            f"{percentile(intervals, 0.99):.2f} ms{gpu_stats}{cpu_stats}{status}"
        )


if __name__ == "__main__":
    main()
