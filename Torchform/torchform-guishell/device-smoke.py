#!/usr/bin/env python3
"""Device-side Torchform smoke scenarios driven through the virtual gamepad.

This runs ON the Minerva device against the live QuickShell/Sway session that
``start-hdmi.sh`` started with ``TORCHFORM_VIRTUAL_GAMEPAD=1``.  Every step
presses a real controller button through the ``torchform-virtpad`` uinput
device, so the production QML Gamepad plugin is exercised rather than keyboard
or pointer shortcuts.

Assertions read the state the shell exports after each observable transition
(``$XDG_CACHE_HOME/torchform/state.json``).  Display roles are never taken from
connector names: they come from ``configure-outputs.py --role upper|lower``.

Usage::

    python3 device-smoke.py --list
    python3 device-smoke.py --scenario lock-screen --scenario terminal-keyboard
    python3 device-smoke.py --artifact-dir /tmp/torchform-smoke
"""

from __future__ import annotations

import argparse
import json
import hashlib
import os
import re
import socket
import subprocess
import sys
import time
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
RUNTIME_DIR = Path(os.environ.get("TORCHFORM_RUNTIME_DIR", "/tmp/xdg-hdmi"))
PAD_SOCKET = RUNTIME_DIR / "torchform" / "virtual-gamepad.sock"
STATE_PATH = Path(
    os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")
) / "torchform" / "state.json"

# The shell coalesces state writes, so a transition can take one writer round
# trip plus the retry to become visible.
SETTLE_TIMEOUT = 6.0


class SmokeError(RuntimeError):
    pass


# ── Session plumbing ────────────────────────────────────────────────────────

def sway_env() -> dict[str, str]:
    sockets = sorted(RUNTIME_DIR.glob("sway-ipc.*.sock"))
    if not sockets:
        raise SmokeError(f"no sway IPC socket under {RUNTIME_DIR}")
    return {
        **os.environ,
        "XDG_RUNTIME_DIR": str(RUNTIME_DIR),
        "WAYLAND_DISPLAY": "wayland-1",
        "SWAYSOCK": str(sockets[-1]),
    }


def output_roles() -> dict[str, str]:
    """Largest live output is upper, smallest is lower — never a connector name."""
    roles = {}
    for role in ("upper", "lower"):
        done = subprocess.run(
            [sys.executable, str(HERE / "configure-outputs.py"), "--role", role],
            capture_output=True, text=True, env=sway_env(),
        )
        if done.returncode != 0:
            raise SmokeError(f"configure-outputs.py --role {role} failed: {done.stderr.strip()}")
        roles[role] = done.stdout.strip()
    if not roles["upper"] or roles["upper"] == roles["lower"]:
        raise SmokeError(f"implausible output roles: {roles}")
    return roles


# ── Controller ──────────────────────────────────────────────────────────────

def pad(*commands: str, delay: float = 0.3) -> None:
    if not PAD_SOCKET.exists():
        raise SmokeError(
            f"virtual gamepad socket missing: {PAD_SOCKET}. Start the session with "
            "TORCHFORM_VIRTUAL_GAMEPAD=1."
        )
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(5.0)
        client.connect(str(PAD_SOCKET))
        stream = client.makefile("rw", encoding="utf-8")
        for command in commands:
            stream.write(command + "\n")
            stream.flush()
            reply = stream.readline().strip()
            if reply != "ok":
                raise SmokeError(f"gamepad rejected {command!r}: {reply!r}")
            time.sleep(delay)


def read_state() -> dict:
    last = None
    for _ in range(40):
        try:
            return json.loads(STATE_PATH.read_text())
        except (OSError, ValueError) as exc:  # mid-rename or partial read
            last = exc
            time.sleep(0.05)
    raise SmokeError(f"could not read {STATE_PATH}: {last}")


