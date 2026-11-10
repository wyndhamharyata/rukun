#!/usr/bin/env python3
"""The Tahap A harness: start, scroll, idle, size and build for each app's .app.

python3 -I harness/run.py [--runs 10] [--idle 60] [--scroll-seconds 20] [--apps thor,gpui] [--build]
python3 -I harness/run.py --self-test

Each app opens with `open -n` (not -g), so its window comes to the front: GPUI stops drawing a
covered window. Results go to harness/results/<time>.json and a summary to stdout.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APPS = {
    "thor": ROOT / "apps/thor/build/Rukun.app",
    "electron": ROOT / "apps/electron/out/Rukun-darwin-arm64/Rukun.app",
    "tauri": ROOT / "apps/tauri/src-tauri/target/release/bundle/macos/Rukun.app",
    "gpui": ROOT / "apps/gpui/build/Rukun.app",
}
BUILDS = {
    "thor": ("apps/thor", "rm -rf build && ./thor/bundle.sh Rukun"),
    "electron": ("apps/electron", "rm -rf out .vite && npx electron-forge package"),
    "tauri": ("apps/tauri", "cargo clean --manifest-path src-tauri/Cargo.toml && npx tauri build --bundles app"),
    "gpui": ("apps/gpui", "cargo clean && ./bundle.sh"),
}
# Tauri's web content runs in WebKit XPC services that launchd owns, not the app.
WEBKIT = re.compile(r"com\.apple\.WebKit\.(WebContent|GPU|Networking)")
UNITS = {"B": 1 / 1024, "KB": 1, "MB": 1024, "GB": 1024 * 1024}


def percentile(values, p):
    values = sorted(values)
    if not values:
        return None
    k = (len(values) - 1) * p / 100
    lo, hi = int(k), min(int(k) + 1, len(values) - 1)
    return values[lo] + (values[hi] - values[lo]) * (k - lo)


def parse_footprint_kb(text):
    m = re.search(r"Footprint:\s*([\d.]+)\s*(B|KB|MB|GB)", text)
    return float(m.group(1)) * UNITS[m.group(2)] if m else None


def parse_cpu_seconds(text):
    """ps time= reads [[dd-]hh:]mm:ss.cc."""
    total = 0.0
    for part in text.strip().replace("-", ":").split(":"):
        total = total * 60 + float(part)
    return total


def pids_by_command():
    out = subprocess.run(["ps", "-axo", "pid=,ppid=,command="], capture_output=True, text=True).stdout
    rows = []
    for line in out.splitlines():
        pid, ppid, command = line.split(None, 2)
        rows.append((int(pid), int(ppid), command))
    return rows


class Launch:
    """One run of an app: launched in front, its pids, its stdout file."""

    def __init__(self, name, env):
        self.name = name
        self.exe_dir = str(APPS[name] / "Contents/MacOS")
        self.webkit_before = {pid for pid, _, c in pids_by_command() if WEBKIT.search(c)}
        self.out = Path(tempfile.mkstemp(prefix=f"harness-{name}-", suffix=".txt")[1])
        args = ["open", "-n", "--stdout", str(self.out), "--stderr", "/dev/null"]
        for key, value in env.items():
            args += ["--env", f"{key}={value}"]
        self.start = time.monotonic()
        subprocess.run(args + [str(APPS[name])], check=True)

    def wait_for(self, line, timeout):
        while time.monotonic() - self.start < timeout:
            if line in self.out.read_text(errors="replace").splitlines():
                return time.monotonic() - self.start
            time.sleep(0.005)
        return None

    def pids(self):
        rows = pids_by_command()
        main = {pid for pid, _, c in rows if c.startswith(self.exe_dir)}
        tree, grew = set(main), True
        while grew:
            more = {pid for pid, ppid, _ in rows if ppid in tree} - tree
            tree |= more
            grew = bool(more)
        if self.name == "tauri":
            tree |= {pid for pid, _, c in rows if WEBKIT.search(c)} - self.webkit_before
        return tree

    def footprint_kb(self):
        total = 0.0
        for pid in self.pids():
            kb = parse_footprint_kb(subprocess.run(["footprint", "-p", str(pid)], capture_output=True, text=True).stdout)
            total += kb or 0
        return total

    def cpu_seconds(self):
        pids = self.pids()
        if not pids:
            return 0.0
        out = subprocess.run(["ps", "-o", "time=", "-p", ",".join(map(str, pids))], capture_output=True, text=True).stdout
        return sum(parse_cpu_seconds(line) for line in out.splitlines() if line.strip())

    def quit(self):
        for pid in self.pids():
            try:
                os.kill(pid, 15)
            except ProcessLookupError:
                pass
        deadline = time.monotonic() + 5
        while self.pids() and time.monotonic() < deadline:
            time.sleep(0.1)
        self.out.unlink(missing_ok=True)


def s1_start(name, runs):
    times = []
    for run in range(runs + 1):
        launch = Launch(name, {"TESTAPP_MARK": "1"})
        seconds = launch.wait_for("first-frame", 30)
        launch.quit()
        time.sleep(1)
        if run > 0:  # the first run warms the disk cache and is dropped
            times.append(seconds)
    ok = [t * 1000 for t in times if t is not None]
    return {"ms": ok, "failed": len(times) - len(ok), "p50_ms": percentile(ok, 50)}


def s2_scroll(name, page, seconds):
    env = {"TESTAPP_SCROLL": "1", "TESTAPP_SCROLL_SECONDS": str(seconds)}
    if page:
        env["TESTAPP_PAGE"] = page
    launch = Launch(name, env)
    peak = 0.0
    done = None
    while done is None and time.monotonic() - launch.start < seconds + 30:
        peak = max(peak, launch.footprint_kb())
        done = launch.wait_for("done", time.monotonic() - launch.start + 1)
    frames = [int(m.group(1)) for m in re.finditer(r"^frame (\d+)$", launch.out.read_text(errors="replace"), re.M)]
    launch.quit()
    gaps = [(b - a) / 1000 for a, b in zip(frames, frames[1:])]
    return {
        "done": done is not None,
        "frames": len(frames),
        "gap_p50_ms": percentile(gaps, 50),
        "gap_p99_ms": percentile(gaps, 99),
        "gaps_over_25ms": sum(g > 25 for g in gaps),
        "peak_footprint_mb": peak / 1024,
    }


def s4_idle(name, seconds):
    launch = Launch(name, {"TESTAPP_MARK": "1"})
    if launch.wait_for("first-frame", 30) is None:
        launch.quit()
        return {"failed": True}
    time.sleep(5)  # let start-up work settle
    cpu0, t0 = launch.cpu_seconds(), time.monotonic()
    memory = []
    while time.monotonic() - t0 < seconds:
        memory.append(launch.footprint_kb() / 1024)
        time.sleep(max(0, 1 - (time.monotonic() - t0) % 1))
    cpu = (launch.cpu_seconds() - cpu0) / (time.monotonic() - t0) * 100
    pids = len(launch.pids())
    launch.quit()
    return {"cpu_percent": cpu, "footprint_mb_p50": percentile(memory, 50), "footprint_mb_max": max(memory), "pids": pids}


def bundle_mb(name):
    return int(subprocess.run(["du", "-sk", str(APPS[name])], capture_output=True, text=True).stdout.split()[0]) / 1024


def clean_build_seconds(name):
    folder, command = BUILDS[name]
    start = time.monotonic()
    result = subprocess.run(command, shell=True, cwd=ROOT / folder, capture_output=True)
    return {"seconds": time.monotonic() - start, "ok": result.returncode == 0}


def self_test():
    assert percentile([1, 2, 3, 4], 50) == 2.5
    assert percentile([5], 99) == 5
    assert parse_footprint_kb("rukun [123]: 64-bit    Footprint: 45 MB (16384 bytes per page)") == 45 * 1024
    assert parse_footprint_kb("Footprint: 512 KB") == 512
    assert parse_cpu_seconds("0:01.50") == 1.5
    assert parse_cpu_seconds("1:02:03.00") == 3723
    print("self-test ok")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apps", default=",".join(APPS))
    parser.add_argument("--runs", type=int, default=10)
    parser.add_argument("--idle", type=int, default=60)
    parser.add_argument("--scroll-seconds", type=int, default=20)
    parser.add_argument("--build", action="store_true", help="time a clean build first (slow, no windows)")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()

    results = {"settings": vars(args), "apps": {}}
    for name in args.apps.split(","):
        app = results["apps"][name] = {}
        if args.build:
            app["build"] = clean_build_seconds(name)
        app["bundle_mb"] = bundle_mb(name)
        app["s1_start"] = s1_start(name, args.runs)
        app["s2_scroll_tasks"] = s2_scroll(name, "", args.scroll_seconds)
        app["s3_scroll_keluarga"] = s2_scroll(name, "keluarga", args.scroll_seconds)
        app["s4_idle"] = s4_idle(name, args.idle)
        print(name, json.dumps(app), flush=True)

    folder = ROOT / "harness/results"
    folder.mkdir(exist_ok=True)
    path = folder / time.strftime("%Y-%m-%dT%H%M%S.json")
    path.write_text(json.dumps(results, indent=2))
    print("wrote", path)


if __name__ == "__main__":
    sys.exit(main())
