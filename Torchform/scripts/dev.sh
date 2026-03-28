#!/usr/bin/env bash
# =============================================================================
# dev.sh — Quick-start script for Torchform development
#
# Detects whether cargo is available natively or falls back to Docker.
# Usage:
#   ./scripts/dev.sh shell         Run the shell UI (command palette default)
#   ./scripts/dev.sh shell radial  Run with radial menu open
#   ./scripts/dev.sh shell idle    Run with lower screen idle view
#   ./scripts/dev.sh compositor   Run the compositor (nested Winit window)
#   ./scripts/dev.sh check         cargo check all crates
#   ./scripts/dev.sh docker        Enter the Docker dev container
# =============================================================================

set -euo pipefail
cd "$(dirname "$0")/.."

DEMO="${2:-palette}"
TARGET="${1:-shell}"

# ---------------------------------------------------------------------------
# Detect cargo
# ---------------------------------------------------------------------------
if command -v cargo &>/dev/null; then
    RUN="cargo"
    echo "[dev.sh] Using native cargo: $(cargo --version)"
else
    echo "[dev.sh] cargo not found — using Docker"

    DOCKER_IMAGE="torchform-dev"

    if ! docker image inspect "$DOCKER_IMAGE" &>/dev/null; then
        echo "[dev.sh] Building Docker image..."
        docker build -t "$DOCKER_IMAGE" .devcontainer/
    fi

    # Allow X connections from Docker
    xhost +local:docker &>/dev/null || true

    WAYLAND_VOL=""
    if [[ -n "${WAYLAND_DISPLAY:-}" && -n "${XDG_RUNTIME_DIR:-}" ]]; then
        WAYLAND_VOL="-v ${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}:/tmp/runtime-dev/${WAYLAND_DISPLAY}:rw"
        WAYLAND_ENV="-e WAYLAND_DISPLAY=${WAYLAND_DISPLAY} -e XDG_RUNTIME_DIR=/tmp/runtime-dev"
    else
        WAYLAND_VOL=""
        WAYLAND_ENV=""
    fi

    RUN="docker run --rm --network=host \
        -e DISPLAY=${DISPLAY:-:0} $WAYLAND_ENV \
        -v /tmp/.X11-unix:/tmp/.X11-unix:rw $WAYLAND_VOL \
        -v $(pwd):/workspace:cached \
        -v torchform-cargo-registry:/usr/local/cargo/registry \
        -v torchform-cargo-git:/usr/local/cargo/git \
        -w /workspace $DOCKER_IMAGE cargo"
fi

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "$TARGET" in
    shell)
        echo "[dev.sh] Running shell UI (demo=$DEMO)"
        RUST_LOG=torchform_shell=debug $RUN run -p torchform-shell -- --demo "$DEMO"
        ;;
    compositor)
        echo "[dev.sh] Running compositor (Winit backend)"
        TORCHFORM_BACKEND=winit RUST_LOG=debug $RUN run -p torchform-compositor
        ;;
    check)
        echo "[dev.sh] Checking workspace"
        $RUN check --workspace
        ;;
    build)
        echo "[dev.sh] Building workspace"
        $RUN build --workspace
        ;;
    docker)
        echo "[dev.sh] Entering Docker container"
        docker run --rm -it --network=host \
            -e DISPLAY="${DISPLAY:-:0}" \
            -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
            -v "$(pwd)":/workspace:cached \
            -v torchform-cargo-registry:/usr/local/cargo/registry \
            -v torchform-cargo-git:/usr/local/cargo/git \
            -w /workspace \
            torchform-dev bash
        ;;
    *)
        echo "Usage: $0 [shell|compositor|check|build|docker] [demo-mode]"
        echo "  shell modes: palette (default), radial, switcher, idle"
        exit 1
        ;;
esac
