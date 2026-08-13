"""Create a named Linux virtual gamepad and serve deterministic button/axis input.

This is a device-side smoke-test backend. It talks to ``/dev/uinput`` using
only Python's standard library, so tests exercise QuickShell's real Gamepad
plugin rather than keyboard or pointer events. The daemon owns a
``torchform-virtpad`` device and accepts one command per line on a private
Unix socket::

    tap south
    tap dpad_down
    press l2
    release l2
    axis left_y -1
    axis left_y 0

Axis values are normalized to the Gamepad plugin's ``[-1, 1]`` range. The
normal Torchform input daemon is disabled by the smoke harness while this
backend is active; both devices intentionally use the same public gamepad
name so the existing plugin discovers the test pad without a rebuild.
"""

from __future__ import annotations

import argparse
import fcntl
import os
import signal
import socket
import struct
import sys
import time
from pathlib import Path


DEVICE_NAME = b"torchform-virtpad"
DEFAULT_SOCKET = "/tmp/torchform-virtual-gamepad.sock"
DEFAULT_READY = "/tmp/torchform-virtual-gamepad.ready"

EV_SYN = 0x00
EV_KEY = 0x01
EV_ABS = 0x03
SYN_REPORT = 0

ABS_X = 0x00
ABS_Y = 0x01
ABS_Z = 0x02
ABS_RX = 0x03
ABS_RY = 0x04
ABS_RZ = 0x05

BTN_SOUTH = 0x130
BTN_EAST = 0x131
BTN_WEST = 0x134
BTN_NORTH = 0x133
BTN_TL = 0x136
BTN_TR = 0x137
BTN_TL2 = 0x138
BTN_TR2 = 0x139
BTN_SELECT = 0x13A
BTN_START = 0x13B
BTN_MODE = 0x13C
BTN_THUMBL = 0x13D
BTN_THUMBR = 0x13E
BTN_DPAD_UP = 0x220
BTN_DPAD_DOWN = 0x221
BTN_DPAD_LEFT = 0x222
BTN_DPAD_RIGHT = 0x223

BUTTONS = {
    "south": BTN_SOUTH,
    "east": BTN_EAST,
    "west": BTN_WEST,
    "north": BTN_NORTH,
    "l1": BTN_TL,
    "r1": BTN_TR,
    "l2": BTN_TL2,
    "r2": BTN_TR2,
    "select": BTN_SELECT,
    "start": BTN_START,
    "mode": BTN_MODE,
    "thumbl": BTN_THUMBL,
    "thumbr": BTN_THUMBR,
    "dpad_up": BTN_DPAD_UP,
    "dpad_down": BTN_DPAD_DOWN,
    "dpad_left": BTN_DPAD_LEFT,
    "dpad_right": BTN_DPAD_RIGHT,
}

AXES = {
    "left_x": ABS_X,
    "left_y": ABS_Y,
    "right_x": ABS_RX,
    "right_y": ABS_RY,
}


def _ioc(direction: int, number: int, size: int) -> int:
    return (direction << 30) | (size << 16) | (ord("U") << 8) | number


_IO = 0
_IOW = 1
UI_SET_EVBIT = _ioc(_IOW, 100, 4)
UI_SET_KEYBIT = _ioc(_IOW, 101, 4)
UI_SET_ABSBIT = _ioc(_IOW, 103, 4)
UI_DEV_CREATE = _ioc(_IO, 1, 0)
UI_DEV_DESTROY = _ioc(_IO, 2, 0)


def _set_bit(fd: int, request: int, value: int) -> None:
    # fcntl's integer argument form matches the kernel's int pointer ABI for
    # UI_SET_* ioctls. Passing packed bytes produces EINVAL on this kernel.
    fcntl.ioctl(fd, request, value)


def _event(sec: int, usec: int, event_type: int, code: int, value: int) -> bytes:
    # Linux aarch64/x86_64 input_event: timeval (two native longs) + HHI.
    return struct.pack("@llHHi", sec, usec, event_type, code, value)


