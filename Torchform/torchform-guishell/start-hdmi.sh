#!/bin/sh
# start-hdmi.sh — Launch Torchform QuickShell on the physical HDMI outputs.
#
# Unlike start.sh (headless + wayvnc), this drives the real DRM/KMS display via
# sway's auto-detected DRM backend. Requires:
#   - vc4-kms-v3d-pi5 dtoverlay enabled (so /dev/dri/card0 exists)
#   - seatd running and the invoking user in the `seat` group
#
# Usage (over SSH or on the device):
#   ~/projects/torchform-guishell/start-hdmi.sh
set -e

DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECTS_DIR="$(dirname "$DEMO_DIR")"
XDG_RUNTIME_DIR=/tmp/xdg-hdmi

# Sibling projects (Phase 1 input layer).
INPUTD_DIR="$PROJECTS_DIR/torchform-inputd"
INPUTD_BIN="$INPUTD_DIR/target/release/torchform-inputd"
GAMEPAD_PLUGIN_DIR="$PROJECTS_DIR/torchform-gamepad/build"
INPUT_CONFIG="$HOME/.config/torchform/input.toml"

# ── Sanity: DRM device present? ───────────────────────────────────────────────
if [ ! -e /dev/dri/card0 ] && [ ! -e /dev/dri/card1 ]; then
    echo "ERROR: no /dev/dri/card* — KMS not enabled."
    echo "       Add 'dtoverlay=vc4-kms-v3d-pi5' to /boot/usercfg.txt and reboot."
    exit 1
fi

# ── Clean up any stale session ───────────────────────────────────────────────
# NOTE: match by process NAME (no -f). Using `-f quickshell` would match this
# script's own command line and SIGKILL itself before doing anything.
if [ -f /tmp/torchform-virtual-gamepad.pid ]; then
    TEST_PAD_PID=$(cat /tmp/torchform-virtual-gamepad.pid 2>/dev/null || true)
    [ -z "$TEST_PAD_PID" ] || kill "$TEST_PAD_PID" 2>/dev/null || true
    rm -f /tmp/torchform-virtual-gamepad.pid
fi
pkill -9 -x quickshell 2>/dev/null || true
pkill -9 -x sway 2>/dev/null || true
pkill -9 -x torchform-input 2>/dev/null || true
sleep 1
rm -rf "$XDG_RUNTIME_DIR"

# ── Runtime dir (shared by the daemon + plugin via the action manifest) ───────
# torchform-inputd writes $XDG_RUNTIME_DIR/torchform/inputd-actions.json and the
# Torchform.Gamepad plugin reads it, so both must see the SAME XDG_RUNTIME_DIR.
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
export XDG_RUNTIME_DIR
mkdir -p "$XDG_RUNTIME_DIR/torchform"

VIRTUAL_GAMEPAD_SOCKET="$XDG_RUNTIME_DIR/torchform/virtual-gamepad.sock"
VIRTUAL_GAMEPAD_READY="$XDG_RUNTIME_DIR/torchform/virtual-gamepad.ready"
VIRTUAL_GAMEPAD_PID=""
INPUTD_PID=""

# ── Input backend FIRST ──────────────────────────────────────────────────────
# Production: torchform-inputd owns the physical controller(s) and emits the
# normalized "torchform-virtpad" uinput device.  Smoke mode: replace only that
# backend with the standard-library virtual gamepad driver.  The QuickShell
# Gamepad plugin therefore sees the same device name and event codes.
if [ "${TORCHFORM_VIRTUAL_GAMEPAD:-0}" = "1" ]; then
    echo ">> Starting virtual gamepad test backend..."
    setsid python3 "$DEMO_DIR/virtual-gamepad.py" --daemon \
        --socket "$VIRTUAL_GAMEPAD_SOCKET" \
        --ready "$VIRTUAL_GAMEPAD_READY" \
        --pid-file /tmp/torchform-virtual-gamepad.pid \
        </dev/null >/tmp/torchform-virtual-gamepad.log 2>&1 &
    VIRTUAL_GAMEPAD_PID=$!
    for i in $(seq 1 40); do
        [ -f "$VIRTUAL_GAMEPAD_READY" ] && break
        sleep 0.05
    done
    if [ ! -f "$VIRTUAL_GAMEPAD_READY" ]; then
        echo "ERROR: virtual gamepad did not become ready."
        cat /tmp/torchform-virtual-gamepad.log 2>/dev/null || true
        kill "$VIRTUAL_GAMEPAD_PID" 2>/dev/null || true
        exit 1
    fi
