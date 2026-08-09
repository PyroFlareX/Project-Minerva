#!/usr/bin/env python3
"""Capture Minerva's geometry-selected upper and lower displays.

The script asks Sway which active output is largest/smallest, then captures
both named outputs with the device's installed ``grim``.  It intentionally
uses the same role-selection source as ``start-hdmi.sh`` and the smoke harness,
so an IO-board connector swap does not silently label screenshots backwards.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import shlex
import subprocess
import sys


SSH_BASE = ["ssh", "-T", "-o", "ForwardX11=no"]
SCP_BASE = ["scp", "-T", "-o", "ForwardX11=no"]
REMOTE_DIR = "$HOME/projects/torchform-guishell"
RUNTIME = "/tmp/xdg-hdmi"
DISPLAY = "wayland-1"


class CaptureError(RuntimeError):
    pass


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(command, text=True, capture_output=True)
    if proc.returncode:
        detail = proc.stderr.strip() or proc.stdout.strip() or "command failed"
        raise CaptureError(f"{' '.join(command)}: {detail}")
    return proc


def remote(host: str, command: str) -> str:
    return run(SSH_BASE + [host, command]).stdout.strip()


def output_roles(host: str) -> tuple[dict, str, str]:
    raw = remote(host, f"python3 {REMOTE_DIR}/configure-outputs.py --status")
    try:
        status = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise CaptureError(f"invalid output status: {raw!r}") from exc
    outputs = status.get("outputs", [])
    if len(outputs) < 2:
        raise CaptureError(f"expected two active outputs, got {outputs!r}")
    ordered = sorted(outputs, key=lambda output: int(output.get("area", 0)), reverse=True)
    return status, str(ordered[0]["name"]), str(ordered[-1]["name"])


def capture(host: str, output: str, remote_path: str, local_path: pathlib.Path) -> None:
    command = (
        f"PATH=$HOME/userpkgs/usr/bin:$PATH "
        f"XDG_RUNTIME_DIR={RUNTIME} WAYLAND_DISPLAY={DISPLAY} "
        f"$HOME/userpkgs/usr/bin/grim -o {shlex.quote(output)} {shlex.quote(remote_path)}"
    )
    remote(host, command)
    run(SCP_BASE + [f"{host}:{remote_path}", str(local_path)])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="Minerva")
    parser.add_argument("--output-dir", help="local artifact directory")
    parser.add_argument("--label", default="current", help="filename label")
    args = parser.parse_args()

    timestamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    destination = pathlib.Path(args.output_dir or f"/tmp/torchform-screens-{timestamp}")
    destination.mkdir(parents=True, exist_ok=True)
    status, upper, lower = output_roles(args.host)
    for role, output in (("upper", upper), ("lower", lower)):
        remote_path = f"/tmp/torchform-capture-{args.label}-{role}.png"
        capture(args.host, output, remote_path, destination / f"{args.label}-{role}.png")

    (destination / "outputs.json").write_text(json.dumps(status, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"upper": upper, "lower": lower, "directory": str(destination)}, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (CaptureError, OSError, ValueError, KeyError) as exc:
        print(f"capture-device-screens: {exc}", file=sys.stderr)
        raise SystemExit(2)
