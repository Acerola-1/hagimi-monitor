#!/usr/bin/env python3
"""有限时长采集独立应用；只清理此脚本创建的子进程，录像与资源对照分轮运行。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--probe", type=Path, required=True)
    parser.add_argument("--native", action="store_true")
    parser.add_argument("--default-native", action="store_true",
                        help="record a production native build without a motion-selection environment flag")
    parser.add_argument("--mode", default="full-matrix")
    parser.add_argument("--load", choices=["cpu", "both"])
    parser.add_argument("--stress", type=Path)
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--duration", type=float, default=56)
    parser.add_argument("--capture", type=Path)
    parser.add_argument("--background-helper", type=Path)
    parser.add_argument("--background", choices=["white", "dark", "complex"])
    parser.add_argument("--trace", choices=["Animation Hitches", "Time Profiler", "SwiftUI"])
    parser.add_argument("--host", choices=["menu", "pinned"], default="menu")
    args = parser.parse_args()
    if not 1 <= args.duration <= 120 or not 1 <= args.workers <= 32:
        parser.error("duration must be 1..120 seconds, workers 1..32")
    if args.load and not args.stress:
        parser.error("stress helper required for load runs")
    import plistlib
    info = plistlib.loads((args.app / "Contents/Info.plist").read_bytes())
    if not info["CFBundleIdentifier"].startswith("local.hagimi.closeout."):
        parser.error("only independently packaged local.hagimi.closeout.* artifacts are accepted")
    binary = args.app / "Contents/MacOS" / info["CFBundleExecutable"]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    prefix = str(args.output.resolve())
    handles, children = [], []
    receipt = {"app": str(args.app.resolve()), "bundle_id": info["CFBundleIdentifier"],
               "executable_sha256": digest(binary), "mode": args.mode,
               "native": args.native or args.default_native, "host": args.host, "load": args.load,
               "workers": args.workers if args.load else 0, "capture": bool(args.capture),
               "trace": args.trace,
               "background": args.background,
               "started_epoch": time.time(), "activity": [], "complete": False}
    configuration = subprocess.run(["defaults", "export", info["CFBundleIdentifier"], "-"],
                                   check=True, capture_output=True, timeout=10).stdout
    Path(prefix + ".configuration.plist").write_bytes(configuration)
    receipt["configuration_sha256"] = hashlib.sha256(configuration).hexdigest()
    environment = {k: v for k, v in os.environ.items() if k in
                   ("HOME", "PATH", "TMPDIR", "LANG", "USER", "LOGNAME", "__CF_USER_TEXT_ENCODING")}
    environment.update(HAGIMI_PANEL_NATIVE_LAYER="1" if args.native else "0",
                       HAGIMI_PANEL_TEST_DISPLAY="1", HAGIMI_PANEL_TEST_HOST=args.host,
                       HAGIMI_PANEL_BENCH=args.mode, HAGIMI_PANEL_BENCH_CAP="700",
                       HAGIMI_PANEL_PERF_WINDOW="0.65", HAGIMI_PANEL_BENCH_HIDE="1")
    # 原生候选由显式预览宿主打开；兼容路径使用同一 Autotest 首次打开入口。
    environment["HAGIMI_PANEL_AUTOTEST"] = "0:0"
    if args.default_native:
        environment.pop("HAGIMI_PANEL_NATIVE_LAYER", None)
    receipt["environment"] = environment | {"HOME": "<user-home>", "USER": "<user>", "LOGNAME": "<user>"}

    def launch(command, suffix, **kwargs):
        handle = open(prefix + suffix, "w")
        handles.append(handle)
        child = subprocess.Popen(command, stdout=handle, stderr=subprocess.STDOUT, **kwargs)
        children.append(child)
        return child

    try:
        if args.background:
            if not args.background_helper:
                parser.error("background helper is required")
            background = launch([str(args.background_helper.resolve()), args.background], ".background.log")
            receipt["background_pid"] = background.pid
            receipt["background_sha256"] = digest(args.background_helper)
        stress = None
        if args.load:
            stress = launch([str(args.stress.resolve()), str(args.duration), args.load, str(args.workers)], ".stress.log")
            receipt["stress_pid"] = stress.pid
            receipt["stress_sha256"] = digest(args.stress)
        app = launch([str(binary.resolve())], ".app.log", env=environment)
        receipt["pid"] = app.pid
        window_server = subprocess.run(["pgrep", "-x", "WindowServer"], text=True,
                                       capture_output=True, timeout=5).stdout.strip()
        targets = [str(app.pid)] + ([str(stress.pid)] if stress else [])
        if window_server:
            targets.append(window_server.splitlines()[0])
        deadline = time.monotonic() + args.duration
        capture_started = False
        trace_started = False
        while time.monotonic() < deadline:
            log = Path(prefix + ".app.log").read_text(errors="replace")
            if app.poll() is not None:
                raise RuntimeError("application exited before capture completed")
            if "aborted=window-occluded" in log:
                receipt["invalid_reason"] = "window-occluded"
                break
            if args.capture and not capture_started and "operation=0 " in log:
                capture = launch([str(args.capture.resolve()), str(app.pid), prefix + ".mp4", "33"], ".capture.log")
                receipt["capture_pid"] = capture.pid
                receipt["capture_sha256"] = digest(args.capture)
                capture_started = True
            if args.trace and not trace_started and "operation=0 " in log:
                trace = launch(["xcrun", "xctrace", "record", "--template", args.trace,
                    "--attach", str(app.pid), "--time-limit", "8s", "--output", prefix + ".trace",
                    "--no-prompt"], ".trace.log")
                receipt["trace_pid"] = trace.pid
                trace_started = True
            try:
                sampled = subprocess.run([str(args.probe.resolve())] + targets,
                                         capture_output=True, text=True, timeout=8)
            except subprocess.TimeoutExpired:
                receipt.setdefault("probe_errors", []).append("resource probe exceeded 8 seconds")
                continue
            if sampled.returncode == 0:
                sample = json.loads(sampled.stdout)
                hidden = "[panel-bench] hidden" in log or "[panel-lifecycle] complete" in log
                active = "operation=0 " in log or "[panel-lifecycle] stage=" in log
                sample["phase"] = "hidden" if hidden else "operations" if active else "warmup"
                receipt["activity"].append(sample)
            else:
                receipt.setdefault("probe_errors", []).append(sampled.stderr)
            time.sleep(1)
        final_log = Path(prefix + ".app.log").read_text(errors="replace")
        receipt["complete"] = ("[panel-lifecycle] complete failures=0" if args.mode == "full-lifecycle"
                               else "[panel-bench] complete") in final_log
        receipt["app_exit_before_cleanup"] = app.poll()
        if stress:
            try:
                stress.wait(timeout=5)
                receipt["stress_exit"] = stress.returncode
                if stress.returncode != 0:
                    receipt["invalid_reason"] = "stress-helper-failed"
            except subprocess.TimeoutExpired:
                receipt["invalid_reason"] = "stress-helper-did-not-finish"
        if args.capture and capture_started:
            capture.wait(timeout=15)
            receipt["capture_exit"] = capture.returncode
        if args.trace and trace_started:
            receipt["trace_exit"] = trace.poll()
    finally:
        for child in reversed(children):
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
        for handle in handles:
            handle.close()
        receipt["ended_epoch"] = time.time()
        Path(prefix + ".json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2))
    print(json.dumps({k: v for k, v in receipt.items() if k not in ("activity", "environment")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
