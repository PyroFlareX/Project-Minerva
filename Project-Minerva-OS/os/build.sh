#!/usr/bin/env bash
# =============================================================================
# MinervaOS — Alpine aarch64 disk image builder
# Usage: sudo bash os/build.sh [output-image] [image-size]
#
# Produces:
#   <image>             — raw disk image with a single ext4 root partition
#   qemu/boot/vmlinuz   — aarch64 kernel (for QEMU direct-boot)
#   qemu/boot/initramfs — initramfs (for QEMU direct-boot)
#
# Requires: alpine-make-rootfs, e2fsprogs, rsync, openssl
# =============================================================================
set -euo pipefail

IMAGE="${1:-minervaos.img}"
IMAGE_SIZE="${2:-4G}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/.." && pwd)"
BOOT_OUT="$WORKSPACE/qemu/boot"

ALPINE_ARCH="aarch64"
ALPINE_BRANCH="v3.21"

# Temporary dirs — cleaned up on exit
ROOTFS_BUILD=""   # where alpine-make-rootfs writes
ROOTFS_MOUNT=""   # where the disk partition is mounted
LOOP=""

cleanup() {
    echo "▸ Cleaning up..."
    [ -n "$ROOTFS_MOUNT" ] && umount -lf "$ROOTFS_MOUNT" 2>/dev/null || true
    [ -n "$LOOP" ]         && losetup -d "$LOOP"         2>/dev/null || true
    [ -n "$ROOTFS_BUILD" ] && rm -rf "$ROOTFS_BUILD"
    [ -n "$ROOTFS_MOUNT" ] && rm -rf "$ROOTFS_MOUNT"
}
trap cleanup EXIT

require_root() {
    [ "$EUID" -eq 0 ] || { echo "ERROR: Run as root (sudo)."; exit 1; }
}
require_root

require_cmd() {
    command -v "$1" >/dev/null \
        || { echo "ERROR: '$1' not found. Rebuild the devcontainer."; exit 1; }
}
require_cmd alpine-make-rootfs
require_cmd mkfs.ext4
require_cmd openssl
require_cmd rsync

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║       MinervaOS Image Builder            ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Image:   $IMAGE ($IMAGE_SIZE)"
echo "  Arch:    $ALPINE_ARCH   Alpine: $ALPINE_BRANCH"
echo ""

# =============================================================================
# 1. Disk image — raw ext4, no partition table
#    losetup --partscan partition nodes are unreliable inside containers.
#    A raw ext4 image is simpler: QEMU boots it directly via -kernel/-initrd
#    and root=LABEL=minervaos-root resolves to the whole virtio block device.
# =============================================================================
echo "▸ Creating disk image..."
truncate -s "$IMAGE_SIZE" "$IMAGE"
mkfs.ext4 -F -L minervaos-root "$IMAGE"

LOOP=$(losetup --find --show "$IMAGE")
echo "  Loop device: $LOOP"

ROOTFS_MOUNT=$(mktemp -d /tmp/minervaos-mount.XXXXXX)
mount "$LOOP" "$ROOTFS_MOUNT"

# =============================================================================
# 2. Alpine rootfs via alpine-make-rootfs
#    Writes to a temp dir first to avoid issues with the mounted fs.
#    APK installs packages for the target arch without running any aarch64
#    binaries, so no binfmt/qemu-user-static is needed here.
# =============================================================================
echo "▸ Building Alpine $ALPINE_BRANCH $ALPINE_ARCH rootfs..."
echo "  (fetches packages from Alpine CDN — may take a few minutes)"

ROOTFS_BUILD=$(mktemp -d /tmp/minervaos-build.XXXXXX)

APK_OPTS="--no-progress --arch $ALPINE_ARCH --allow-untrusted" \
alpine-make-rootfs \
    --branch  "$ALPINE_BRANCH" \
    --packages "alpine-base linux-virt openssh util-linux e2fsprogs" \
    "$ROOTFS_BUILD"

echo "▸ Copying rootfs to disk partition..."
rsync -a "$ROOTFS_BUILD/" "$ROOTFS_MOUNT/"

# =============================================================================
# 3. Configure rootfs (file-based — no chroot needed)
# =============================================================================
echo "▸ Configuring rootfs..."
R="$ROOTFS_MOUNT"

# --- Hostname ---
echo "minervaos" > "$R/etc/hostname"

cat > "$R/etc/hosts" << 'EOF'
127.0.0.1   localhost
127.0.1.1   minervaos
::1         localhost
EOF

# --- fstab (raw image: root is the whole virtio block device /dev/vda) ---
cat > "$R/etc/fstab" << 'EOF'
LABEL=minervaos-root  /  ext4  defaults,noatime  0 0
EOF

# --- Network: DHCP on eth0 (virtio-net in QEMU appears as eth0) ---
mkdir -p "$R/etc/network"
cat > "$R/etc/network/interfaces" << 'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

# --- User accounts ---
# Write entries directly rather than running adduser in chroot.
USER_HASH=$(openssl passwd -6 "minerva")
ROOT_HASH=$(openssl passwd -6 "minerva")

grep -q "^user:" "$R/etc/passwd" 2>/dev/null \
    || echo "user:x:1000:1000::/home/user:/bin/sh" >> "$R/etc/passwd"
grep -q "^user:" "$R/etc/shadow" 2>/dev/null \
    || echo "user:${USER_HASH}:19000:0:99999:7:::" >> "$R/etc/shadow"
grep -q "^user:" "$R/etc/group"  2>/dev/null \
    || echo "user:x:1000:" >> "$R/etc/group"

# Root password
sed -i "s|^root:[^:]*:|root:${ROOT_HASH}:|" "$R/etc/shadow"

