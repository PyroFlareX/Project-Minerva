#!/usr/bin/env python3
"""Run script-driven Torchform smoke scenarios on a live Minerva console.

The harness creates the same named Linux virtual gamepad that the production
QuickShell Gamepad plugin reads.  Button and D-pad steps therefore exercise
the controller path without a physical controller or keyboard/mouse events.
Terminal text steps are the only keyboard injection fallback because arbitrary
shell text is not representable by a gamepad button.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import shlex
import subprocess
import sys
import time
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCENARIOS_PATH = pathlib.Path(__file__).with_name("device-scenarios.json")
SSH_BASE = ["ssh", "-T", "-o", "ForwardX11=no"]
SCP_BASE = ["scp", "-T", "-o", "ForwardX11=no"]
WAYLAND_RUNTIME = "/tmp/xdg-hdmi"
WAYLAND_DISPLAY = "wayland-1"
REMOTE_DIR = "$HOME/projects/torchform-guishell"
REMOTE_STATE = "$HOME/.cache/torchform/state.json"
REMOTE_VGAMEPAD = f"{REMOTE_DIR}/virtual-gamepad.py"
REMOTE_VGAMEPAD_SOCKET = f"{WAYLAND_RUNTIME}/torchform/virtual-gamepad.sock"

VIRTUAL_BUTTONS = {
    "ESC": "east",
    "SPACE": "start",
    "TAB": "north",
    "ENTER": "select",
    "SELECT": "select",
    "UP": "dpad_up",
    "DOWN": "dpad_down",
    "LEFT": "dpad_left",
    "RIGHT": "dpad_right",
    "A": "south",
    "B": "east",
    "X": "west",
    "Z": "r1",
    "C": "l1",
}


class DeviceError(RuntimeError):
    pass


def run_command(command: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(command, text=True, capture_output=True)
    if check and proc.returncode != 0:
        detail = proc.stderr.strip() or proc.stdout.strip() or "command failed"
        raise DeviceError(f"{' '.join(command)}: {detail}")
    return proc


def remote(host: str, command: str, *, check: bool = True) -> str:
    proc = run_command(SSH_BASE + [host, command], check=check)
    return proc.stdout.strip()


def remote_ok(host: str, command: str) -> bool:
    return run_command(SSH_BASE + [host, command], check=False).returncode == 0


def remote_json(host: str, command: str) -> dict[str, Any]:
    text = remote(host, command)
    try:
        payload = json.loads(text)
    except json.JSONDecodeError as exc:
        raise DeviceError(f"invalid JSON from {command!r}: {text!r}") from exc
    if not isinstance(payload, dict):
        raise DeviceError(f"expected object from {command!r}, got {payload!r}")
    return payload


def output_status(host: str) -> dict[str, Any]:
    command = f"python3 {REMOTE_DIR}/configure-outputs.py --status"
    return remote_json(host, command)


def role_outputs(status: dict[str, Any]) -> tuple[str, str]:
    outputs = status.get("outputs", [])
    if len(outputs) < 2:
        raise DeviceError(f"expected two outputs, got {outputs!r}")
    ordered = sorted(outputs, key=lambda output: int(output.get("area", 0)), reverse=True)
    return str(ordered[0]["name"]), str(ordered[-1]["name"])


def restart_device(host: str) -> None:
    command = (
        "pkill -9 -x quickshell 2>/dev/null || true; "
        "pkill -9 -x sway 2>/dev/null || true; "
        "if [ -f /tmp/torchform-virtual-gamepad.pid ]; then "
        "kill \"$(cat /tmp/torchform-virtual-gamepad.pid)\" 2>/dev/null || true; "
        "fi; "
        f"rm -f {REMOTE_STATE}; "
        "rm -rf $HOME/.cache/quickshell $HOME/.cache/qmlcache; "
        "sleep 1; "
        f"TORCHFORM_VIRTUAL_GAMEPAD=1 nohup setsid sh {REMOTE_DIR}/start-hdmi.sh "
        ">/tmp/start-hdmi.log 2>&1 </dev/null &"
    )
    remote(host, command)
    deadline = time.monotonic() + 30
    ipc_ready = (
        "for socket in /tmp/xdg-hdmi/sway-ipc.*.sock; do "
        'test -S "$socket" && exit 0; '
        "done; exit 1"
    )
    pad_ready = (
        f"test -f {WAYLAND_RUNTIME}/torchform/virtual-gamepad.ready "
        f"&& test -S {REMOTE_VGAMEPAD_SOCKET}"
    )
    while time.monotonic() < deadline:
        if (
            remote_ok(host, ipc_ready)
            and remote_ok(host, "pgrep -x quickshell >/dev/null")
            and remote_ok(host, pad_ready)
        ):
            # Give the QML Gamepad plugin one retry interval to open the
            # uinput event node before the first tap.
            time.sleep(2.2)
            return
        time.sleep(1)
    raise DeviceError("Timed out waiting for the Minerva virtual-gamepad session")


def send_key(host: str, key: str) -> None:
    button = VIRTUAL_BUTTONS.get(key.upper())
    if button is None:
        raise DeviceError(f"no virtual-gamepad mapping for key action {key!r}")
    command = (
        f"python3 {REMOTE_VGAMEPAD} --socket {REMOTE_VGAMEPAD_SOCKET} "
        f"tap {shlex.quote(button)}"
    )
    remote(host, command)



def send_text(host: str, text: str) -> None:
    command = (
        f"XDG_RUNTIME_DIR={WAYLAND_RUNTIME} WAYLAND_DISPLAY={WAYLAND_DISPLAY} "
        f"$HOME/userpkgs/usr/bin/wtype -- {shlex.quote(text)}"
    )
    remote(host, command)


def read_state(host: str) -> dict[str, Any]:
    text = remote(host, f"cat {REMOTE_STATE}", check=False)
    if not text:
        return {}
    try:
        state = json.loads(text)
    except json.JSONDecodeError:
        return {"_invalid": text}
    return state if isinstance(state, dict) else {"_invalid": state}


def capture_screens(
    host: str,
    upper: str,
    lower: str,
    destination: pathlib.Path,
    label: str,
) -> list[pathlib.Path]:
    destination.mkdir(parents=True, exist_ok=True)
    captured: list[pathlib.Path] = []
    for role, output in (("upper", upper), ("lower", lower)):
        remote_path = f"/tmp/torchform-smoke-{label}-{role}.png"
        command = (
            f"PATH=$HOME/userpkgs/usr/bin:$PATH "
            f"XDG_RUNTIME_DIR={WAYLAND_RUNTIME} WAYLAND_DISPLAY={WAYLAND_DISPLAY} "
            f"$HOME/userpkgs/usr/bin/grim -o {shlex.quote(output)} {remote_path}"
        )
        try:
            remote(host, command)
            local_path = destination / f"{label}-{role}.png"
            run_command(SCP_BASE + [f"{host}:{remote_path}", str(local_path)])
            captured.append(local_path)
        except DeviceError:
            # One failed capture must not hide state/assertion failures for the
            # step; the caller records the missing artifact in the report.
            continue
    return captured


def assert_state(state: dict[str, Any], expected: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    if not state:
        return ["state.json missing or empty"]
    if "_invalid" in state:
        return [f"invalid state.json: {state['_invalid']!r}"]
    for key, value in expected.items():
        if key.endswith("Contains"):
            field = key[: -len("Contains")]
            actual = str(state.get(field, ""))
            if str(value) not in actual:
                failures.append(f"{field}={actual!r} does not contain {value!r}")
            continue
        actual = state.get(key)
        if actual != value:
            failures.append(f"{key}={actual!r}, expected {value!r}")
    return failures


def device_has_touch(host: str) -> bool:
    devices = remote(host, "cat /proc/bus/input/devices", check=False).lower()
    return "touchscreen" in devices or "touch screen" in devices or "touchpad" in devices


def run_action(host: str, action: str) -> None:
    if action.startswith("key:"):
        send_key(host, action.split(":", 1)[1])
    elif action.startswith("text:"):
        send_text(host, action.split(":", 1)[1])
    elif action.startswith("sleep:"):
        time.sleep(float(action.split(":", 1)[1]))
    elif action.startswith("touch:"):
        raise DeviceError(f"touch action requires an injected pointer: {action}")
    else:
        raise DeviceError(f"unknown action {action!r}")


def device_resources(host: str) -> str:
    return remote(host, "free -m; printf '\n'; df -h /; printf '\n'; uptime", check=False)


def run(args: argparse.Namespace) -> int:
    scenarios_doc = json.loads(SCENARIOS_PATH.read_text())
    scenarios = scenarios_doc["scenarios"]
    selected = set(args.scenario or [scenario["id"] for scenario in scenarios])
    scenarios = [scenario for scenario in scenarios if scenario["id"] in selected]
    missing = selected - {scenario["id"] for scenario in scenarios}
    if missing:
        raise DeviceError(f"unknown scenario(s): {', '.join(sorted(missing))}")

    timestamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    artifact_dir = pathlib.Path(args.artifact_dir or f"/tmp/torchform-device-{timestamp}")
    artifact_dir.mkdir(parents=True, exist_ok=True)
    report_path = pathlib.Path(args.report or artifact_dir / "report.md")
    report_path.parent.mkdir(parents=True, exist_ok=True)

    report: list[str] = [
        f"# Torchform device smoke test — {timestamp}",
        "",
        f"- Host: `{args.host}`",
        "- Input path: `virtual gamepad` button/D-pad taps through `/dev/uinput`; `text:` actions use `wtype` only for terminal command payloads.",
        f"- Artifact directory: `{artifact_dir}`",
        "",
        "## Outputs",
        "",
    ]
    if args.restart:
        restart_device(args.host)
    status = output_status(args.host)
    report.append("```json")
    report.append(json.dumps(status, indent=2, sort_keys=True))
    report.append("```")
    report.append("")

    upper, lower = role_outputs(status)
    touch_available = device_has_touch(args.host)
    report.append(f"- Touch-capable input detected: `{touch_available}`")
    report.append("")

    failures = 0
    skipped = 0
    for scenario in scenarios:
        scenario_id = scenario["id"]
        if scenario.get("touch_required") and not touch_available:
            skipped += 1
            report.extend([f"## {scenario_id}: SKIP", "", "No touchscreen/touchpad input is currently enumerated in `/proc/bus/input/devices`.", ""])
            print(f"SKIP {scenario_id}: no touch input enumerated")
            continue

        report.extend([f"## {scenario_id}", "", scenario.get("description", ""), "", "| Step | State | Assertions | Screenshots |", "|---|---|---|---|"])
        for step_index, step in enumerate(scenario["steps"], start=1):
            step_id = step["id"]
            for action in step.get("actions", []):
                run_action(args.host, action)
                if not action.startswith("sleep:"):
                    time.sleep(args.delay)
            time.sleep(args.settle)
            state = read_state(args.host)
            assertion_failures = assert_state(state, step.get("expect", {}))
            shots: list[pathlib.Path] = []
            if not args.no_screenshots:
                shots = capture_screens(args.host, upper, lower, artifact_dir, f"{scenario_id}-{step_index:02d}-{step_id}")
            status_word = "PASS" if not assertion_failures else "FAIL"
            if assertion_failures:
                failures += 1
            state_text = json.dumps(state, sort_keys=True) if state else "(missing)"
            assertion_text = "; ".join(assertion_failures) if assertion_failures else "ok"
            shot_text = ", ".join(path.name for path in shots) or "none"
            report.append(f"| `{step_id}` | **{status_word}** `{state_text}` | {assertion_text} | `{shot_text}` |")
            print(f"{status_word} {scenario_id}/{step_id}")
        report.append("")

    report.extend(["## Resource snapshot", "", "```text", device_resources(args.host), "```", ""])
    report.extend(["## Totals", "", f"- Assertion failures: `{failures}`", f"- Skipped scenarios: `{skipped}`", ""])
    report_path.write_text("\n".join(report))
    print(f"Report: {report_path}")
    print(f"Artifacts: {artifact_dir}")
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="Minerva", help="SSH host alias")
    parser.add_argument("--scenario", action="append", help="scenario id (repeatable; default: all)")
    parser.add_argument("--restart", action="store_true", help="restart the device shell before testing")
    parser.add_argument("--no-screenshots", action="store_true", help="skip grim/scp artifacts")
    parser.add_argument("--artifact-dir", help="local screenshot/report directory")
    parser.add_argument("--report", help="explicit local Markdown report path")
    parser.add_argument("--delay", type=float, default=0.12, help="delay between injected key events")
    parser.add_argument("--settle", type=float, default=0.35, help="settle time before each assertion")
    args = parser.parse_args()
    try:
        return run(args)
    except (DeviceError, OSError, ValueError, KeyError) as exc:
        print(f"device-smoke-test: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
