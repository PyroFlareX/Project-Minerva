#!/bin/sh
# setup-local.sh — Check that the local machine has everything needed to run
# `make remote-build` (rsync source to device, build natively over SSH).
#
# Usage:
#   bash scripts/setup-local.sh
#   MINERVA_HOST=my-device bash scripts/setup-local.sh

set -e

MINERVA_HOST="${MINERVA_HOST:-Minerva}"
PASS=0
FAIL=0

_ok()   { echo "  [ok]   $1"; PASS=$((PASS + 1)); }
_fail() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }
_info() { echo "         $1"; }

echo ""
echo "Checking local dependencies for 'make remote-build'..."
echo ""

# -----------------------------------------------------------------------------
# Local tools
# -----------------------------------------------------------------------------
echo "Local tools:"

if command -v rsync >/dev/null 2>&1; then
    _ok "rsync $(rsync --version 2>&1 | head -1 | awk '{print $3}')"
else
    _fail "rsync not found"
    _info "install: sudo apt install rsync  (or brew install rsync)"
fi

if command -v ssh >/dev/null 2>&1; then
    _ok "ssh ($(ssh -V 2>&1 | head -1))"
else
    _fail "ssh not found"
    _info "install: sudo apt install openssh-client"
fi

echo ""

# -----------------------------------------------------------------------------
# SSH connectivity to device
# -----------------------------------------------------------------------------
echo "Device connectivity (${MINERVA_HOST}):"

if ssh -o BatchMode=yes -o ConnectTimeout=5 "${MINERVA_HOST}" true 2>/dev/null; then
    _ok "SSH login to ${MINERVA_HOST} succeeded"
else
    _fail "Cannot SSH to ${MINERVA_HOST} (key auth failed or host unreachable)"
    _info "Make sure your SSH key is authorised and the host alias is set in ~/.ssh/config"
fi

# -----------------------------------------------------------------------------
# Remote tools (only if SSH works)
# -----------------------------------------------------------------------------
echo ""
echo "Remote tools on ${MINERVA_HOST}:"

_remote() {
    ssh -o BatchMode=yes -o ConnectTimeout=5 "${MINERVA_HOST}" "$@" 2>/dev/null
}

if ssh -o BatchMode=yes -o ConnectTimeout=5 "${MINERVA_HOST}" true 2>/dev/null; then
    if _remote "command -v cargo >/dev/null 2>&1 || [ -x \"\$HOME/.cargo/bin/cargo\" ]"; then
        CARGO_VER=$(_remote "PATH=\"\$HOME/.cargo/bin:\$PATH\" cargo --version" || echo "unknown")
        _ok "cargo: ${CARGO_VER}"
    else
        _fail "cargo not found on device"
        _info "install: curl https://sh.rustup.rs -sSf | sh"
    fi

    if _remote "command -v cc || command -v gcc || command -v clang" >/dev/null; then
        _ok "C compiler available (needed for some crate build scripts)"
    else
        _fail "No C compiler found on device"
        _info "install: doas apk add build-base"
    fi

    if _remote "pkg-config --exists fontconfig" 2>/dev/null; then
        FC_VER=$(_remote "pkg-config --modversion fontconfig" 2>/dev/null || echo "unknown")
        _ok "fontconfig ${FC_VER} (dev headers present)"
    else
        _fail "fontconfig dev headers not found on device"
        _info "install: doas apk add fontconfig-dev"
    fi

    if _remote "pkg-config --exists alsa" 2>/dev/null; then
        ALSA_VER=$(_remote "pkg-config --modversion alsa" 2>/dev/null || echo "unknown")
        _ok "alsa ${ALSA_VER} (dev headers present)"
    else
        _fail "alsa dev headers not found on device"
        _info "install: doas apk add alsa-lib-dev"
    fi
else
    _info "(skipping remote checks — SSH not reachable)"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "----------------------------------------"
echo "  Passed: ${PASS}   Failed: ${FAIL}"
echo "----------------------------------------"

if [ "${FAIL}" -gt 0 ]; then
    echo "  Fix the items above, then run 'make remote-build'."
    echo ""
    exit 1
else
    echo "  All checks passed — ready to run 'make remote-build'."
    echo ""
fi
