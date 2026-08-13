#!/usr/bin/env python3
"""Assign Torchform display roles from live Sway output geometry.

The largest active output is the upper display and the smallest active output is
lower.  A portrait upper panel is rotated into landscape by default, then
scaled to Torchform's 1920x1080 logical design space.  Role names and all
geometry remain overrideable through environment variables because the IO-board
connectors are still provisional.
"""

from __future__ import annotations

import argparse
import glob
import json
import math
import os
import subprocess
import sys
from typing import Any


DEFAULT_RUNTIME = "/tmp/xdg-hdmi"


def _runtime_dir() -> str:
    return os.environ.get(
        "TORCHFORM_XDG_RUNTIME_DIR",
        os.environ.get("XDG_RUNTIME_DIR", DEFAULT_RUNTIME),
    )


def _sway(*args: str) -> list[dict[str, Any]]:
    env = os.environ.copy()
    if not env.get("SWAYSOCK"):
        sockets = sorted(glob.glob(os.path.join(_runtime_dir(), "sway-ipc.*.sock")))
        if sockets:
            env["SWAYSOCK"] = sockets[0]
    if not env.get("SWAYSOCK"):
        raise RuntimeError(f"no Sway IPC socket in {_runtime_dir()}")

    proc = subprocess.run(
        ["swaymsg", *args],
        env=env,
        check=False,
        text=True,
        capture_output=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or "swaymsg failed")
    try:
        payload = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"invalid swaymsg response: {proc.stdout!r}") from exc
    if not isinstance(payload, list):
        raise RuntimeError(f"unexpected swaymsg response: {payload!r}")
    return payload


def _outputs() -> list[dict[str, Any]]:
    payload = _sway("-t", "get_outputs")
    return [
        output
        for output in payload
        if output.get("active", False) and not output.get("non_desktop", False)
    ]


def _mode_size(output: dict[str, Any]) -> tuple[int, int]:
    mode = output.get("current_mode") or {}
    width = int(mode.get("width", 0) or 0)
    height = int(mode.get("height", 0) or 0)
    transform = str(output.get("transform", "normal"))
    if transform in {"90", "270", "flipped-90", "flipped-270"}:
        width, height = height, width
    return width, height


def _area(output: dict[str, Any]) -> int:
    width, height = _mode_size(output)
    return width * height


def _pick(outputs: list[dict[str, Any]], role: str, largest: bool) -> dict[str, Any]:
    requested = os.environ.get(f"TORCHFORM_{role.upper()}_OUTPUT", "").strip()
    if requested:
        for output in outputs:
            if output.get("name") == requested:
                return output
        raise RuntimeError(
            f"TORCHFORM_{role.upper()}_OUTPUT={requested!r} is not active; "
            f"active outputs: {[o.get('name') for o in outputs]}"
        )
    return sorted(outputs, key=_area, reverse=largest)[0]


def _scale_for(width: int, height: int) -> float:
    requested = os.environ.get("TORCHFORM_UPPER_SCALE", "").strip()
    if requested:
        return float(requested)
    # Match the existing QML design space without making assumptions about the
    # final panel resolution.  Keep at least 1 logical pixel per physical pixel
    # when the panel is smaller than the design target.
    return max(0.5, min(4.0, min(width / 1920.0, height / 1080.0)))


def _round_scale(value: float) -> str:
    if not math.isfinite(value) or value <= 0:
        raise RuntimeError(f"invalid output scale {value!r}")
    return f"{value:.4f}".rstrip("0").rstrip(".")


def status() -> dict[str, Any]:
    outputs = _outputs()
    return {
        "outputs": [
            {
                "name": output.get("name"),
                "make": output.get("make"),
                "model": output.get("model"),
                "mode": output.get("current_mode"),
                "rect": output.get("rect"),
                "scale": output.get("scale"),
                "transform": output.get("transform"),
                "area": _area(output),
            }
            for output in outputs
        ]
    }


def configure() -> dict[str, Any]:
    outputs = _outputs()
    if len(outputs) < 2:
        raise RuntimeError(f"Torchform needs two active outputs, found {len(outputs)}")

    upper = _pick(outputs, "upper", largest=True)
    lower = _pick([o for o in outputs if o.get("name") != upper.get("name")], "lower", largest=False)

    requested_transform = os.environ.get("TORCHFORM_UPPER_TRANSFORM", "").strip()
    if requested_transform:
        transform = requested_transform
    else:
        # The portrait upper panel is currently mounted upside down.  Rotate
        # the normal landscape transform (90°) by another 180°.
        width, height = _mode_size(upper)
        transform = "270" if height > width * 1.15 else "180"
    _sway("output", str(upper["name"]), "transform", transform)

    outputs = _outputs()
    upper = next(output for output in outputs if output.get("name") == upper.get("name"))
    lower = next(output for output in outputs if output.get("name") == lower.get("name"))
    upper_width, upper_height = _mode_size(upper)
    upper_scale = _scale_for(upper_width, upper_height)
    lower_scale = os.environ.get("TORCHFORM_LOWER_SCALE", "1").strip() or "1"

    _sway("output", str(upper["name"]), "scale", _round_scale(upper_scale))
    _sway("output", str(lower["name"]), "scale", _round_scale(float(lower_scale)))

    # Sway positions are in logical coordinates after scaling.  Set the upper
    # first, then place the lower immediately beneath its final logical rect.
    outputs = _outputs()
    upper = next(output for output in outputs if output.get("name") == upper.get("name"))
    upper_height = int((upper.get("rect") or {}).get("height", 0) or 0)
    if upper_height <= 0:
        _, upper_height = _mode_size(upper)
    _sway("output", str(upper["name"]), "pos", "0", "0")
    _sway("output", str(lower["name"]), "pos", "0", str(upper_height))

    result = status()
    result["roles"] = {
        "upper": upper.get("name"),
        "lower": lower.get("name"),
        "upper_transform": transform,
        "upper_scale": upper_scale,
        "lower_scale": float(lower_scale),
    }
    return result


def role_name(role: str) -> str:
    outputs = _outputs()
    if len(outputs) < 2:
        raise RuntimeError(f"Torchform needs two active outputs, found {len(outputs)}")
    upper = _pick(outputs, "upper", largest=True)
    if role == "upper":
        return str(upper["name"])
    remaining = [output for output in outputs if output.get("name") != upper.get("name")]
    return str(_pick(remaining, "lower", largest=False)["name"])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--status", action="store_true", help="print current active outputs")
    parser.add_argument(
        "--role",
        choices=("upper", "lower"),
        help="print the output name for a display role and exit",
    )
    args = parser.parse_args()

    try:
        if args.role:
            print(role_name(args.role))
            return 0
        result = status() if args.status else configure()
    except (OSError, RuntimeError, StopIteration, ValueError) as exc:
        print(f"configure-outputs: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
