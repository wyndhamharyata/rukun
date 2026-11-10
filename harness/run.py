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
    # Tauri builds the shared React app itself; Electron's package only copies its dist.
    "electron": ("apps/electron", "rm -rf out ../web/dist && npm --prefix ../web run build && npx electron-forge package"),
    "tauri": ("apps/tauri", "cargo clean --manifest-path src-tauri/Cargo.toml && npx tauri build --bundles app"),
    "gpui": ("apps/gpui", "cargo clean && ./bundle.sh"),
}
UNITS = {"B": 1 / 1024, "KB": 1, "MB": 1024, "GB": 1024 * 1024}


def percentile(values, p):
    values = sorted(values)
    if not values:
        return None
    k = (len(values) - 1) * p / 100
    lo, hi = int(k), min(int(k) + 1, len(values) - 1)
    return values[lo] + (values[hi] - values[lo]) * (k - lo)


def parse_footprints_kb(text):
    """Each process footprint lists, by pid: `name [pid]: 64-bit    Footprint: 45 MB`."""
    found = re.finditer(r"\[(\d+)\]: \S+\s+Footprint:\s*([\d.]+)\s*(B|KB|MB|GB)", text)
    return {int(m.group(1)): float(m.group(2)) * UNITS[m.group(3)] for m in found}


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
        return tree

    def footprints_kb(self):
        """By pid: the app's process tree, plus the XPC services macOS counts as its children, such as
        the WebKit processes of Tauri's web view, which launchd owns."""
        args = ["footprint", "--targetChildren"]
        for pid in self.pids():
            args += ["-p", str(pid)]
        if len(args) == 2:
            return {}
        return parse_footprints_kb(subprocess.run(args, capture_output=True, text=True).stdout)

    def footprint_kb(self):
        return sum(self.footprints_kb().values())

    def cpu_by_pid(self, pids):
        if not pids:
            return {}
        out = subprocess.run(["ps", "-o", "pid=,time=", "-p", ",".join(map(str, pids))], capture_output=True, text=True).stdout
        return {int(pid): parse_cpu_seconds(time) for pid, time in (line.split() for line in out.splitlines() if line.strip())}


    def quit(self):
        for pid in self.pids() | set(self.footprints_kb()):
            try:
                os.kill(pid, 15)
            except ProcessLookupError:
                pass
        deadline = time.monotonic() + 5
        while self.pids() and time.monotonic() < deadline:
            time.sleep(0.1)
        self.out.unlink(missing_ok=True)


class Cpu:
    """CPU percent over samples. Each process counts from the sample it first shows in, so a helper
    that starts later counts, and one that quits keeps what it used."""

    def __init__(self):
        self.first, self.last, self.times = {}, {}, []

    def sample(self, launch, pids):
        for pid, seconds in launch.cpu_by_pid(pids).items():
            self.first.setdefault(pid, seconds)
            self.last[pid] = seconds
        self.times.append(time.monotonic())

    def percent(self):
        if len(self.times) < 2:
            return None
        used = sum(self.last[pid] - self.first[pid] for pid in self.last)
        return used / (self.times[-1] - self.times[0]) * 100


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
    median = percentile(ok, 50)
    return {"ms": ok, "failed": len(times) - len(ok), "p50_ms": median, "spread": (max(ok) - min(ok)) / median if ok else None}


