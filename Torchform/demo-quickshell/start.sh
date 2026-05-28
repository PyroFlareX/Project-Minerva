#!/bin/sh
# start.sh — Launch Torchform QuickShell demo (headless Sway + wayvnc)
# Mirrors the proven remote-vnc pattern from the main Torchform Makefile.
#
# Usage (on Minerva directly):
#   ./start.sh
#
# From workstation Makefile target (remote-vnc-qs):
#   ssh minerva 'cd ~/projects/demo-quickshell && ./start.sh' &
#   ssh -L 5900:localhost:5900 minerva -N &
#   gvncviewer localhost::5900
set -e

DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"
VNC_PORT="${VNC_PORT:-5900}"
XDG_RUNTIME_DIR=/tmp/xdg-qs-vnc

# ── Clean up any stale session ───────────────────────────────────────────────
pkill -9 -f wayvnc  2>/dev/null || true
pkill -9 -f quickshell 2>/dev/null || true
pkill -9 -f "sway.*torchform" 2>/dev/null || true
sleep 1
rm -rf "$XDG_RUNTIME_DIR"

# ── Runtime dir ──────────────────────────────────────────────────────────────
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
export XDG_RUNTIME_DIR

# ── Headless Wayland env ──────────────────────────────────────────────────────
export WLR_BACKENDS=headless
export WLR_HEADLESS_OUTPUTS=1
export DISPLAY=
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export QT_SCALE_FACTOR=1

# ── Start Sway (headless) ────────────────────────────────────────────────────
echo ">> Starting headless Sway..."
sway -c "$DEMO_DIR/sway.conf" &
SWAY_PID=$!

# Wait for Wayland socket
for i in $(seq 1 40); do
    SOCK=$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | grep -v lock | head -1)
    [ -n "$SOCK" ] && break
    sleep 0.25
done
[ -z "$SOCK" ] && { echo "ERROR: Sway socket not found"; kill $SWAY_PID 2>/dev/null; exit 1; }

export WAYLAND_DISPLAY="$(basename "$SOCK")"
echo ">> Wayland socket: $WAYLAND_DISPLAY"

# Set headless output resolution to 1920x1080
sleep 1
WAYLAND_DISPLAY="$WAYLAND_DISPLAY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    wlr-randr --output HEADLESS-1 --custom-mode 1920x1080 2>/dev/null || true
sleep 0.5

# ── Start QuickShell ─────────────────────────────────────────────────────────
echo ">> Starting QuickShell..."
cd "$DEMO_DIR"
# QuickShell resolves shell.qml via XDG config profile "default".
# Ensure the symlink points at our demo dir.
mkdir -p "$HOME/.config/quickshell"
ln -sfn "$DEMO_DIR" "$HOME/.config/quickshell/default"

WAYLAND_DISPLAY="$WAYLAND_DISPLAY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    quickshell &
QS_PID=$!
sleep 2

# ── Start wayvnc (localhost only — use SSH tunnel from workstation) ───────────
echo ">> Starting wayvnc on 127.0.0.1:$VNC_PORT ..."
WAYLAND_DISPLAY="$WAYLAND_DISPLAY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    wayvnc --output=HEADLESS-1 127.0.0.1 "$VNC_PORT" &
VNC_PID=$!

echo ""
echo "Torchform QuickShell demo running."
echo "  SSH tunnel from workstation:"
echo "    ssh -L $VNC_PORT:localhost:$VNC_PORT minerva -N &"
echo "    gvncviewer localhost::$VNC_PORT"
echo ""
echo "  Keys: Space=Home  A=Confirm  Esc=Back  X=Palette"
echo "        Z=QS  C=Notifs  Tab=Radial  Enter=Switcher  Arrows=Nav"
echo ""
echo "  Stop: kill $SWAY_PID"

wait $SWAY_PID
echo "Sway exited. Cleaning up."
kill $QS_PID $VNC_PID 2>/dev/null || true
rm -rf "$XDG_RUNTIME_DIR"
