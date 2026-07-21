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

# ── 4a. Input stack — torchform-inputd (Rust) + Torchform.Gamepad plugin (C++)
#   Both read evdev with no extra dev lib: the Rust 'evdev' crate is pure-Rust and
#   the C++ plugin uses raw <linux/input.h> ioctls (kernel headers from
#   linux-headers, already installed in section 2). rust/cargo build the daemon;
#   the daemon emits a uinput virtual gamepad (needs /dev/uinput + the 'input'
#   group at RUNTIME, not build time).
apk add --no-cache \
    rust \
    cargo || true

# ── 4b. D-Bus, PipeWire & NetworkManager (for the service modules) ───────────
# Bluetooth/UPower/Mpris/Notifications/StatusNotifier need only Qt::DBus (already
# in qt6-qtbase-dev). PipeWire needs libpipewire-0.3; Network needs libnm — both
# require their -dev packages at *configure* time or CMake auto-disables them.
apk add --no-cache \
    dbus-dev \
    dbus-glib-dev \
    pipewire-dev \
    pipewire \
    networkmanager-dev    # provides libnm + pkgconfig for -DNETWORK=ON

# ── 5. Sway + wayvnc (for running & streaming) ───────────────────────────────
apk add --no-cache \
    sway \
    swaybg \
    wayvnc \
    wlr-randr \
    xkeyboard-config \
    dbus \
    dbus-x11

# ── 5b. Runtime services the shell drives (Phases 3-7) ───────────────────────
#   networkmanager  → Wi-Fi (manages wpa_supplicant as backend; Quickshell.Network)
#   bluez           → Bluetooth (org.bluez; Quickshell.Bluetooth)
#   upower          → battery % / charging state (Quickshell.Services.UPower)
#   brightnessctl   → backlight (via Quickshell.Io.Process; no native module)
#   flatpak         → app store + extra apps (via Process)
apk add --no-cache \
    networkmanager \
    bluez \
    upower \
    brightnessctl \
    flatpak || true

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
# NOTE: QuickShell's CMake options are UNPREFIXED (WAYLAND, SERVICE_*, BLUETOOTH,
# NETWORK, I3…). The old -DQS_* names were silently ignored, so every service
# module defaulted OFF — that is why Pipewire/UPower/Bluetooth/Network/etc. never
# built. A stale build/ cache keeps the old OFF values: delete it before reconfig:
#     rm -rf "$QUICKSHELL_DIR/build"
cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
    -DWAYLAND=ON \
    -DWAYLAND_WLR_LAYERSHELL=ON \
    -DSERVICE_PIPEWIRE=ON \
    -DSERVICE_UPOWER=ON \
    -DSERVICE_MPRIS=ON \
    -DSERVICE_NOTIFICATIONS=ON \
    -DSERVICE_STATUS_NOTIFIER=ON \
    -DBLUETOOTH=ON \
    -DNETWORK=ON \
    -DI3=ON \
    -DHYPRLAND=OFF \
    -DCRASH_HANDLER=OFF

cmake --build build --parallel "$(nproc)"
cmake --install build

echo ""
echo "✓ QuickShell installed at $INSTALL_PREFIX/bin/quickshell"
echo "  Run: cd /path/to/demo-quickshell && ./start.sh"
