#!/bin/sh
# torchform-run.sh — Shell fallback launcher for Torchform apps
# Sets the required Wayland / SDL / Qt / GTK environment variables
# then exec()s the given command, replacing this process.
#
# Usage: torchform-run.sh <binary> [args...]
#   e.g. torchform-run.sh thunar
#        torchform-run.sh firefox --new-window
#        torchform-run.sh retroarch -L /usr/lib/libretro/snes9x_libretro.so

export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/torchform}"
export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-wayland}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"
export GDK_BACKEND="${GDK_BACKEND:-wayland}"
export MOZ_ENABLE_WAYLAND="${MOZ_ENABLE_WAYLAND:-1}"
export EGL_PLATFORM="${EGL_PLATFORM:-wayland}"
export CLUTTER_BACKEND="${CLUTTER_BACKEND:-wayland}"
export __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME:-mesa}"

if [ $# -eq 0 ]; then
    echo "Usage: torchform-run.sh <binary> [args...]" >&2
    exit 1
fi

exec "$@"
