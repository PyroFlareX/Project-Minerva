# Torchform DE

Torchform is the desktop environment for Project Minerva — a handheld device with two DSI displays and a custom controller layout. It is built entirely in Rust.

```
┌────────────────────────────────────────┐
│          Upper Display 1920×1080        │  ← apps, shell overlays (DSI-1)
├────────────────────────────────────────┤
│        Lower Display 640×480           │  ← status, virtual keyboard (DSI-2)
└────────────────────────────────────────┘
```

---

## Architecture

```
torchform-shell       Slint UI process — shell overlays + stub apps
torchform-compositor  Smithay Wayland compositor — two outputs, XDG tiling
torchform-inputd      Input daemon — Cirque SPI trackpad, USB HID gamepad,
                      uinput virtual device, Unix socket to shell
```

In production all three run as separate processes. In development, `torchform-shell` runs standalone (no compositor needed) and reads gamepad/keyboard directly via gilrs + Slint `FocusScope`.

---

## Quick start — desktop testing (no hardware required)

### Prerequisites

**Native (recommended if you have Rust installed):**
```sh
# Rust — install from https://rustup.rs if not present
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# System libs needed for the full workspace
# Debian/Ubuntu:
sudo apt-get install \
    libseat-dev libinput-dev libgbm-dev libdrm-dev \
    libudev-dev libxkbcommon-dev libwayland-dev \
    libx11-dev libx11-xcb-dev libevdev-dev \
    pkg-config build-essential
```

**Docker (no host libs needed):**
```sh
make dev-build      # build the dev image (one-time, ~5 min)
make dev            # enter interactive container shell
# then run any cargo / make command from inside
```

### Run the emulator

The emulator is a single window that shows both displays inside a hardware-frame — like a DS emulator. This is the primary way to develop and test.

```sh
make run-emulator          # default — both screens, no overlay
make run-shell-radial      # start with radial menu open
make run-shell-switcher    # start with app switcher open
make run-shell-idle        # start with lower screen in idle/status mode
```

Or with cargo directly:
```sh
cargo run -p torchform-shell
cargo run -p torchform-shell -- --demo radial
cargo run -p torchform-shell -- --demo switcher
cargo run -p torchform-shell -- --demo idle
```

### Keyboard shortcuts in the emulator window

| Key        | Maps to       | Action                        |
|------------|---------------|-------------------------------|
| `Space`    | Select        | Toggle command palette        |
| `Enter`    | Start         | Open app switcher             |
| `Tab`      | L2 (hold)     | Open radial menu              |
| `Esc`      | B             | Dismiss / back                |
| `A`        | A             | Confirm / select              |
| Arrow keys | D-pad         | Navigate UI elements          |

### Run with two separate windows (mirrors physical layout)

```sh
make run-standalone
cargo run -p torchform-shell -- --standalone
cargo run -p torchform-shell -- --standalone --demo radial
```

### Send mock gamepad events

In a second terminal, while the shell is running:
```sh
make send-input
# or
python3 scripts/send-input.py
```

---

## Build targets

```sh
make check           # fast type-check — torchform-shell only (no hardware libs)
make build           # debug build — torchform-shell only
make build-release   # release build — torchform-shell only
make build-all       # full workspace (needs libseat/libinput/libgbm/libdrm)
make check-all       # full workspace type-check
```

---

## Running as a real DE (target device or QEMU)

On a system where Torchform is the compositor (Raspberry Pi CM5, or nested in another compositor via Winit):

### 1 — Start the input daemon

The input daemon must start first so the socket exists before the shell connects.

```sh
# Needs /dev/uinput write access — add user to 'input' group or run as root
sudo torchform-inputd
# or with a user that has the right permissions:
torchform-inputd
```

It will:
- Open `/dev/spidev0.0` for the Cirque trackpad (skips gracefully if absent)
- Scan `/dev/input/event*` for the USB HID gamepad
- Create a uinput virtual gamepad
- Listen on `/run/torchform/inputd.sock` for the shell to connect

### 2 — Start the compositor

```sh
# Development / QEMU — runs inside an X11 or Wayland window
TORCHFORM_BACKEND=winit torchform-compositor

# Production — DRM/KMS direct to hardware (stub, full integration pending)
TORCHFORM_BACKEND=udev torchform-compositor
```

