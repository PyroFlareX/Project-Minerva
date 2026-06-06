#!/usr/bin/env bash
# =============================================================================
# MinervaOS QEMU ARM64 launcher
# Usage: bash qemu/launch.sh [--kvm]
#
# Uses direct kernel boot (no bootloader) for QEMU testing.
# Kernel and initramfs are produced by os/build.sh → qemu/boot/.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vars.sh"

USE_KVM=0
HEADLESS=0
VNC=0
for arg in "$@"; do
    [[ "$arg" == "--kvm" ]]      && USE_KVM=1
    [[ "$arg" == "--headless" ]] && HEADLESS=1
    [[ "$arg" == "--vnc" ]]      && VNC=1
done

KERNEL_SRC="$SCRIPT_DIR/boot/vmlinuz"
INITRD_SRC="$SCRIPT_DIR/boot/initramfs"
# Resolve IMAGE to absolute path so QEMU doesn't depend on cwd
IMAGE="$(cd "$(dirname "$IMAGE")" 2>/dev/null && pwd)/$(basename "$IMAGE")" \
    || IMAGE="$(pwd)/$IMAGE"

# --- Validate prerequisites ---
if [ ! -f "$IMAGE" ]; then
    echo "ERROR: Disk image not found: $IMAGE"
    echo "Run 'make image' first."
    exit 1
fi
if [ ! -f "$KERNEL_SRC" ]; then
    echo "ERROR: Kernel not found: $KERNEL_SRC"
    echo "Run 'make image' first."
    exit 1
fi
if [ ! -f "$INITRD_SRC" ]; then
    echo "ERROR: Initramfs not found: $INITRD_SRC"
    echo "Run 'make image' first."
    exit 1
fi

# Stage kernel + initramfs to /tmp (tmpfs) before passing to QEMU.
# Docker Desktop Windows bind mounts don't support mmap, which QEMU
# uses when loading boot files from /workspace.
KERNEL=$(mktemp /tmp/minervaos-vmlinuz.XXXXXX)
INITRD=$(mktemp /tmp/minervaos-initramfs.XXXXXX)
trap 'rm -f "$KERNEL" "$INITRD"' EXIT
cp "$KERNEL_SRC" "$KERNEL"
cp "$INITRD_SRC" "$INITRD"

QEMU_ARGS=(
    -machine virt
    -cpu cortex-a76          # Matches CM5 CPU
    -m "$QEMU_MEM"
    -smp "$QEMU_SMP"

    # Direct kernel boot — no bootloader required for QEMU testing
    -kernel "$KERNEL"
    -initrd "$INITRD"
    -append "root=/dev/vda rootfstype=ext4 rw console=ttyAMA0 loglevel=4"

    # Root filesystem
    -drive "file=$IMAGE,format=raw,if=virtio,cache=writeback"

    # Network — SSH forwarded to localhost:2222
    -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22"
    -device virtio-net-pci,netdev=net0
)

# Display / console
if [ "$HEADLESS" -eq 1 ]; then
    # No GPU device — serial console only. Use for boot/shell testing.
    QEMU_ARGS+=( -nographic )
elif [ "$VNC" -eq 1 ]; then
    # ramfb: simple QEMU built-in framebuffer, always available.
    # Guest sees /dev/fb0; compositor can write pixels directly.
    # Connect from host: vncviewer localhost:5900
    QEMU_ARGS+=(
        -device ramfb
        -display vnc=0.0.0.0:0
        -device virtio-keyboard-pci
        -device virtio-mouse-pci
        -serial stdio
        -monitor none
    )
else
    # virtio-gpu-gl (virgl/OpenGL) + SDL. Requires host OpenGL support.
    QEMU_ARGS+=(
        -device virtio-gpu-gl
        -display sdl,gl=on
        -device virtio-keyboard-pci
        -device virtio-mouse-pci
        -serial stdio
        -monitor none
    )
fi

if [ "$USE_KVM" -eq 1 ]; then
    if [ ! -e /dev/kvm ]; then
        echo "WARNING: /dev/kvm not available. Falling back to software emulation."
    else
        QEMU_ARGS+=(-enable-kvm)
        echo "▸ KVM acceleration enabled"
    fi
fi

echo "▸ Launching MinervaOS in QEMU ARM64"
echo "  Image:    $IMAGE"
echo "  CPU:      cortex-a76 × $QEMU_SMP"
echo "  RAM:      $QEMU_MEM"
echo "  SSH:      ssh -p $SSH_PORT user@localhost"
if [ "$HEADLESS" -eq 1 ]; then
echo "  Display:  headless (no GPU) — serial console on this terminal"
echo "  Quit:     Ctrl+A then X"
elif [ "$VNC" -eq 1 ]; then
echo "  Display:  VNC → connect to localhost:5900 from your host"
echo "  Quit:     Ctrl+A then X (serial) or close VNC"
else
echo "  Display:  SDL (virtio-gpu-gl)"
echo "  Quit:     close SDL window"
fi
echo ""

exec qemu-system-aarch64 "${QEMU_ARGS[@]}"
