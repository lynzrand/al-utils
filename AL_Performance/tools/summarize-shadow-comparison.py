"""Compare repeated AL Performance runs without pooling unlike scene states.

This checks the state the plugin records, not light/caster equivalence or visual
correctness. Those checks belong to the capture procedure in README.shadows.md.
"""

import argparse
import csv
import json
import math
from pathlib import Path
from statistics import fmean, median


STATE_FIELDS = (
    "Scene", "Api", "Gpu", "Width", "Height", "VSync", "TargetFrameRate",
    "TimeScale", "UnityFrameTiming", "URP", "Cameras",
)
TIMINGS = ("FrameIntervalMs", "UnityCpuFrameMs", "UnityGpuFrameMs", "UnityMainThreadMs", "UnityRenderThreadMs")


def timing_summary(rows, column):
    values = []
    for row in rows:
        value = row[column]
        if not value:
            if column == "FrameIntervalMs":
                raise ValueError("Missing frame interval")
            continue
        value = float(value)
        if not math.isfinite(value):
            raise ValueError(f"Nonfinite timing in {column}")
        if value > 0:
            values.append(value)
        elif column == "FrameIntervalMs":
            raise ValueError("Nonpositive frame interval")
    if not values:
        return None
    values.sort()
    return {
        "n": len(values),
        "mean": fmean(values),
        "p50": values[math.ceil(len(values) * 0.50) - 1],
        "p95": values[math.ceil(len(values) * 0.95) - 1],
    }


def read_run(path, group):
    metadata = json.loads(path.read_text(encoding="utf-8-sig"))
    with path.with_suffix(".csv").open(newline="", encoding="utf-8-sig") as source:
        rows = list(csv.DictReader(source))
    if not rows or len(rows) != metadata["Samples"]:
        raise ValueError(f"{path}: empty or incomplete CSV")
    return {
        "path": path, "group": group, "metadata": metadata,
        "stats": {column: timing_summary(rows, column) for column in TIMINGS},
    }


def state_differences(expected, actual, path):
    """Name the changed leaf without weakening the exact recorded-state check."""
    if isinstance(expected, dict) and isinstance(actual, dict):
        for key in sorted(expected.keys() | actual.keys()):
            child = f"{path}.{key}"
            if key not in expected or key not in actual:
                yield f"{child}: field missing from one snapshot"
            else:
                yield from state_differences(expected[key], actual[key], child)
    elif isinstance(expected, list) and isinstance(actual, list):
        if len(expected) != len(actual):
            yield f"{path}: length {len(expected)} -> {len(actual)}"
        for index, (left, right) in enumerate(zip(expected, actual)):
            yield from state_differences(left, right, f"{path}[{index}]")
    elif expected != actual:
        yield f"{path}: {expected!r} -> {actual!r}"


def compare_recorded_state(runs):
    problems = []
    reference = runs[0]["metadata"]["Start"]
    for run in runs:
        for endpoint in ("Start", "End"):
            state = run["metadata"][endpoint]
            label = f"{run['path'].stem} {endpoint}"
            if not state["Focused"]:
                problems.append(f"{label}: game was unfocused")
            for field in STATE_FIELDS:
                problems.extend(f"{label}: {difference} (first run Start -> snapshot)"
                                for difference in state_differences(reference[field], state[field], field))
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--a", nargs="+", type=Path, required=True, help="Baseline JSON runs")
    parser.add_argument("--b", nargs="+", type=Path, required=True, help="Candidate JSON runs")
    args = parser.parse_args()
    paths = args.a + args.b
    if len({path.resolve() for path in paths}) != len(paths):
        parser.error("Each run must be listed exactly once")
    if min(len(args.a), len(args.b)) < 2:
        parser.error("Provide at least two runs per condition, preferably in A/B/B/A order")
    try:
        runs = [read_run(path, group) for group, paths in (("A", args.a), ("B", args.b)) for path in paths]
        runs.sort(key=lambda run: run["metadata"]["Start"]["At"])
        problems = compare_recorded_state(runs)
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.error(str(error))

    print("Recorded order:", "/".join(run["group"] for run in runs))
    first = runs[0]["metadata"]["Start"]
    print(f"{first['Scene']} {first['Api']} {first['Width']}x{first['Height']} "
          f"scale={first['URP']['renderScale']} MSAA={first['URP']['msaaSampleCount']} "
          f"TimeScale={first['TimeScale']}")
    for run in runs:
        stats = run["stats"]
        frame = stats["FrameIntervalMs"]
        print(f"{run['group']} {run['path'].stem}: {1000 / frame['mean']:.2f} FPS, "
              f"frame p50/p95={frame['p50']:.3f}/{frame['p95']:.3f} ms (n={frame['n']})")
        for column in TIMINGS[1:]:
            values = stats[column]
            print(f"  {column}: " + (
                f"p50/p95={values['p50']:.3f}/{values['p95']:.3f} ms "
                f"({values['n']}/{frame['n']} positive samples)" if values else "unavailable"))

    if problems:
        print("Comparison rejected; individual timings above are not a matched A/B result:")
        for problem in problems:
            print("  " + problem)
        return 2

    print("Recorded state matches. Light/caster lists, animation, visual output, and error rates still need review.")
    print("FrameIntervalMs measures wall-clock frame cadence; it is not CPU work time or GPU duration.")
    print("B minus A, using the median of per-run percentiles (negative means less time):")
    for column in TIMINGS:
        a = [run["stats"][column] for run in runs if run["group"] == "A"]
        b = [run["stats"][column] for run in runs if run["group"] == "B"]
        if any(value is None for value in a + b):
            print(f"  {column}: unavailable in at least one run")
            continue
        for percentile in ("p50", "p95"):
            left, right = median(value[percentile] for value in a), median(value[percentile] for value in b)
            print(f"  {column} {percentile}: {left:.3f} -> {right:.3f} ms, "
                  f"delta {right - left:+.3f} ms ({100 * (right / left - 1):+.2f}%)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