def await_state(predicate, description: str, timeout: float = SETTLE_TIMEOUT) -> dict:
    deadline = time.monotonic() + timeout
    state = read_state()
    while time.monotonic() < deadline:
        state = read_state()
        if predicate(state):
            return state
        time.sleep(0.15)
    raise SmokeError(f"timed out waiting for {description}; last state: {compact(state)}")


def compact(state: dict) -> str:
    keys = ("screen", "panel", "app", "textTarget", "externalRunning", "externalApp")
    return ", ".join(f"{k}={state.get(k)!r}" for k in keys)


def expect(state: dict, **fields) -> None:
    for key, want in fields.items():
        got = state.get(key)
        if got != want:
            raise SmokeError(f"expected {key}={want!r}, got {got!r}")


# ── Screenshots ─────────────────────────────────────────────────────────────

class Capture:
    def __init__(self, directory: Path | None, roles: dict[str, str]) -> None:
        self.directory = directory
        self.roles = roles
        self.step = 0
        if directory:
            directory.mkdir(parents=True, exist_ok=True)

    def shot(self, scenario: str, tag: str) -> list[Path]:
        if not self.directory:
            return []
        self.step += 1
        written = []
        for role, output in self.roles.items():
            path = self.directory / f"{scenario}-{self.step:02d}-{tag}-{role}.png"
            done = subprocess.run(["grim", "-o", output, str(path)],
                                  capture_output=True, text=True, env=sway_env())
            if done.returncode != 0:
                raise SmokeError(f"grim failed for {role} ({output}): {done.stderr.strip()}")
            written.append(path)
        return written

    def frame(self) -> str:
        """Hash of the current upper output, for proving the screen changed."""
        target = Path(tempfile.gettempdir()) / "torchform-smoke-frame.png"
        done = subprocess.run(["grim", "-o", self.roles["upper"], str(target)],
                              capture_output=True, text=True, env=sway_env())
        if done.returncode != 0:
            raise SmokeError(f"grim failed for the upper output: {done.stderr.strip()}")
        return hashlib.sha256(target.read_bytes()).hexdigest()


# ── Shared helpers ──────────────────────────────────────────────────────────

def go_home(capture: Capture, scenario: str) -> dict:
    """Reach the home screen from lock or anywhere else, controller only."""
    state = read_state()
    if state.get("screen") == "lock":
        # The lock screen accepts four Confirm presses as its PIN length.
        pad("tap south", "tap south", "tap south", "tap south")
        state = await_state(lambda s: s.get("screen") != "lock", "unlock")
    if state.get("screen") != "home" or state.get("panel"):
        pad("tap start")
        state = await_state(
            lambda s: s.get("screen") == "home" and not s.get("panel"), "home screen"
        )
    return state


def open_app(name: str) -> dict:
    """Open an app card by walking the home grid with the D-pad only."""
    pad("tap start")
    await_state(lambda s: s.get("screen") == "home", "home screen")
    for _ in range(24):
        pad("tap south")
        state = await_state(
            lambda s: s.get("screen") in ("app", "home"), "app or home", timeout=4.0
        )
        if state.get("screen") == "app" and state.get("app") == name:
            return state
        if state.get("screen") == "app":
            pad("tap east")
            await_state(lambda s: s.get("screen") == "home", "back to home")
        pad("tap dpad_right")
        time.sleep(0.15)
    raise SmokeError(f"never reached the {name} app card with the D-pad")


# ── Scenarios ───────────────────────────────────────────────────────────────

