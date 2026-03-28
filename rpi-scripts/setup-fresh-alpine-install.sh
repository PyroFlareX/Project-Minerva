#!/bin/sh
# =============================================================================
# MinervaOS — CM5 Developer Bootstrap
# Run this once on a fresh Alpine Linux install on the Raspberry Pi CM5.
# Sets up all dependencies needed to run MinervaOS DE binaries.
#
# Usage:
#   wget https://raw.githubusercontent.com/YOUR_REPO/main/scripts/bootstrap-cm5.sh
#   sh bootstrap-cm5.sh
#
# Or copy to the CM5 and run:
#   scp scripts/bootstrap-cm5.sh user@<cm5-ip>:~
#   ssh user@<cm5-ip> "sh bootstrap-cm5.sh"
# =============================================================================

set -e

# Must be root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Run as root (sudo sh bootstrap-cm5.sh)"
    exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║     MinervaOS CM5 Developer Bootstrap        ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# =============================================================================
# 1. System update
# =============================================================================
echo "▸ Updating Alpine package index..."
apk update
apk upgrade

# =============================================================================
# 2. Enable community + edge repos if not already enabled
# =============================================================================
echo "▸ Enabling Alpine community repository..."
REPOS_FILE="/etc/apk/repositories"

# Get the mirror base from the first enabled repo line
MIRROR=$(grep -m1 "^http" "$REPOS_FILE" | sed 's|/[^/]*$||')

# Add community if not present
if ! grep -q "/community" "$REPOS_FILE"; then
    echo "${MIRROR}/community" >> "$REPOS_FILE"
    echo "  Added: ${MIRROR}/community"
fi

apk update

# =============================================================================
# 3. Core system utilities
# =============================================================================
echo "▸ Installing core utilities..."
apk add \
    alpine-sdk \
    bash \
    curl \
    wget \
    git \
    rsync \
    openssh \
    sudo \
    shadow \
    util-linux \
    eudev \
    udev-init-scripts \
    dbus \
    dbus-openrc

# =============================================================================
# 4. Wayland / compositor dependencies
# =============================================================================
echo "▸ Installing Wayland and compositor dependencies..."
apk add \
    wayland \
    wayland-dev \
    wayland-protocols \
    libdrm \
    libdrm-dev \
    libinput \
    libinput-dev \
    libxkbcommon \
    libxkbcommon-dev \
    pixman \
    pixman-dev \
    eudev-dev \
    libseat \
    libseat-dev

# =============================================================================
# 5. Mesa / GPU (VideoCore VII on CM5 uses V3D driver)
# =============================================================================
echo "▸ Installing Mesa graphics stack..."
apk add \
    mesa \
    mesa-dri-gallium \
    mesa-gl \
    mesa-egl \
    mesa-dev \
    mesa-gbm \
    xf86-video-fbdev

# =============================================================================
# 6. Slint / UI toolkit dependencies
# =============================================================================
echo "▸ Installing Slint backend dependencies..."
apk add \
    fontconfig \
    fontconfig-dev \
    freetype \
    freetype-dev \
    ttf-dejavu \
    font-noto \
    sdl2 \
    sdl2-dev

# =============================================================================
# 7. Audio (PipeWire)
# =============================================================================
echo "▸ Installing audio stack (PipeWire)..."
apk add \
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    wireplumber \
    alsa-utils \
    alsa-lib \
    alsa-lib-dev

# =============================================================================
# 8. Input / gamepad testing tools
# =============================================================================
echo "▸ Installing input tools..."
apk add \
    evtest \
    libevdev \
    libevdev-dev \
    linux-firmware \
    linux-firmware-other

# =============================================================================
# 9. Networking (ModemManager for LTE, iwd for WiFi)
# =============================================================================
echo "▸ Installing networking stack..."
apk add \
    networkmanager \
    networkmanager-openrc \
    modemmanager \
    modemmanager-openrc \
    iwd \
    iwd-openrc \
    wpa_supplicant

# =============================================================================
# 10. ZFS (OpenZFS on Alpine)
# =============================================================================
echo "▸ Installing ZFS..."

# ZFS needs the running kernel version
KERNEL_VER=$(uname -r)
echo "  Kernel: $KERNEL_VER"

apk add \
    zfs \
    zfs-openrc \
    zfs-udev

