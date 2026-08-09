#!/usr/bin/env python3
"""Send logical gamepad actions to Minerva's virtual controller backend.

The device-side ``virtual-gamepad.py`` owns a real ``/dev/uinput`` gamepad
named ``torchform-virtpad``. This host-side helper makes ad-hoc controller
checks convenient without keyboard or pointer injection::

    python3 scripts/emulate-controller.py --host Minerva tap A
    python3 scripts/emulate-controller.py --host Minerva hold L1 1.0
    python3 scripts/emulate-controller.py --host Minerva sequence A UP RIGHT

The virtual-gamepad backend must already be running, normally via
``device-smoke-test.py --restart``. ``list`` and ``--dry-run`` work without a
Minerva connection.
"""

from __future__ import annotations

import argparse
import os
import shlex
import subprocess
import sys
import time
from collections.abc import Sequence

SSH_BASE = ["ssh", "-T", "-o", "ForwardX11=no"]
DEFAULT_HOST = os.environ.get("MINERVA_HOST", "Minerva")
DEFAULT_SOCKET = "/tmp/xdg-hdmi/torchform/virtual-gamepad.sock"
DEFAULT_REMOTE_SCRIPT = "$HOME/projects/torchform-guishell/virtual-gamepad.py"
DEFAULT_TAP_DURATION = 0.04

BUTTONS = (
    "south",
    "east",
    "west",
    "north",
    "l1",
    "r1",
    "l2",
    "r2",
    "select",
    "start",
    "mode",
    "thumbl",
    "thumbr",
    "dpad_up",
    "dpad_down",
    "dpad_left",
    "dpad_right",
)

ALIASES = {
    "a": "south",
    "b": "east",
    "x": "west",
    "y": "north",
    "cross": "south",
    "circle": "east",
    "square": "west",
    "triangle": "north",
    "up": "dpad_up",
    "down": "dpad_down",
    "left": "dpad_left",
    "right": "dpad_right",
    "dpadup": "dpad_up",
    "dpaddown": "dpad_down",
    "dpadleft": "dpad_left",
    "dpadright": "dpad_right",
    "l": "l1",
    "r": "r1",
}
ALIASES.update({button: button for button in BUTTONS})


class ControllerError(RuntimeError):
    """An emulator command could not be delivered or was invalid."""


def canonical_button(raw: str) -> str:
    key = raw.strip().lower().replace("-", "_")
    key = key.replace("_", "") if key.startswith("dpad") else key
    button = ALIASES.get(key)
    if button is None:
        choices = ", ".join(BUTTONS)
        raise ControllerError(f"unknown button {raw!r}; use one of: {choices}")
    return button


def remote_script_argument(path: str) -> str:
    if path.startswith("$HOME/"):
        suffix = path[len("$HOME/") :]
        if not suffix or any(char in suffix for char in "'\"`;&|<>$\\"):
            raise ControllerError(f"unsafe remote script path {path!r}")
        return f'"$HOME/{suffix}"'
    return shlex.quote(path)


def remote_command(args: argparse.Namespace, command: Sequence[str]) -> str:
    return (
        f"python3 {remote_script_argument(args.remote_script)}"
        f" --socket {shlex.quote(args.socket)}"
        f" {shlex.join(command)}"
    )


def send(args: argparse.Namespace, command: Sequence[str]) -> None:
    command_text = remote_command(args, command)
    ssh_command = SSH_BASE + [args.host, command_text]
    if args.dry_run:
        print(shlex.join(ssh_command))
        return
    proc = subprocess.run(ssh_command, text=True, capture_output=True)
    if proc.returncode != 0:
        detail = proc.stderr.strip() or proc.stdout.strip() or "remote command failed"
        raise ControllerError(f"{args.host}: {detail}")


def tap(args: argparse.Namespace, button: str, duration: float) -> None:
    # Keep the normal tap in one SSH command so network latency cannot make
    # the button appear held long enough to trigger QML's repeat timer.
    if duration == DEFAULT_TAP_DURATION:
        send(args, ["tap", button])
        return
    send(args, ["press", button])
    try:
        time.sleep(duration)
    finally:
        send(args, ["release", button])


def run(args: argparse.Namespace) -> int:
    if args.operation == "list":
        for button in BUTTONS:
            aliases = sorted(alias for alias, value in ALIASES.items() if value == button and alias != button)
            suffix = f" ({', '.join(aliases)})" if aliases else ""
            print(f"{button}{suffix}")
        return 0

    if args.operation == "press":
        send(args, ["press", canonical_button(args.button)])
        return 0
    if args.operation == "release":
        send(args, ["release", canonical_button(args.button)])
        return 0
    if args.operation == "tap":
        tap(args, canonical_button(args.button), args.duration)
        return 0
    if args.operation == "hold":
        button = canonical_button(args.button)
        send(args, ["press", button])
        try:
            time.sleep(args.seconds)
        finally:
            send(args, ["release", button])
        return 0
    if args.operation == "sequence":
        for index, raw_button in enumerate(args.buttons):
            tap(args, canonical_button(raw_button), args.duration)
            if index + 1 < len(args.buttons):
                time.sleep(args.delay)
        return 0

    raise ControllerError(f"unsupported operation {args.operation!r}")


def parser() -> argparse.ArgumentParser:
    command = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    command.add_argument("--host", default=DEFAULT_HOST, help="SSH host (default: %(default)s)")
    command.add_argument("--socket", default=DEFAULT_SOCKET, help="remote virtual-gamepad socket")
    command.add_argument("--remote-script", default=DEFAULT_REMOTE_SCRIPT, help="remote virtual-gamepad.py path")
    command.add_argument("--dry-run", action="store_true", help="print SSH commands without sending them")
    sub = command.add_subparsers(dest="operation", required=True)

    sub.add_parser("list", help="list logical buttons and aliases")
    for operation in ("press", "release"):
        item = sub.add_parser(operation, help=f"{operation} a logical button")
        item.add_argument("button")
    tap_parser = sub.add_parser("tap", help="press and release a button")
    tap_parser.add_argument("button")
    tap_parser.add_argument("--duration", type=float, default=0.04, help="held duration in seconds")
    hold_parser = sub.add_parser("hold", help="hold a button for a duration")
    hold_parser.add_argument("button")
    hold_parser.add_argument("seconds", type=float)
    sequence = sub.add_parser("sequence", help="tap buttons in order")
    sequence.add_argument("buttons", nargs="+")
    sequence.add_argument("--delay", type=float, default=0.12, help="delay between taps in seconds")
    sequence.add_argument("--duration", type=float, default=0.04, help="duration of each tap in seconds")
    return command


def main() -> int:
    args = parser().parse_args()
    try:
        return run(args)
    except (ControllerError, OSError, ValueError) as exc:
        print(f"emulate-controller: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