else
    # Install the default config on first run (chords/multiclick live here; the
    # daemon falls back to built-in defaults if it is missing entirely).
    if [ ! -f "$INPUT_CONFIG" ] && [ -f "$INPUTD_DIR/config/input.toml" ]; then
        mkdir -p "$(dirname "$INPUT_CONFIG")"
        cp "$INPUTD_DIR/config/input.toml" "$INPUT_CONFIG"
        echo ">> Installed default input config to $INPUT_CONFIG"
    fi
    if [ ! -x "$INPUTD_BIN" ] && [ -d "$INPUTD_DIR" ]; then
        echo ">> Building torchform-inputd (release)..."
        ( cd "$INPUTD_DIR" && cargo build --release ) \
            || echo "   WARNING: cargo build failed — controller will not work"
    fi
    if [ -x "$INPUTD_BIN" ]; then
        echo ">> Starting input daemon..."
        setsid "$INPUTD_BIN" </dev/null >/tmp/torchform-inputd.log 2>&1 &
        INPUTD_PID=$!
        sleep 1
    else
        echo "   WARNING: $INPUTD_BIN not found — no controller input"
    fi
fi

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

# ── Configure provisional display roles ───────────────────────────────────────
# The largest active output is upper; the smallest is lower.  This keeps the
# UI correct while the IO-board connector mapping and final panel modes move.
echo ">> Configuring display roles from live output geometry..."
if ! python3 "$DEMO_DIR/configure-outputs.py"; then
    echo "ERROR: display-role configuration failed."
    kill "$SWAY_PID" 2>/dev/null || true
    exit 1
fi
sleep 1

# ── Start QuickShell ─────────────────────────────────────────────────────────
echo ">> Starting QuickShell..."
cd "$DEMO_DIR"
mkdir -p "$HOME/.config/quickshell"
ln -sfn "$DEMO_DIR" "$HOME/.config/quickshell/default"

# QML_IMPORT_PATH lets `import Torchform.Gamepad` resolve the out-of-tree plugin.
WAYLAND_DISPLAY="$WAYLAND_DISPLAY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    QML_IMPORT_PATH="$GAMEPAD_PLUGIN_DIR${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
    quickshell >/tmp/quickshell-hdmi.log 2>&1 &
QS_PID=$!

echo ""
echo "Torchform QuickShell shell running on HDMI."
echo "  Controller: South=Confirm East=Back West=Palette North=Radial"
echo "              Start=Home Select=Switcher R1=QS L1=Notifs  D-pad=Nav"
echo "  Keyboard (dev): Space=Home A=Confirm Esc=Back X=Palette Z=QS C=Notifs"
echo "                  Tab=Radial Enter=Switcher Arrows=Nav"
echo "  Emergency exit: Mod4+Escape"
echo "  Logs: /tmp/quickshell-hdmi.log  /tmp/torchform-inputd.log  /tmp/sway-hdmi.log"
if [ "${TORCHFORM_VIRTUAL_GAMEPAD:-0}" = "1" ]; then
    echo "  Input: virtual gamepad test backend ($VIRTUAL_GAMEPAD_SOCKET)"
fi
echo "  Stop: kill $SWAY_PID"
echo ""

wait $SWAY_PID
echo "Sway exited. Cleaning up."
kill $QS_PID 2>/dev/null || true
kill "$INPUTD_PID" 2>/dev/null || true
kill "$VIRTUAL_GAMEPAD_PID" 2>/dev/null || true
rm -f /tmp/torchform-virtual-gamepad.pid
rm -rf "$XDG_RUNTIME_DIR"
