#!/bin/sh
# stream-dev-local.sh — Run on the host (Linux/macOS).
# Builds and rsyncs the Torchform binary to Minerva, opens SSH tunnels for
# both display streams, starts the remote capture script, then launches the
# local minerva-emulator in stream-mode.
#
# Environment:
#   MINERVA_HOST   SSH host alias for the device (default: minerva)
#   SKIP_BUILD=1   Skip cross-compilation and rsync steps

set -e

# -----------------------------------------------------------------------------
# 1. Dependency check
# -----------------------------------------------------------------------------
_check() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "missing: $1 — install hint: $2"
        exit 1
    }
}

_check cross  "cargo install cross"
_check rsync  "install rsync via your package manager"
_check ffmpeg "install ffmpeg via your package manager"
_check ssh    "install openssh-client via your package manager"

MINERVA_HOST="${MINERVA_HOST:-minerva}"

# -----------------------------------------------------------------------------
# 2. Build (unless SKIP_BUILD=1)
# -----------------------------------------------------------------------------
if [ "${SKIP_BUILD:-0}" != "1" ]; then
    cross build --target aarch64-unknown-linux-musl --release -p torchform-shell

    rsync -avz \
        target/aarch64-unknown-linux-musl/release/torchform-shell \
        "${MINERVA_HOST}:~/torchform"
fi

# -----------------------------------------------------------------------------
# 3. Copy remote helper script to device
# -----------------------------------------------------------------------------
rsync -avz \
    scripts/stream-dev-remote.sh \
    "${MINERVA_HOST}:~/stream-dev-remote.sh"

# -----------------------------------------------------------------------------
# 4. Open SSH tunnel + run remote script in background
# -----------------------------------------------------------------------------
ssh \
    -L 5910:localhost:5910 \
    -L 5911:localhost:5911 \
    "${MINERVA_HOST}" \
    "sh ~/stream-dev-remote.sh" &
SSH_PID=$!

# Give the remote side a moment to start Weston and the capture pipelines.
sleep 3

# -----------------------------------------------------------------------------
# 5. Trap for clean shutdown
# -----------------------------------------------------------------------------
_cleanup() {
    kill "$SSH_PID" 2>/dev/null
    exit 0
}
trap '_cleanup' INT TERM EXIT

# -----------------------------------------------------------------------------
# 6. Launch the local emulator in stream-mode
# -----------------------------------------------------------------------------
cargo run -p minerva-emulator -- --stream-mode --upper-port 5910 --lower-port 5911
