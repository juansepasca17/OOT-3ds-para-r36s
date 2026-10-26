"""Summarize console benchmark results as one Markdown table.

    python scripts/summarize_results.py work/devserver/results/007-vfp [--base v110]

Reads every bench_*.json under the given directories (recursively) and prints
frame-time p50/mean/p95, fps and, with --base, the change against the runs
whose name starts with that prefix. Runs named NAME_a, NAME_b... are also
averaged into one NAME row, so A/B pairs read at a glance.
"""
from __future__ import annotations

import argparse
import json
import re
import statistics
import sys
from pathlib import Path


def frame_times(data):
    if isinstance(data, dict):
        if "frame_times" in data and isinstance(data["frame_times"], dict):
            return data["frame_times"]
        for value in data.values():
            found = frame_times(value)
            if found:
                return found
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("dirs", nargs="+", type=Path)
    parser.add_argument("--base", help="run-name prefix used as the reference")
    args = parser.parse_args()

    runs: dict[str, dict] = {}
    for directory in args.dirs:
        for path in sorted(directory.rglob("*bench_*.json")):
            times = frame_times(json.loads(path.read_text(encoding="utf-8")))
            if times is None:
                print(f"(sin frame_times: {path})", file=sys.stderr)
                continue
            name = path.stem.replace("bench_", "", 1)
            if len(args.dirs) > 1:
                name = f"{directory.name}/{name}"
            runs[name] = times

    if not runs:
        print("no bench_*.json found", file=sys.stderr)
        return 1

    groups: dict[str, list[float]] = {}
    for name, times in runs.items():
        group = re.sub(r"_[a-z]$", "", name)
        if group != name:
            groups.setdefault(group, []).append(times["p50_upper_ms"])

    base = None
    if args.base:
        values = [t["p50_upper_ms"] for n, t in runs.items() if n.split("/")[-1].startswith(args.base)]
        base = statistics.mean(values) if values else None

    def change(p50: float) -> str:
        return f"{(base / p50 - 1) * 100:+.1f} %" if base else ""

    print("| Prueba | p50 ms | media ms | p95 ms | fps (p50) | vs base |")
    print("|---|---|---|---|---|---|")
    for name, times in runs.items():
        p50 = times["p50_upper_ms"]
        print(f"| {name} | {p50:.1f} | {times['mean_ms']:.1f} | {times['p95_upper_ms']:.1f} "
              f"| {1000 / p50:.1f} | {change(p50)} |")
    for group, values in groups.items():
        if len(values) > 1:
            p50 = statistics.mean(values)
            spread = max(values) - min(values)
            print(f"| **{group} (media de {len(values)})** | **{p50:.1f}** ±{spread / 2:.1f} | | "
                  f"| **{1000 / p50:.1f}** | {change(p50)} |")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
