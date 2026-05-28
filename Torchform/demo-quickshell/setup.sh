#!/bin/sh
# setup.sh — Install deps and build QuickShell from source on Alpine aarch64 (RPi)
# Run with doas/sudo for the apk steps; clone/build happen as the CALLING user.
set -e

# Clone into the invoking user's home, not root's, even when run via doas/sudo.
REAL_HOME="$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)"
QUICKSHELL_DIR="${REAL_HOME}/projects/quickshell-src"
INSTALL_PREFIX="/usr/local"

# ── 1. Enable edge/community repos if needed ─────────────────────────────────
if ! grep -q "edge" /etc/apk/repositories 2>/dev/null; then
    echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories
    echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing"   >> /etc/apk/repositories
fi
apk update

# ── 2. Core build tools ──────────────────────────────────────────────────────
apk add --no-cache \
    git cmake ninja samurai \
    gcc g++ musl-dev pkgconf \
    linux-headers \
    cli11-dev

# ── 3. Qt6 ───────────────────────────────────────────────────────────────────
apk add --no-cache \
    qt6-qtbase-dev \
    qt6-qtdeclarative-dev \
    qt6-qtdeclarative-private-dev \
    qt6-qtwayland-dev \
    qt6-qtsvg-dev \
    qt6-qtshadertools-dev \
    qt6-qttools-dev

# ── 4. Wayland & graphics ────────────────────────────────────────────────────
apk add --no-cache \
    wayland-dev \
    wayland-protocols \
    libxkbcommon-dev \
    mesa-dev \
    libdrm-dev \
    eudev-dev

# ── 4b. D-Bus & PipeWire (for QS_DBUS / QS_PIPEWIRE modules) ─────────────────
apk add --no-cache \
    dbus-dev \
    dbus-glib-dev \
    pipewire-dev \
    pipewire \
    wvkbd || true  # on-screen keyboard; tolerate absence

# ── 5. Sway + wayvnc (for running & streaming) ───────────────────────────────
apk add --no-cache \
    sway \
    swaybg \
    wayvnc \
    wlr-randr \
    xkeyboard-config \
    dbus \
    dbus-x11

# ── 6. Fonts ─────────────────────────────────────────────────────────────────
apk add --no-cache \
    font-inter \
    font-jetbrains-mono-nerd \
    font-noto-emoji \
    ttf-dejavu || true
# Barlow Condensed: not in repos, fetch from Google Fonts manually if needed
# curl -Lo /tmp/BarlowCondensed.zip "https://fonts.google.com/download?family=Barlow+Condensed"
# (or just let Inter be the fallback — Tokens.qml already has it as fallback)

# ── 7. Build QuickShell from source ──────────────────────────────────────────
if [ ! -d "$QUICKSHELL_DIR" ]; then
    git clone --recursive https://github.com/quickshell-mirror/quickshell "$QUICKSHELL_DIR"
else
    echo "QuickShell source already present — pulling latest..."
    git -C "$QUICKSHELL_DIR" pull --recurse-submodules
fi

cd "$QUICKSHELL_DIR"
cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
    -DQS_WAYLAND=ON \
    -DQS_WAYLAND_WLR_LAYERSHELL=ON \
    -DQS_DBUS=ON \
    -DQS_PIPEWIRE=ON \
    -DQS_SERVICE_STATUS_NOTIFIER=ON \
    -DQS_HYPRLAND=OFF \
    -DQS_I3=OFF \
    -DCRASH_HANDLER=OFF

cmake --build build --parallel "$(nproc)"
cmake --install build

echo ""
echo "✓ QuickShell installed at $INSTALL_PREFIX/bin/quickshell"
echo "  Run: cd /path/to/demo-quickshell && ./start.sh"
