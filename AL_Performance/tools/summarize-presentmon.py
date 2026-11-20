"""Summarize steady-state frame intervals and GPU work from PresentMon CSVs."""

import argparse
import csv
import math
import statistics
from collections import Counter, defaultdict
from pathlib import Path


METRIC_COLUMNS = {
    "Present interval": ("MsBetweenPresents",),
    "CPU frame interval": ("FrameTime", "MsBetweenAppStart"),
    "GPU busy": ("GPUBusy", "MsGPUBusy", "MsGPUActive"),
    "CPU busy": ("CPUBusy", "MsCPUBusy"),
    "CPU wait": ("CPUWait", "MsCPUWait"),
    "Display interval": ("DisplayedTime", "MsBetweenDisplayChange"),
}

TIME_COLUMNS = (
    ("TimeInSeconds", 1.0),
    ("TimeInMs", 0.001),
    ("CPUStartTime", 0.001),
    ("CPUStartTimeInSeconds", 1.0),
    ("CPUStartTimeInMs", 0.001),
    ("CPUStartQPCTime", 0.001),
    ("CPUStartQPCTimeInMs", 0.001),
)


def numeric_value(raw_value):
    if raw_value is None or raw_value.strip().casefold() in {"", "na", "n/a", "nan"}:
        return None
    number = float(raw_value)
    return number if math.isfinite(number) else None


def percentile(ordered, fraction):
    index = (len(ordered) - 1) * fraction
    lower = math.floor(index)
    upper = math.ceil(index)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (index - lower)


def read_swapchains(path, process_name):
    swapchains = defaultdict(list)
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        required_columns = {"application", "processid", "swapchainaddress"}
        columns = {column.casefold() for column in reader.fieldnames or ()}
        if not required_columns.issubset(columns):
            raise ValueError("expected a PresentMon CSV with application, PID, and swap chain")

        for original in reader:
            row = {column.casefold(): value for column, value in original.items() if column is not None}
            app = row["application"]
            if process_name and app.casefold() != process_name.casefold():
                continue
            key = (app, row["processid"], row["swapchainaddress"])
            swapchains[key].append(row)

    if not swapchains:
        raise ValueError("no matching frames")
    return swapchains


def discard_warmup(rows, seconds):
    if not seconds:
        return rows

    for column, scale in TIME_COLUMNS:
        if column.casefold() in rows[0]:
            break
    else:
        raise ValueError("--skip-seconds requires a numeric timestamp in seconds or milliseconds")

    timestamped = [(numeric_value(row[column.casefold()]), row) for row in rows]
    timestamped = [(timestamp, row) for timestamp, row in timestamped if timestamp is not None]
    if not timestamped:
        raise ValueError(f"no usable timestamps in {column}")
    start = min(timestamp for timestamp, _ in timestamped)
    return [row for timestamp, row in timestamped if (timestamp - start) * scale >= seconds]


def summarize(path, process_name, warmup, all_swapchains):
    swapchains = read_swapchains(path, process_name)
    ranked = sorted(swapchains.items(), key=lambda entry: len(entry[1]), reverse=True)
    print(path)

    for (app, pid, address), rows in ranked if all_swapchains else ranked[:1]:
        captured_frames = len(rows)
        rows = discard_warmup(rows, warmup)
        if not rows:
            raise ValueError(f"no frames after warmup on swap chain {address}")

        print(f"  {app}, PID {pid}, swap chain {address}, {len(rows)}/{captured_frames} frames")
        for column in ("SyncInterval", "PresentMode"):
            if column.casefold() in rows[0]:
                distribution = Counter(row[column.casefold()] for row in rows)
                counts = ", ".join(f"{value} ({count})" for value, count in distribution.most_common())
                print(f"  {column}  {counts}")

        print(f"  {'Metric (ms)':<21} {'Samples':>8} {'Mean':>8} {'p50':>8} {'p95':>8} {'p99':>8}")
        for label, candidates in METRIC_COLUMNS.items():
            column = next((candidate.casefold() for candidate in candidates if candidate.casefold() in rows[0]), None)
            if column is None:
                continue

            # A zero duration can represent an absent measurement. CPU wait can legitimately be zero.
            values = [numeric_value(row[column]) for row in rows]
            usable = sorted(
                value for value in values if value is not None and (value > 0 or label == "CPU wait" and value == 0)
            )
            if not usable:
                print(f"  {label:<21} {'0':>8}   unavailable")
                continue

            mean = statistics.fmean(usable)
            p50, p95, p99 = (percentile(usable, fraction) for fraction in (0.50, 0.95, 0.99))
            print(f"  {label:<21} {len(usable):>8} {mean:8.3f} {p50:8.3f} {p95:8.3f} {p99:8.3f}")

    if len(ranked) > 1 and not all_swapchains:
        print(f"  Selected the busiest of {len(ranked)} swap chains by captured frame count.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv", nargs="+", type=Path, help="PresentMon capture CSVs")
    parser.add_argument("--process", help="Match an executable name, e.g. AmanatsuLocation.exe")
    parser.add_argument("--skip-seconds", type=float, default=0.0, help="Discard capture warmup per swap chain")
    parser.add_argument("--all-swapchains", action="store_true", help="Show every swap chain")
    args = parser.parse_args()
    if not math.isfinite(args.skip_seconds) or args.skip_seconds < 0:
        parser.error("--skip-seconds must be a finite, nonnegative number")

    for path in args.csv:
        try:
            summarize(path, args.process, args.skip_seconds, args.all_swapchains)
        except (OSError, ValueError) as error:
            parser.exit(1, f"{path}: {error}\n")


if __name__ == "__main__":
    main()
