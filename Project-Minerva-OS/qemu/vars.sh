#!/usr/bin/env bash
# =============================================================================
# QEMU launch defaults — overridden by Makefile env vars or .env
# =============================================================================

IMAGE="${IMAGE:-minervaos.img}"
QEMU_MEM="${QEMU_MEM:-8G}"
QEMU_SMP="${QEMU_SMP:-4}"
SSH_PORT="${SSH_PORT:-2222}"
