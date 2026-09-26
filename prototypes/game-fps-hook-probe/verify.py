#!/usr/bin/env python3
"""Check that each demo actually loaded the observer and produced frame events."""

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "tmp/game-fps-hook-probe"


def check(backend: str) -> bool:
    path = OUTPUT / f"{backend}-observer.jsonl"
    if not path.exists():
        print(f"{backend}: missing log ({path})")
        return False
    rows = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    loaded = any(row.get("probe") == "loaded" for row in rows)
    frames = [row for row in rows if row.get("probe") == "fps"]
    if backend == "opengl":
        values = [row["cgl_swaps"] for row in frames]
        independent = all(row["cgl_swaps"] == row["cocoa_swaps"] for row in frames)
    else:
        values = [row["metal_presented"] for row in frames]
        independent = all(row["cgl_swaps"] == 0 for row in frames)
    passed = loaded and independent and any(value >= 100 for value in values)
    print(f"{backend}: loaded={loaded}, max_per_second={max(values, default=0)}, "
          f"consistent={independent}, passed={passed}")
    return passed


if __name__ == "__main__":
    requested = sys.argv[1:] or ["metal", "opengl", "vulkan"]
    sys.exit(0 if all(check(backend) for backend in requested) else 1)