# Load ZFS kernel module
modprobe zfs 2>/dev/null && echo "  ✓ ZFS module loaded" \
    || echo "  WARNING: ZFS module failed to load — may need reboot"

# Enable ZFS at boot
rc-update add zfs-import boot 2>/dev/null || true
rc-update add zfs-mount boot 2>/dev/null || true

# =============================================================================
# 11. Security tools
# =============================================================================
echo "▸ Installing security tools..."
apk add \
    cryptsetup \
    cryptsetup-openrc \
    lvm2 \
    e2fsprogs \
    dosfstools

# =============================================================================
# 12. Development / debugging tools (helpful on device)
# =============================================================================
echo "▸ Installing dev/debug tools..."
apk add \
    strace \
    htop \
    lsof \
    file \
    tree \
    tmux \
    nano \
    less \
    jq

# =============================================================================
# 13. MinervaOS runtime directories
# =============================================================================
echo "▸ Creating MinervaOS runtime directories..."
mkdir -p /run/minerva
mkdir -p /data/workspaces
mkdir -p /data/projects
mkdir -p /usr/local/bin
mkdir -p /etc/minerva

# /data will eventually live on ZFS/NVMe but for dev it lives on rootfs
# Set ownership to the main user (created below if needed)
chown -R user:user /data 2>/dev/null || true

# =============================================================================
# 14. Create 'user' account if it doesn't exist
# =============================================================================
echo "▸ Checking user account..."
if ! id user >/dev/null 2>&1; then
    echo "  Creating user 'user'..."
    adduser -D -s /bin/bash user
    echo "user:minerva" | chpasswd
    echo "  Password set to: minerva — CHANGE THIS"
fi

# Add user to relevant groups
for grp in wheel video input audio plugdev dialout; do
    addgroup user $grp 2>/dev/null || true
done

# sudoers
if ! grep -q "^%wheel" /etc/sudoers; then
    echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
fi

# =============================================================================
# 15. OpenRC services
# =============================================================================
echo "▸ Enabling services..."
rc-update add dbus default
rc-update add udev sysinit
rc-update add udev-trigger sysinit
rc-update add udev-settle sysinit
rc-update add networkmanager default
rc-update add sshd default

# =============================================================================
# 16. Raspberry Pi CM5 specific — ensure VC4/V3D DRM is loaded
# =============================================================================
echo "▸ Configuring CM5 display (V3D / DRM)..."

# Add kernel modules to load at boot
MODULES_FILE="/etc/modules"
for mod in v3d vc4 drm drm_kms_helper; do
    if ! grep -q "^$mod" "$MODULES_FILE" 2>/dev/null; then
        echo "$mod" >> "$MODULES_FILE"
    fi
done

# config.txt — enable DRM/KMS for the upper DSI display
CONFIG_TXT="/boot/config.txt"
if [ -f "$CONFIG_TXT" ]; then
    # Disable legacy framebuffer, enable DRM
    grep -q "^dtoverlay=vc4-kms-v3d" "$CONFIG_TXT" \
        || echo "dtoverlay=vc4-kms-v3d" >> "$CONFIG_TXT"
    grep -q "^gpu_mem=" "$CONFIG_TXT" \
        || echo "gpu_mem=128" >> "$CONFIG_TXT"
    echo "  ✓ config.txt updated"
else
    echo "  WARNING: /boot/config.txt not found — set dtoverlay=vc4-kms-v3d manually"
fi

# =============================================================================
# 17. SSH hardening (basic)
# =============================================================================
echo "▸ Configuring SSH..."
SSHD_CONFIG="/etc/ssh/sshd_config"
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' "$SSHD_CONFIG"
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' "$SSHD_CONFIG"

# =============================================================================
# Done
# =============================================================================
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║            Bootstrap complete!               ║"
echo "║                                              ║"
echo "║  Next steps:                                 ║"
echo "║  1. Reboot to load kernel modules            ║"
echo "║  2. Set CM5_IP in your devcontainer .env     ║"
echo "║  3. Run 'make deploy-bins' from VS Code      ║"
echo "║  4. SSH in and run minerva-compositor        ║"
echo "║                                              ║"
echo "║  SSH:  ssh user@<this-ip>                    ║"
echo "║  Pass: minerva  ← CHANGE THIS                ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# Print the device IP for convenience
echo "  Device IP addresses:"
ip -4 addr show | grep "inet " | grep -v "127.0.0.1" \
    | awk '{print "    " $2}' || true
echo ""