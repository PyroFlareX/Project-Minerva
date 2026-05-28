#!/bin/sh
# start-hdmi.sh — Launch Torchform QuickShell demo on the physical HDMI output.
#
# Unlike start.sh (headless + wayvnc), this drives the real DRM/KMS display via
# sway's auto-detected DRM backend. Requires:
#   - vc4-kms-v3d-pi5 dtoverlay enabled (so /dev/dri/card0 exists)
#   - seatd running and the invoking user in the `seat` group
#
# Usage (over SSH or on the device):
#   ~/projects/demo-quickshell/start-hdmi.sh
set -e

DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"
XDG_RUNTIME_DIR=/tmp/xdg-hdmi

# ── Sanity: DRM device present? ───────────────────────────────────────────────
if [ ! -e /dev/dri/card0 ] && [ ! -e /dev/dri/card1 ]; then
    echo "ERROR: no /dev/dri/card* — KMS not enabled."
    echo "       Add 'dtoverlay=vc4-kms-v3d-pi5' to /boot/usercfg.txt and reboot."
    exit 1
fi

# ── Clean up any stale session ───────────────────────────────────────────────
# NOTE: match by process NAME (no -f). Using `-f quickshell` would match this
# script's own command line, since it lives under demo-quickshell/, and SIGKILL
# itself before doing anything.
pkill -9 -x quickshell 2>/dev/null || true
pkill -9 -x sway 2>/dev/null || true
pkill -9 -f demo-quickshell/gamepad-map 2>/dev/null || true
sleep 1

# ── Gamepad mapper FIRST ──────────────────────────────────────────────────────
# sway only enumerates input devices present at startup (udev hotplug does not
# reliably deliver uinput devices created later), so the virtual keyboard/mouse
# must exist before sway launches.
#
# Auto-compile if source is newer than binary (or binary missing).
if [ -f "$DEMO_DIR/gamepad-map.c" ]; then
    if [ ! -x "$DEMO_DIR/gamepad-map" ] || [ "$DEMO_DIR/gamepad-map.c" -nt "$DEMO_DIR/gamepad-map" ]; then
        echo ">> Compiling gamepad-map.c..."
        gcc -O2 -o "$DEMO_DIR/gamepad-map" "$DEMO_DIR/gamepad-map.c" \
            && echo "   OK" \
            || echo "   WARNING: compile failed — gamepad will not work"
    fi
fi
if [ -x "$DEMO_DIR/gamepad-map" ]; then
    echo ">> Starting gamepad mapper..."
    setsid "$DEMO_DIR/gamepad-map" </dev/null >/tmp/gamepad-map.log 2>&1 &
    GP_PID=$!
    sleep 1
fi
rm -rf "$XDG_RUNTIME_DIR"

# ── Runtime dir ──────────────────────────────────────────────────────────────
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
export XDG_RUNTIME_DIR

# ── Wayland env (DRM backend — NO headless) ───────────────────────────────────
# unset DISPLAY entirely — a set-but-empty DISPLAY makes wlroots pick the X11
# backend (and fail). With DISPLAY/WAYLAND_DISPLAY/WLR_BACKENDS all unset,
# wlroots auto-selects the DRM backend.
unset WLR_BACKENDS WLR_HEADLESS_OUTPUTS DISPLAY
export XWAYLAND=disable
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export QT_SCALE_FACTOR=1

# ── Start Sway on the real display ────────────────────────────────────────────
echo ">> Starting Sway on DRM/KMS (HDMI)..."
sway -c "$DEMO_DIR/sway.conf" >/tmp/sway-hdmi.log 2>&1 &
SWAY_PID=$!

# Wait for Wayland socket
for i in $(seq 1 40); do
    SOCK=$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | grep -v lock | head -1)
    [ -n "$SOCK" ] && break
    sleep 0.25
done
if [ -z "$SOCK" ]; then
    echo "ERROR: Sway socket not found. Log:"
    cat /tmp/sway-hdmi.log 2>/dev/null
    kill $SWAY_PID 2>/dev/null
    exit 1
fi

export WAYLAND_DISPLAY="$(basename "$SOCK")"
echo ">> Wayland socket: $WAYLAND_DISPLAY"
sleep 1

# ── Start QuickShell ─────────────────────────────────────────────────────────
echo ">> Starting QuickShell..."
cd "$DEMO_DIR"
mkdir -p "$HOME/.config/quickshell"
ln -sfn "$DEMO_DIR" "$HOME/.config/quickshell/default"

WAYLAND_DISPLAY="$WAYLAND_DISPLAY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    quickshell >/tmp/quickshell-hdmi.log 2>&1 &
QS_PID=$!

echo ""
echo "Torchform QuickShell demo running on HDMI."
echo "  Keys: Space=Home  A=Confirm  Esc=Back  X=Palette"
echo "        Z=QS  C=Notifs  Tab=Radial  Enter=Switcher  Arrows=Nav"
echo "  Emergency exit: Mod4+Escape   |   Logs: /tmp/quickshell-hdmi.log"
echo "  Stop: kill $SWAY_PID"
echo ""

wait $SWAY_PID
echo "Sway exited. Cleaning up."
kill $QS_PID 2>/dev/null || true
[ -n "$GP_PID" ] && kill $GP_PID 2>/dev/null || true
rm -rf "$XDG_RUNTIME_DIR"