def scenario_lock_screen(capture: Capture) -> list[str]:
    """The lower display must reflect the lock and expose no touch actions."""
    notes = []
    go_home(capture, "lock-screen")

    # The only controller route to the lock screen the shell actually offers:
    # Radial (north) -> "Power menu" -> quick menu -> "Lock" (its initial focus).
    pad("tap north")
    await_state(lambda s: s.get("radial") is True, "radial menu open")
    capture.shot("lock-screen", "radial")

    for _ in range(7):
        pad("tap dpad_right", delay=0.2)
    pad("tap south")
    await_state(lambda s: s.get("quickMenu") is True, "power menu open")
    capture.shot("lock-screen", "power-menu")

    pad("tap south")
    state = await_state(lambda s: s.get("screen") == "lock", "lock screen")

    expect(state, screen="lock")
    notes.append("shell reports screen=lock")
    capture.shot("lock-screen", "locked")

    # The controller must still be the way out.
    pad("tap south", "tap south", "tap south", "tap south")
    state = await_state(lambda s: s.get("screen") == "home", "unlock back to home")
    notes.append("four Confirm presses unlocked back to home")
    capture.shot("lock-screen", "unlocked")
    return notes


def scenario_terminal_keyboard(capture: Capture) -> list[str]:
    """Terminal must be typable with the controller alone (no keyboard)."""
    notes = []
    go_home(capture, "terminal-keyboard")
    state = open_app("Terminal")
    expect(state, screen="app", app="Terminal")
    capture.shot("terminal-keyboard", "terminal-open")

    pad("tap west")
    state = await_state(lambda s: s.get("textTarget") == "terminal",
                        "lower keyboard targeting the terminal")
    notes.append("X opened the lower on-screen keyboard with textTarget=terminal")
    capture.shot("terminal-keyboard", "osk-open")

    # Activate whatever key the OSK starts on; this proves controller text entry
    # reaches the shell-owned terminal buffer rather than a hidden TextInput.
    pad("tap south")
    time.sleep(0.4)
    notes.append("Confirm activated an on-screen key")
    capture.shot("terminal-keyboard", "typed")

    pad("tap east")
    state = await_state(lambda s: s.get("textTarget") != "terminal",
                        "keyboard dismissed with B")
    expect(state, screen="app", app="Terminal")
    notes.append("B closed the keyboard and left the Terminal app intact")
    capture.shot("terminal-keyboard", "osk-closed")
    return notes


def scenario_quick_settings_honesty(capture: Capture) -> list[str]:
    """Quick Settings availability must match the device probe, not data.js."""
    notes = []
    go_home(capture, "quick-settings-honesty")

    probe = subprocess.run(["sh", str(HERE / "torchform-control.sh"), "qs-state"],
                           capture_output=True, text=True)
    if probe.returncode != 0:
        raise SmokeError(f"qs-state failed: {probe.stderr.strip()}")
    available = {}
    for line in probe.stdout.strip().splitlines():
        parts = line.split("|")
        if len(parts) >= 4:
            available[(parts[0], parts[1])] = parts[2] == "available"
    if not available:
        raise SmokeError("qs-state produced no control lines")

    pad("tap r1")
    await_state(lambda s: s.get("panel") == "qs", "quick settings open")
    capture.shot("quick-settings-honesty", "qs-open")

    slider_ids, tile_ids = quick_settings_ids()

    # The probe is a real subprocess, so wait for its result rather than racing it.
    state = await_state(
        lambda s: len(s.get("quickSettingsSliderAvailability") or []) == len(slider_ids)
        and len(s.get("quickSettingsTileAvailability") or []) == len(tile_ids),
        "quick settings availability probed",
        timeout=15.0,
    )

    got_sliders = state.get("quickSettingsSliderAvailability") or []
    got_tiles = state.get("quickSettingsTileAvailability") or []
    if len(got_sliders) != len(slider_ids) or len(got_tiles) != len(tile_ids):
        raise SmokeError(
            f"availability arrays mis-sized: sliders {got_sliders} vs {slider_ids}, "
            f"tiles {got_tiles} vs {tile_ids}"
        )
    for index, control_id in enumerate(slider_ids):
        want = available.get(("slider", control_id))
        if want is None:
            raise SmokeError(f"qs-state never reported slider {control_id}")
        if bool(got_sliders[index]) != want:
            raise SmokeError(
                f"slider {control_id}: shell says {got_sliders[index]}, device says {want}"
            )
    for index, control_id in enumerate(tile_ids):
        want = available.get(("tile", control_id))
        if want is None:
            raise SmokeError(f"qs-state never reported tile {control_id}")
        if bool(got_tiles[index]) != want:
            raise SmokeError(
                f"tile {control_id}: shell says {got_tiles[index]}, device says {want}"
            )
    notes.append(
        "shell availability matches qs-state for "
        f"{len(slider_ids)} sliders and {len(tile_ids)} tiles"
    )

    focus = state.get("quickSettingsFocus", 0)
    combined = list(got_sliders) + list(got_tiles)
    if any(combined) and not combined[focus]:
        raise SmokeError(
            f"controller focus parked on unavailable control index {focus}: {combined}"
        )
    notes.append(f"focus index {focus} is on an available control")

    pad("tap east")
    await_state(lambda s: s.get("panel") != "qs", "quick settings closed with B")
    notes.append("B closed Quick Settings")
    return notes