# wheel group for sudo
if grep -q "^wheel:" "$R/etc/group" 2>/dev/null; then
    # Append user to existing wheel group (handles trailing colon or existing members)
    sed -i 's/^wheel:\([^:]*\):\([^:]*\):\(.*\)$/wheel:\1:\2:\3,user/' "$R/etc/group"
    sed -i 's/^wheel:\([^:]*\):\([^:]*\):,$/wheel:\1:\2:user/' "$R/etc/group"
else
    echo "wheel:x:10:user" >> "$R/etc/group"
fi

mkdir -p "$R/home/user"
chmod 700 "$R/home/user"

# sudoers
mkdir -p "$R/etc/sudoers.d"
echo "%wheel ALL=(ALL) NOPASSWD:ALL" > "$R/etc/sudoers.d/wheel"
chmod 440 "$R/etc/sudoers.d/wheel"

# --- Kernel modules to auto-load ---
# virtio_gpu: exposes /dev/dri/card0 for compositor DRM access in QEMU
cat >> "$R/etc/modules" << 'EOF'
drm
virtio_gpu
EOF

# --- SSH ---
sed -i \
    -e 's/#PasswordAuthentication yes/PasswordAuthentication yes/' \
    -e 's/PasswordAuthentication no/PasswordAuthentication yes/' \
    -e 's/#PermitRootLogin.*/PermitRootLogin yes/' \
    "$R/etc/ssh/sshd_config" 2>/dev/null || true

# --- OpenRC services ---
# alpine-base includes the default sysinit/boot runlevel symlinks.
# We only add the services we specifically need on top.
mkdir -p \
    "$R/etc/runlevels/sysinit" \
    "$R/etc/runlevels/boot" \
    "$R/etc/runlevels/default" \
    "$R/etc/runlevels/shutdown"

_svc() { ln -sf "/etc/init.d/$2" "$R/etc/runlevels/$1/$2" 2>/dev/null || true; }

# boot
_svc boot hwclock
_svc boot modules
_svc boot sysctl
_svc boot hostname
_svc boot bootmisc
_svc boot syslog
_svc boot networking

# default
_svc default sshd
_svc default local

# shutdown
_svc shutdown mount-ro
_svc shutdown killprocs
_svc shutdown savecache

echo "  ✓ Rootfs configured"

# =============================================================================
# 4. Extract kernel + initramfs from rootfs for QEMU direct-boot
#    mkinitfs runs via binfmt during APK install (Docker Desktop provides
#    QEMU aarch64 binfmt support), so the generated initramfs is available.
# =============================================================================
echo "▸ Extracting kernel and initramfs from rootfs..."
mkdir -p "$BOOT_OUT"

KVER=$(ls "$ROOTFS_BUILD/boot/" 2>/dev/null | grep "^vmlinuz-" | sed 's/vmlinuz-//' | head -1)
if [ -z "$KVER" ]; then
    echo "  ERROR: No kernel found in rootfs /boot. Package install failed."
    exit 1
fi
if [ ! -f "$ROOTFS_BUILD/boot/initramfs-${KVER}" ]; then
    echo "  ERROR: initramfs-${KVER} not found. mkinitfs may have failed."
    echo "  Check that binfmt_misc aarch64 support is active in Docker."
    exit 1
fi

cp "$ROOTFS_BUILD/boot/vmlinuz-${KVER}"   "$BOOT_OUT/vmlinuz"
cp "$ROOTFS_BUILD/boot/initramfs-${KVER}" "$BOOT_OUT/initramfs"
chmod 644 "$BOOT_OUT/vmlinuz" "$BOOT_OUT/initramfs"
echo "  ✓ vmlinuz    → qemu/boot/vmlinuz  (${KVER})"
echo "  ✓ initramfs  → qemu/boot/initramfs"

# =============================================================================
# 5. Install MinervaOS binaries
# =============================================================================
echo "▸ Installing MinervaOS binaries..."
mkdir -p "$R/usr/local/bin"

for bin in minerva-compositor minerva-shell minerva-workspaced minerva-inputd; do
    BIN_PATH="$WORKSPACE/target/aarch64-unknown-linux-musl/release/$bin"
    if [ -f "$BIN_PATH" ]; then
        install -m755 "$BIN_PATH" "$R/usr/local/bin/$bin"
        echo "  ✓ $bin"
    else
        echo "  ⚠ $bin not found — run 'make build' first"
    fi
done

# =============================================================================
# 6. Overlays
# =============================================================================
if [ -d "$SCRIPT_DIR/overlays" ] && [ -n "$(ls -A "$SCRIPT_DIR/overlays" 2>/dev/null)" ]; then
    echo "▸ Applying overlays..."
    rsync -av "$SCRIPT_DIR/overlays/" "$R/"
fi

# =============================================================================
# Fix ownership so the dev user can read the outputs without sudo
# =============================================================================
DEV_USER="${SUDO_USER:-dev}"
chown "$DEV_USER" "$IMAGE" "$BOOT_OUT/vmlinuz" "$BOOT_OUT/initramfs" 2>/dev/null || true
chmod 644 "$IMAGE" "$BOOT_OUT/vmlinuz" "$BOOT_OUT/initramfs"

# =============================================================================
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║       Image build complete!              ║"
echo "║                                          ║"
printf "║  Image:     %-28s║\n" "$IMAGE"
echo "║  Kernel:    qemu/boot/vmlinuz            ║"
echo "║  Initrd:    qemu/boot/initramfs          ║"
echo "║                                          ║"
echo "║  Credentials: user/minerva root/minerva  ║"
echo "║  Boot:        make run                   ║"
echo "║  SSH:         make ssh (after boot)      ║"
echo "╚══════════════════════════════════════════╝"
echo ""
