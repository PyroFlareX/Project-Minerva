#!/usr/bin/env python3
"""
send-input.py — Mock gamepad event sender for torchform-inputd testing.

Connects to the inputd Unix socket at /run/torchform/inputd.sock and
lets you send controller events interactively from the terminal.

Usage:
    python3 scripts/send-input.py
    python3 scripts/send-input.py --socket /tmp/inputd-test.sock

Keys (interactive mode):
    s   → Select    (command palette)
    t   → Start     (app switcher)
    a   → A         (confirm)
    b   → B         (back/dismiss)
    [   → L2 hold   (radial app1)
    ]   → R2 hold   (radial app2)
    \\   → L2+R2     (system radial)  [type [ then ] quickly]
    w   → D-pad up
    x   → D-pad down
    d   → D-pad right
    z   → D-pad left
    ,   → L1 (switch tile left)
    .   → R1 (switch tile right)
    q   → quit

These are sent as the same text strings that torchform-inputd would publish,
letting you test torchform-shell's event handling without real hardware.
"""

import socket
import sys
import os
import time
import argparse
import threading

try:
    import tty
    import termios
    HAS_TTY = True
except ImportError:
    HAS_TTY = False  # Windows


SOCKET_PATH = "/run/torchform/inputd.sock"

# Map key character → action string (matching chord.rs Debug output format)
KEY_MAP = {
    's': 'ButtonPressed(Select)',
    't': 'ButtonPressed(Start)',
    'a': 'ButtonPressed(A)',
    'b': 'ButtonPressed(B)',
    '[': 'L2HeldChange(true)',
    ']': 'R2HeldChange(true)',
    'w': 'ButtonPressed(DpadUp)',
    'x': 'ButtonPressed(DpadDown)',
    'z': 'ButtonPressed(DpadLeft)',
    'd': 'ButtonPressed(DpadRight)',
    ',': 'ButtonPressed(L1)',
    '.': 'ButtonPressed(R1)',
    # L2+R2 chord: send both
    '\\': None,  # handled specially
}

RELEASE_MAP = {
    '[': 'L2HeldChange(false)',
    ']': 'R2HeldChange(false)',
}


def send(sock, msg: str):
    try:
        sock.sendall((msg + '\n').encode())
        print(f'  → {msg}')
    except (BrokenPipeError, ConnectionResetError):
        print('Connection lost.')
        sys.exit(1)


def connect(path: str) -> socket.socket:
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.connect(path)
        print(f'Connected to {path}')
        return sock
    except FileNotFoundError:
        print(f'Socket not found: {path}')
        print('Make sure torchform-inputd is running, or start it with:')
        print('  cargo run -p torchform-inputd')
        sys.exit(1)
    except ConnectionRefusedError:
        print(f'Connection refused: {path}')
        sys.exit(1)


def interactive_loop(sock):
    if not HAS_TTY:
        print('Interactive mode not available (no tty module). Use --command mode.')
        return

    print()
    print('Interactive input mode. Keys:')
    print('  s=Select  t=Start  a=A  b=B  [=L2  ]=R2  \\=L2+R2')
    print('  w=Up  x=Down  z=Left  d=Right  ,=L1  .=R1  q=quit')
    print()

    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        while True:
            ch = sys.stdin.read(1)

            if ch == 'q' or ch == '\x03':   # q or Ctrl-C
                break

            if ch == '\\':
                # System chord: L2 + R2 simultaneously
                send(sock, 'L2HeldChange(true)')
                send(sock, 'R2HeldChange(true)')
                send(sock, 'SystemChordEntered')
                time.sleep(0.5)
                send(sock, 'SystemChordExited')
                send(sock, 'L2HeldChange(false)')
                send(sock, 'R2HeldChange(false)')
                continue

            if ch in KEY_MAP and KEY_MAP[ch] is not None:
                send(sock, KEY_MAP[ch])
                # Auto-release triggers after 1s
                if ch in RELEASE_MAP:
                    def release_later(release_msg):
                        time.sleep(1.0)
                        send(sock, release_msg)
                    t = threading.Thread(
                        target=release_later,
                        args=(RELEASE_MAP[ch],),
                        daemon=True,
                    )
                    t.start()
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

    print()
    print('Bye.')


def batch_mode(sock, commands):
    """Send a space-separated list of commands with 100ms delay between each."""
    for cmd in commands:
        cmd = cmd.strip()
        if not cmd:
            continue
        if cmd.startswith('sleep:'):
            time.sleep(float(cmd[6:]))
        else:
            send(sock, cmd)
            time.sleep(0.1)


# ---------------------------------------------------------------------------
# Pre-built test sequences
# ---------------------------------------------------------------------------

SEQUENCES = {
    'palette': [
        'ButtonPressed(Select)',          # Open palette
        'sleep:0.3',
        'ButtonPressed(DpadDown)',        # Navigate down
        'ButtonPressed(DpadDown)',
        'ButtonPressed(DpadUp)',          # Navigate up
        'sleep:0.2',
        'ButtonPressed(A)',               # Confirm
    ],
    'radial': [
        'L2HeldChange(true)',             # Open L2 radial
        'sleep:0.3',
        'ButtonPressed(DpadRight)',       # Move to next item
        'ButtonPressed(DpadRight)',
        'sleep:0.2',
        'ButtonPressed(A)',               # Select
        'L2HeldChange(false)',
    ],
    'system-radial': [
        'L2HeldChange(true)',
        'R2HeldChange(true)',
        'SystemChordEntered',
        'sleep:0.5',
        'ButtonPressed(DpadUp)',
        'ButtonPressed(A)',
        'SystemChordExited',
        'L2HeldChange(false)',
        'R2HeldChange(false)',
    ],
    'switcher': [
        'ButtonPressed(Start)',           # Open app switcher
        'sleep:0.5',
        'ButtonPressed(Start)',           # Close
    ],
}


def main():
    parser = argparse.ArgumentParser(description='Torchform mock input sender')
    parser.add_argument('--socket', default=SOCKET_PATH, help='inputd socket path')
    parser.add_argument('--sequence', choices=list(SEQUENCES.keys()),
                        help='Run a pre-built test sequence instead of interactive mode')
    parser.add_argument('--list-sequences', action='store_true',
                        help='List available test sequences')
    args = parser.parse_args()

    if args.list_sequences:
        print('Available test sequences:')
        for name, cmds in SEQUENCES.items():
            print(f'  {name:<20} ({len(cmds)} events)')
        return

    sock = connect(args.socket)

    if args.sequence:
        print(f'Running sequence: {args.sequence}')
        batch_mode(sock, SEQUENCES[args.sequence])
    else:
        interactive_loop(sock)

    sock.close()


if __name__ == '__main__':
    main()