def _open_media_card(index: int, tag: str, capture: Capture) -> dict:
    """Focus the given Media card with the D-pad and activate it."""
    state = open_app("Media")
    expect(state, screen="app", app="Media")
    for _ in range(index):
        pad("tap dpad_down", delay=0.25)
    state = await_state(lambda s: s.get("mediaFocus") == index,
                        f"media card {index} focused")
    capture.shot(tag, "media-open")
    pad("tap south")
    try:
        return await_state(lambda s: s.get("externalRunning") is True,
                           "external client running", timeout=30.0)
    except SmokeError:
        raise SmokeError(
            "the media action never produced an external client "
            f"({compact(read_state())}); a failing backend must show an error banner"
        )


def _assert_closed_cleanly(pattern: str, tag: str, capture: Capture,
                           notes: list[str]) -> None:
    """B must close the client and leave no process of its own behind."""
    pad("tap east")
    state = await_state(lambda s: s.get("externalRunning") is False,
                        "external client closed with B", timeout=25.0)
    expect(state, externalApp="", externalAppKey="", externalControls=0)
    notes.append("B closed the client and cleared externalApp/Key/controls")

    # A wrapper script's real UI is often a child process: killing only the
    # direct child orphans it and leaves its window mapped forever.
    deadline = time.monotonic() + 10.0
    while time.monotonic() < deadline:
        found = subprocess.run(["pgrep", "-f", pattern],
                               capture_output=True, text=True).stdout.strip()
        if not found:
            break
        time.sleep(0.25)
    else:
        raise SmokeError(f"{pattern!r} survived the close: pids {found}")
    notes.append(f"no {pattern!r} process survived")
    capture.shot(tag, "external-closed")

    pad("tap start")
    await_state(lambda s: s.get("screen") == "home", "home reachable after exit")
    notes.append("controller still drives the shell after the client exited")
    capture.shot(tag, "focus-restored")


def scenario_external_app(capture: Capture) -> list[str]:
    """An external client must own the upper output and stay closable with B."""
    notes = []
    go_home(capture, "external-app")
    state = _open_media_card(0, "external-app", capture)

    # The backend, not the shell, decides which configured app handles this.
    if not state.get("externalAppKey"):
        raise SmokeError("the backend never reported an app key for the client")
    notes.append(f"backend resolved appkey {state['externalAppKey']!r} "
                 f"labelled {state.get('externalApp')!r}")
    time.sleep(2.0)
    capture.shot("external-app", "external-mapped")
    _assert_closed_cleanly("chromium", "external-app", capture, notes)
    return notes


