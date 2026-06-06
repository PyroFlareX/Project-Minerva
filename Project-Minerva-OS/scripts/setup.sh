#!/usr/bin/env bash
# =============================================================================
# MinervaOS dev environment setup
# Run once automatically by devcontainer postCreateCommand.
# Safe to re-run manually at any time.
# =============================================================================
set -euo pipefail

WORKSPACE="/workspace"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║     MinervaOS Dev Environment Setup      ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# --- Fix cargo volume ownership ---
# Docker-managed volumes are created as root; ensure dev user can write.
echo "▸ Fixing cargo volume ownership..."
sudo chown -R dev:dev /usr/local/cargo /usr/local/rustup 2>/dev/null || true
echo "  ✓ /usr/local/cargo and /usr/local/rustup owned by dev"

# --- Verify musl cross toolchain ---
echo "▸ Checking musl cross-compilation toolchain..."
if ! command -v aarch64-linux-musl-gcc &>/dev/null; then
    echo "  ERROR: aarch64-linux-musl-gcc not found. Rebuild the devcontainer."
    exit 1
fi
echo "  ✓ aarch64-linux-musl-gcc: $(aarch64-linux-musl-gcc --version | head -1)"

# --- Verify Rust + musl target ---
echo "▸ Checking Rust toolchain..."
if ! command -v cargo &>/dev/null; then
    echo "  ERROR: cargo not found."
    exit 1
fi
echo "  ✓ cargo: $(cargo --version)"
echo "  ✓ rustc: $(rustc --version)"

if ! rustup target list --installed | grep -q "aarch64-unknown-linux-musl"; then
    echo "  Adding aarch64-unknown-linux-musl target..."
    rustup target add aarch64-unknown-linux-musl
fi
echo "  ✓ target: aarch64-unknown-linux-musl"

# --- Verify QEMU ---
echo "▸ Checking QEMU..."
if ! command -v qemu-system-aarch64 &>/dev/null; then
    echo "  ERROR: qemu-system-aarch64 not found."
    exit 1
fi
echo "  ✓ qemu-system-aarch64: $(qemu-system-aarch64 --version | head -1)"

# --- Verify alpine-make-rootfs is available ---
echo "▸ Checking alpine-make-rootfs..."
if ! command -v alpine-make-rootfs &>/dev/null; then
    echo "  WARNING: alpine-make-rootfs not found. 'make image' will not work."
    echo "  It will be installed during image build if needed."
else
    echo "  ✓ alpine-make-rootfs: $(alpine-make-rootfs --version 2>&1 | head -1)"
fi

# --- Generate .env if it doesn't exist ---
echo "▸ Checking .env..."
if [ ! -f "$WORKSPACE/.env" ]; then
    cat > "$WORKSPACE/.env" << 'EOF'
# Local overrides — gitignored, edit freely
# CM5_IP=192.168.1.100
# IMAGE=minervaos.img
# QEMU_MEM=8G
# QEMU_SMP=4
EOF
    echo "  ✓ Created .env"
else
    echo "  ✓ .env already exists"
fi

# --- Initial cargo fetch (warms cache) ---
echo "▸ Fetching Cargo dependencies..."
cd "$WORKSPACE"
cargo fetch --target aarch64-unknown-linux-musl 2>/dev/null || true

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║              Setup complete!             ║"
echo "║                                          ║"
echo "║  make build   → cross-compile (musl)     ║"
echo "║  make image   → build disk image + boot ║"
echo "║  make run     → launch QEMU VM           ║"
echo "║  make deploy  → push to CM5              ║"
echo "╚══════════════════════════════════════════╝"
echo ""