class VirtualPad:
    def __init__(self, device_path: str = "/dev/uinput") -> None:
        self.fd = os.open(device_path, os.O_WRONLY | os.O_NONBLOCK | os.O_CLOEXEC)
        self.closed = False
        try:
            _set_bit(self.fd, UI_SET_EVBIT, EV_KEY)
            _set_bit(self.fd, UI_SET_EVBIT, EV_ABS)
            for code in BUTTONS.values():
                _set_bit(self.fd, UI_SET_KEYBIT, code)
            for code in (ABS_X, ABS_Y, ABS_RX, ABS_RY, ABS_Z, ABS_RZ):
                _set_bit(self.fd, UI_SET_ABSBIT, code)

            abs_max = [0] * 64
            abs_min = [0] * 64
            abs_fuzz = [0] * 64
            abs_flat = [0] * 64
            for code in (ABS_X, ABS_Y, ABS_RX, ABS_RY):
                abs_min[code] = -32768
                abs_max[code] = 32767
            for code in (ABS_Z, ABS_RZ):
                abs_max[code] = 255

            descriptor = struct.pack(
                "@80sHHHHI64i64i64i64i",
                DEVICE_NAME.ljust(80, b"\0"),
                0x03,  # BUS_USB
                0x1234,
                0x5678,
                0x0111,
                0,
                *abs_max,
                *abs_min,
                *abs_fuzz,
                *abs_flat,
            )
            os.write(self.fd, descriptor)
            fcntl.ioctl(self.fd, UI_DEV_CREATE)
            time.sleep(0.2)
        except BaseException:
            os.close(self.fd)
            raise

    def write_button(self, name: str, pressed: bool) -> None:
        try:
            code = BUTTONS[name]
        except KeyError as exc:
            raise ValueError(f"unknown virtual gamepad button {name!r}") from exc
        now = time.time_ns()
        payload = _event(now // 1_000_000_000, (now // 1_000) % 1_000_000, EV_KEY, code, int(pressed))
        payload += _event(0, 0, EV_SYN, SYN_REPORT, 0)
        os.write(self.fd, payload)

    def write_axis(self, name: str, value: float | None = None) -> None:
        if name == "neutral":
            axis_values = [(code, 0) for code in AXES.values()]
        else:
            if value is None:
                raise ValueError("axis value is required")
            try:
                code = AXES[name]
            except KeyError as exc:
                raise ValueError(f"unknown virtual gamepad axis {name!r}") from exc
            normalized = max(-1.0, min(1.0, float(value)))
            axis_values = [(code, round(normalized * 32767))]
        now = time.time_ns()
        payload = b"".join(
            _event(
                now // 1_000_000_000,
                (now // 1_000) % 1_000_000,
                EV_ABS,
                code,
                raw_value,
            )
            for code, raw_value in axis_values
        )
        payload += _event(0, 0, EV_SYN, SYN_REPORT, 0)
        os.write(self.fd, payload)

    def tap(self, name: str, duration: float = 0.04) -> None:
        self.write_button(name, True)
        time.sleep(duration)
        self.write_button(name, False)

    def close(self) -> None:
        if self.closed:
            return
        self.closed = True
        try:
            fcntl.ioctl(self.fd, UI_DEV_DESTROY)
        finally:
            os.close(self.fd)


def serve(args: argparse.Namespace) -> int:
    socket_path = Path(args.socket)
    ready_path = Path(args.ready)
    pid_path = Path(args.pid_file) if args.pid_file else None
    socket_path.unlink(missing_ok=True)
    ready_path.unlink(missing_ok=True)
    if pid_path:
        pid_path.write_text(f"{os.getpid()}\n")

    pad = VirtualPad(args.device)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(socket_path))
    os.chmod(socket_path, 0o600)
    server.listen(4)
    ready_path.write_text("ready\n")
    print(f"virtual gamepad ready: {DEVICE_NAME.decode()}", flush=True)

    stopping = False

    def stop(_signum: int, _frame: object) -> None:
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        while not stopping:
            server.settimeout(0.25)
            try:
                conn, _ = server.accept()
            except socket.timeout:
                continue
            # A client that sends commands and closes without reading the reply
            # makes sendall() raise ConnectionResetError/BrokenPipeError.  That
            # must end the connection, never the daemon: losing the pad here
            # would silently disable input for the rest of the smoke session.
            try:
                with conn:
                    stream = conn.makefile("r", encoding="utf-8")
                    for raw in stream:
                        command = raw.strip().split()
                        if not command:
                            continue
                        try:
                            op = command[0].lower()
                            if op == "tap" and len(command) == 2:
                                pad.tap(command[1])
                                response = "ok"
                            elif op == "press" and len(command) == 2:
                                pad.write_button(command[1], True)
                                response = "ok"
                            elif op == "release" and len(command) == 2:
                                pad.write_button(command[1], False)
                                response = "ok"
                            elif op == "axis" and len(command) == 3:
                                pad.write_axis(command[1], float(command[2]))
                                response = "ok"
                            elif op == "axis" and len(command) == 2 and command[1] == "neutral":
                                pad.write_axis("neutral")
                                response = "ok"
                            elif op == "sleep" and len(command) == 2:
                                time.sleep(float(command[1]))
                                response = "ok"
                            elif op == "quit" and len(command) == 1:
                                stopping = True
                                response = "ok"
                            else:
                                raise ValueError("expected tap|press|release|axis|sleep|quit")
                        except (OSError, ValueError) as exc:
                            response = f"error {exc}"
                        conn.sendall((response + "\n").encode())
                        if stopping:
                            break
            except OSError as exc:
                print(f"client disconnected: {exc}", flush=True)
    finally:
        server.close()
        socket_path.unlink(missing_ok=True)
        ready_path.unlink(missing_ok=True)
        if pid_path:
            pid_path.unlink(missing_ok=True)
        pad.close()
    return 0


def send_command(args: argparse.Namespace) -> int:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        try:
            client.connect(args.socket)
        except FileNotFoundError as exc:
            raise SystemExit(f"virtual gamepad socket not found: {args.socket}") from exc
        client.sendall((" ".join(args.command) + "\n").encode())
        response = client.recv(4096).decode().strip()
    if response and response != "ok":
        print(response, file=sys.stderr)
        return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket", default=DEFAULT_SOCKET)
    parser.add_argument("--ready", default=DEFAULT_READY)
    parser.add_argument("--pid-file")
    parser.add_argument("--device", default="/dev/uinput")
    parser.add_argument("--daemon", action="store_true")
    parser.add_argument("command", nargs="*")
    args = parser.parse_args()
    if args.daemon:
        if args.command:
            parser.error("--daemon does not accept a command")
        return serve(args)
    if not args.command:
        parser.error("provide a command or use --daemon")
    return send_command(args)


if __name__ == "__main__":
    raise SystemExit(main())