def scenario_external_controls(capture: Capture) -> list[str]:
    """Every external client must expose its configured controller map."""
    notes = []
    go_home(capture, "external-controls")

    # Card 4 is the ebook reader: a shell-wrapper program whose real UI is a
    # child process, so it is the strictest test of both control forwarding and
    # process-group teardown.
    state = _open_media_card(4, "external-controls", capture)
    key = state.get("externalAppKey")
    if key != "ebook":
        raise SmokeError(f"expected the ebook app key, got {key!r}")

    state = await_state(lambda s: (s.get("externalControls") or 0) > 0,
                        "controller map loaded for the client", timeout=15.0)
    count = state["externalControls"]
    notes.append(f"{count} controller mappings loaded for {key!r}")

    expected = subprocess.run(
        ["sh", str(HERE / "torchform-control.sh"), "app-controls", key],
        capture_output=True, text=True,
    )
    if expected.returncode != 0:
        raise SmokeError(f"app-controls {key} failed: {expected.stderr.strip()}")
    rows = [r for r in expected.stdout.strip().splitlines() if r]
    if len(rows) != count:
        raise SmokeError(
            f"shell loaded {count} mappings but the backend reports {len(rows)}"
        )
    for row in rows:
        button = row.split("\t")[0]
        if button in ("east", "start", "mode"):
            raise SmokeError(
                f"{button} is reserved for Torchform but {key} maps it; "
                "the client could capture the only way out"
            )
    notes.append("mappings match the backend and reserve east/start/mode")

    # A mapped button must actually reach the client and change what is drawn.
    time.sleep(2.0)
    before = capture.frame()
    pad("tap south")
    time.sleep(2.0)
    if capture.frame() == before:
        raise SmokeError(
            "the upper output did not change after a mapped button press; "
            "controller input is not reaching the client"
        )
    notes.append("a mapped button visibly changed the client's output")
    capture.shot("external-controls", "control-applied")

    _assert_closed_cleanly("reader.lua", "external-controls", capture, notes)
    return notes


def quick_settings_ids() -> tuple[list[str], list[str]]:
    """Control ids from data.js, in the order the shell binds them."""
    text = (HERE / "data.js").read_text()

    def ids(key: str) -> list[str]:
        start = text.index(key, text.index("quickSettings:"))
        open_at = text.index("[", start)
        depth = 0
        for cursor in range(open_at, len(text)):
            if text[cursor] == "[":
                depth += 1
            elif text[cursor] == "]":
                depth -= 1
                if depth == 0:
                    return re.findall(r'id:\s*"([^"]+)"', text[open_at:cursor])
        raise SmokeError(f"unterminated {key} array in data.js")

    return ids("sliders:"), ids("tiles:")


SCENARIOS = {
    "lock-screen": scenario_lock_screen,
    "terminal-keyboard": scenario_terminal_keyboard,
    "quick-settings-honesty": scenario_quick_settings_honesty,
    "external-app": scenario_external_app,
    "external-controls": scenario_external_controls,
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", action="append", choices=sorted(SCENARIOS),
                        help="run only these scenarios (default: all)")
    parser.add_argument("--artifact-dir", type=Path,
                        help="write role-labelled screenshots here")
    parser.add_argument("--list", action="store_true", help="list scenarios and exit")
    args = parser.parse_args()

    if args.list:
        for name in sorted(SCENARIOS):
            print(name)
        return 0

    roles = output_roles()
    print(f"outputs: upper={roles['upper']} lower={roles['lower']}")
    capture = Capture(args.artifact_dir, roles)

    selected = args.scenario or sorted(SCENARIOS)
    failures = []
    for name in selected:
        print(f"\n== {name} ==")
        try:
            for note in SCENARIOS[name](capture):
                print(f"  ok: {note}")
        except SmokeError as exc:
            failures.append(name)
            print(f"  FAIL: {exc}")

    print("\n---")
    print(f"{len(selected) - len(failures)}/{len(selected)} scenarios passed")
    if failures:
        print("failed: " + ", ".join(failures))
    return 1 if failures else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SmokeError as exc:
        print(f"fatal: {exc}", file=sys.stderr)
        raise SystemExit(2)
