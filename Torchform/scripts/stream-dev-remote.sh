#!/bin/sh
# stream-dev-remote.sh — Run on Minerva (Alpine/busybox ash).
# Starts a headless Weston compositor, launches Torchform, then streams both
# displays over TCP so the host emulator can display them.
#
# POSIX sh only — no bashisms; Alpine uses busybox ash.

set -e

# -----------------------------------------------------------------------------
# 1. Dependency check
# -----------------------------------------------------------------------------
_check() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "missing: $1 — run: apk add $2"
        exit 1
    }
}

_check weston       weston
_check wf-recorder  wf-recorder
_check nc           netcat-openbsd

# -----------------------------------------------------------------------------
# 2. Write Weston config
# -----------------------------------------------------------------------------
cat > /tmp/weston-stream-dev.ini << 'EOF'
[core]
backend=headless-backend.so

[output]
name=upper
width=1080
height=1920

[output]
name=lower
width=800
height=480
EOF

# -----------------------------------------------------------------------------
# 3. Launch Weston
# -----------------------------------------------------------------------------
weston --config=/tmp/weston-stream-dev.ini &
WESTON_PID=$!

# -----------------------------------------------------------------------------
# 4. Detect the Wayland socket Weston created (poll up to 5 s)
# -----------------------------------------------------------------------------
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
WAYLAND_SOCK=""
_elapsed=0
while [ $_elapsed -lt 5 ]; do
    for _f in "$RUNTIME_DIR"/wayland-*; do
        # Skip lock files
        case "$_f" in *.lock) continue ;; esac
        if [ -S "$_f" ]; then
            WAYLAND_SOCK="$_f"
            break
        fi
    done
    [ -n "$WAYLAND_SOCK" ] && break
    sleep 1
    _elapsed=$(( _elapsed + 1 ))
done

if [ -z "$WAYLAND_SOCK" ]; then
    echo "[stream-dev] ERROR: Weston socket not found after 5 s" >&2
    kill "$WESTON_PID" 2>/dev/null
    exit 1
fi

export WAYLAND_DISPLAY="${WAYLAND_SOCK##*/}"

# -----------------------------------------------------------------------------
# 5. Launch Torchform
# -----------------------------------------------------------------------------
"$HOME/torchform" &
TORCHFORM_PID=$!

sleep 1

# -----------------------------------------------------------------------------
# 6. Start capture + stream pipelines
# -----------------------------------------------------------------------------
wf-recorder --muxer=rawvideo --codec=h264 --output=upper -f - | nc -l -p 5910 &
UPPER_PID=$!

wf-recorder --muxer=rawvideo --codec=h264 --output=lower -f - | nc -l -p 5911 &
LOWER_PID=$!

# -----------------------------------------------------------------------------
# 7. Trap for clean shutdown
# -----------------------------------------------------------------------------
_cleanup() {
    kill "$UPPER_PID" "$LOWER_PID" "$TORCHFORM_PID" "$WESTON_PID" 2>/dev/null
    exit 0
}
trap '_cleanup' INT TERM EXIT

# -----------------------------------------------------------------------------
# 8. Ready
# -----------------------------------------------------------------------------
echo "[stream-dev] ready"

# Keep the script alive so the trap fires on signal
wait