The compositor sets `WAYLAND_DISPLAY` automatically. Note it in your shell:
```sh
export WAYLAND_DISPLAY=$(ls /run/user/$(id -u)/wayland-* | head -1 | xargs basename)
```

### 3 — Start the shell

```sh
torchform-shell
```

The shell connects to `$WAYLAND_DISPLAY` as a Wayland client and to `/run/torchform/inputd.sock` for decoded input events.

### All three at once (development convenience)

```sh
torchform-inputd &
TORCHFORM_BACKEND=winit torchform-compositor &
sleep 1   # wait for socket + Wayland display
torchform-shell
```

---

## Project layout

```
Torchform/
├── Cargo.toml                    workspace
├── Makefile                      dev targets
├── scripts/
│   ├── send-input.py             mock gamepad event sender
│   └── dev.sh                    dev helpers
└── crates/
    ├── torchform-shell/
    │   ├── build.rs              slint_build — compiles ui/main.slint
    │   ├── src/
    │   │   ├── main.rs           emulator + standalone modes, gilrs, keyboard wiring
    │   │   ├── apps.rs           AppManager — opens Settings / Files windows
    │   │   ├── palette.rs        command palette state machine
    │   │   ├── radial.rs         radial menu state machine
    │   │   └── workspace.rs      workspace / tiling config
    │   └── ui/
    │       ├── main.slint        single compile entry point
    │       ├── tokens.slint      design system (colours, typography)
    │       ├── shell.slint       upper display overlay (standalone mode)
    │       ├── lower_screen.slint lower companion display (standalone mode)
    │       ├── emulator.slint    combined DS-frame window (default mode)
    │       ├── radial_menu.slint radial overlay component
    │       ├── command_palette.slint command palette overlay
    │       ├── app_switcher.slint  app switcher overlay
    │       ├── app_settings.slint  stub Settings app
    │       └── app_files.slint     stub Files app
    ├── torchform-compositor/
    │   └── src/
    │       ├── main.rs           event loop, Winit + UDev backends
    │       ├── compositor.rs     TorchState — all Smithay delegate impls
    │       ├── display.rs        TorchOutput — dual output management
    │       └── input.rs          InputAction, ChordTracker, evdev mappings
    └── torchform-inputd/
        └── src/
            ├── main.rs           input loop, SPI + evdev + socket publish
            ├── chord.rs          ChordDetector, Action, D-pad repeat
            ├── cirque.rs         Cirque SPI driver + kernel evdev fallback
            └── uinput.rs         VirtualGamepad (uinput axes + buttons)
```

---

## Design system

| Token           | Value       | Usage                    |
|-----------------|-------------|--------------------------|
| `bg-base`       | `#0d0f14`   | All backgrounds          |
| `bg-surface`    | `#1a1d24`   | Cards, overlays          |
| `bg-elevated`   | `#23273a`   | Highlighted rows         |
| `accent`        | `#00d4ff`   | Focus rings, active items |
| `accent-dim`    | `#007a99`   | Secondary accent         |
| `text-primary`  | `#e8eaf0`   | Body text                |
| `text-secondary`| `#8892a4`   | Labels, hints            |

---

## Input grammar

| Input          | Action                                    |
|----------------|-------------------------------------------|
| A              | Confirm / select                          |
| B              | Back / cancel                             |
| Select         | Command palette                           |
| Start          | App switcher                              |
| L2 (hold)      | App radial — layer 1                      |
| R2 (hold)      | App radial — layer 2                      |
| L2 + R2        | System radial menu                        |
| D-pad          | Navigate focused UI element               |
| L1 / R1        | Cycle tile focus (compositor)             |
| Left pad       | Cursor / scroll (via uinput ABS_X/Y)      |

---

## Status

| Component             | Status                              |
|-----------------------|-------------------------------------|
| Shell emulator window | Working — run `make run-emulator`   |
| Keyboard shortcuts    | Working                             |
| HID gamepad (gilrs)   | Working in emulator mode            |
| Radial menu UI        | Working (demo mode)                 |
| Command palette UI    | Working (demo mode)                 |
| App switcher UI       | Working (demo mode)                 |
| Settings app (stub)   | Working                             |
| Files app (stub)      | Working                             |
| Wayland compositor    | Builds; Winit backend functional    |
| DRM/KMS backend       | Stub — pending hardware integration |
| Input daemon          | Builds; requires CM5 hardware       |
| Cirque SPI driver     | Written; requires CM5 hardware      |