def s2_scroll(name, page, seconds, sample_memory=True):
    env = {"TESTAPP_MARK": "1", "TESTAPP_SCROLL": "1", "TESTAPP_SCROLL_SECONDS": str(seconds)}
    if page:
        env["TESTAPP_PAGE"] = page
    launch = Launch(name, env)
    memory, cpu = [], Cpu()
    first_frame = launch.wait_for("first-frame", 30)
    if first_frame is not None:  # the scroll starts a second after the first frame
        time.sleep(max(0, launch.start + first_frame + 1 - time.monotonic()))
    while first_frame is not None and time.monotonic() - launch.start < seconds + 30:
        if "done" in launch.out.read_text(errors="replace").splitlines():
            break
        if sample_memory:
            footprints = launch.footprints_kb()
            if footprints:
                memory.append(sum(footprints.values()) / 1024)
                cpu.sample(launch, set(footprints))
        time.sleep(1)
    text = launch.out.read_text(errors="replace")
    frames = [int(m.group(1)) for m in re.finditer(r"^frame (\d+)$", text, re.M)]
    launch.quit()
    time.sleep(1)
    gaps = [(b - a) / 1000 for a, b in zip(frames, frames[1:])]
    return {
        "done": "done" in text.splitlines(),
        "frames": len(frames),
        "gap_p50_ms": percentile(gaps, 50),
        "gap_p99_ms": percentile(gaps, 99),
        "gaps_over_25ms": sum(g > 25 for g in gaps),
        "cpu_percent": cpu.percent(),
        "footprint_mb_mean": sum(memory) / len(memory) if memory else None,
        "footprint_mb_max": max(memory, default=None),
    }


def s4_idle(name, seconds):
    launch = Launch(name, {"TESTAPP_MARK": "1"})
    if launch.wait_for("first-frame", 30) is None:
        launch.quit()
        return {"failed": True}
    time.sleep(5)  # let start-up work settle
    memory, cpu, pids, t0 = [], Cpu(), set(), time.monotonic()
    while True:
        footprints = launch.footprints_kb()
        pids |= set(footprints)
        cpu.sample(launch, set(footprints))
        if time.monotonic() - t0 >= seconds:
            break
        memory.append(sum(footprints.values()) / 1024)
        time.sleep(max(0, 1 - (time.monotonic() - t0) % 1))
    launch.quit()
    time.sleep(1)
    return {"cpu_percent": cpu.percent(), "footprint_mb_mean": sum(memory) / len(memory), "footprint_mb_max": max(memory), "pids": len(pids)}


def summary(runs):
    """The median of each number over the runs, and how far the runs spread: (max - min) / median."""
    out = {}
    for key in runs[0]:
        values = [r[key] for r in runs if isinstance(r.get(key), (int, float)) and not isinstance(r.get(key), bool)]
        if values:
            median = percentile(values, 50)
            out[key] = {"median": median, "spread": (max(values) - min(values)) / median if median else 0}
    return out


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
    text = "rukun [123]: 64-bit    Footprint: 45 MB (16384 bytes per page)\nShared with GPU [9]:\nGPU [9]: 64-bit    Footprint: 512 KB (16384 bytes per page)"
    assert parse_footprints_kb(text) == {123: 45 * 1024, 9: 512}
    assert summary([{"a": 1, "b": True}, {"a": 3, "b": True}]) == {"a": {"median": 2, "spread": 1}}
    class Fake:  # pid 2 starts late, pid 1 quits before the last sample
        readings = [{1: 1.0}, {1: 2.0, 2: 5.0}, {2: 6.0}]

        def cpu_by_pid(self, pids):
            return self.readings.pop(0)

    cpu, fake = Cpu(), Fake()
    for _ in range(3):
        cpu.sample(fake, set())
    cpu.times = [0, 1, 2]
    assert cpu.percent() == 100  # 1 s from pid 1 and 1 s from pid 2 over 2 s
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
        for key, run in [
            ("s2_scroll_tasks", lambda: s2_scroll(name, "", args.scroll_seconds)),
            ("s3_scroll_keluarga", lambda: s2_scroll(name, "keluarga", args.scroll_seconds)),
            ("s4_idle", lambda: s4_idle(name, args.idle)),
        ]:
            runs = [run() for _ in range(args.runs)]
            app[key] = {"runs": runs, "summary": summary(runs)}
        print(name, json.dumps({key: value.get("summary", value) if isinstance(value, dict) else value for key, value in app.items()}), flush=True)

    folder = ROOT / "harness/results"
    folder.mkdir(exist_ok=True)
    path = folder / time.strftime("%Y-%m-%dT%H%M%S.json")
    path.write_text(json.dumps(results, indent=2))
    print("wrote", path)


if __name__ == "__main__":
    sys.exit(main())
