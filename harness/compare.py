#!/usr/bin/env python3
"""Compares harness result files: each number's median per file, and the largest gap between them.

python3 -I harness/compare.py harness/results/A.json harness/results/B.json
"""
import json
import sys

KEYS = {
    "s1_start": ["p50_ms"],
    "s2_scroll_tasks": ["gap_p50_ms", "gap_p99_ms", "gaps_over_25ms", "cpu_percent", "footprint_mb_mean", "footprint_mb_max"],
    "s3_scroll_keluarga": ["gap_p50_ms", "gap_p99_ms", "gaps_over_25ms", "cpu_percent", "footprint_mb_mean", "footprint_mb_max"],
    "s4_idle": ["cpu_percent", "footprint_mb_mean", "footprint_mb_max"],
}


def value(app, scenario, key):
    part = app[scenario]
    if "summary" in part:
        entry = part["summary"].get(key)
        return entry["median"] if entry else None, entry["spread"] if entry else None
    return part.get(key), part.get("spread")


def main(paths):
    files = [json.load(open(path))["apps"] for path in paths]
    print(f"{'app':9} {'number':34} " + " ".join(f"{'run ' + str(i + 1):>16}" for i in range(len(files))) + "   between")
    for name in files[0]:
        for scenario, keys in KEYS.items():
            for key in keys:
                pairs = [value(apps[name], scenario, key) for apps in files]
                medians = [m for m, _ in pairs if m is not None]
                between = (max(medians) - min(medians)) / max(medians) if medians and max(medians) else 0
                cells = " ".join(f"{m:9.2f} ±{s * 100:4.0f}%" if m is not None else f"{'-':>16}" for m, s in pairs)
                print(f"{name:9} {scenario + '.' + key:34} {cells}   {between * 100:5.1f}%")


if __name__ == "__main__":
    main(sys.argv[1:])
