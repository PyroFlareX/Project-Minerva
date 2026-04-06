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
torchform-shell       Slint UI process — shell overlays + built-in stub apps
torchform-compositor  Smithay Wayland compositor — two outputs, XDG tiling
torchform-inputd      Input daemon — Cirque SPI trackpad, USB HID gamepad,
                      uinput virtual device, Unix socket to shell

torchform-actions     Shared lib — ShellAction enum + InputMap keybinds (no Slint)
torchform-config      Shared lib — TorchformConfig + settings schema (no Slint)
torchform-settings    Standalone Settings app (Slint window, same UI as stub)
torchform-files       Standalone File Browser app (Slint window, same UI as stub)
torchform-terminal    Terminal launcher — writes themed config then exec()s terminal
torchform-run         Universal app launcher — sets Wayland env, then exec()s app
```

In production all processes run separately. In development, `torchform-shell` runs standalone (no compositor needed) and reads gamepad/keyboard directly via gilrs + Slint `FocusScope`.

### Input virtualization

All physical inputs are mapped to semantic `ShellAction` variants (defined in `torchform-actions`) before reaching the shell's event handlers. Raw button/axis names are never hardcoded in shell logic.

The mapping is controlled by `~/.config/torchform/keybinds.toml` (or `/etc/torchform/keybinds.toml`, or `config/keybinds.toml` in the repo). If no file is found, built-in defaults are used. See `config/keybinds.toml` for the full default table.

**Key `ShellAction` variants:**

| Variant | Meaning |
|---------|---------|
| `Confirm` / `Cancel` | Accept / dismiss |
| `NavUp` / `NavDown` / `NavLeft` / `NavRight` | D-pad direction |
| `OpenPalette` / `OpenSwitcher` | Toggle overlays |
| `RadialHold { held }` | Radial menu open (true) / close (false) |
| `StickMoved { x, y }` | Analog stick (bypasses map) |
| `WorkspacePrev` / `WorkspaceNext` | Cycle workspaces |
| `BrightnessUp/Down`, `VolumeUp/Down`, `WifiToggle`, … | System actions |

### Intended external programs

| Role | Intended binary | Fallback / stub |
|------|----------------|-----------------|
| Terminal | `alacritty` | `kitty` (configured via `config.toml [apps] terminal`) |
| File Manager | `torchform-files` (native Slint app) | in-shell stub |
| Settings | `torchform-settings` (native Slint app) | in-shell stub |
| Web Browser | Servo (embedded) | `chromium --kiosk --ozone-platform=wayland` |
| Media Player | `mpv --player-operation-mode=pseudo-gui` | in-shell stub |

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


**Alpine Linux (on-device / aarch64):**
```sh
# One-time setup — install build deps
apk add --no-cache \
    rust \
    clang \ #or gcc
    libalsa-dev \ 
    eudev-dev \
    libinput-dev \
    mesa-dev \
    libdrm-dev \
    wayland-dev \
    libx11-dev \
    libxcb-dev \
    libevdev-dev \
    libseat-dev

# Then build normally
cargo build --release -p torchform-shell
```

> **Note:** Alpine ships `eudev` (not systemd's `libudev`). The package `eudev-dev` provides
> `libudev.pc` and satisfies the `libudev-sys` crate. If `apk` reports `libseat-dev` not found,
> try `seatd-dev` instead.

**Docker (no host libs needed):**
```sh
make dev-build      # build the dev image (one-time, ~5 min)
make dev            # enter interactive container shell
# then run any cargo / make command from inside
```

### Run the emulator

The emulator is a single window that shows both displays inside a hardware-frame — like a DS emulator. This is the primary way to develop and test.

```sh
make run-emulator          # default — both screens, palette open
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

| Key           | Maps to          | Action                           |
|---------------|------------------|----------------------------------|
| `Space`       | Select           | Toggle command palette           |
| `Enter`       | Start            | Open app switcher                |
| `Tab` (hold)  | L2 (hold)        | Open radial menu                 |
| `Tab` release | L2 release       | Activate radial selection / exit |
| `Esc`         | B                | Dismiss overlay / close app      |
| `A`           | A (confirm)      | Select focused item              |
| Arrow keys    | D-pad            | Navigate UI elements / app rows  |
| `I` / `K`     | Stick North/South| Point radial menu up/down        |
| `J` / `L`     | Stick West/East  | Point radial menu left/right     |

The stick keys set a fixed deflection of 0.8 magnitude. Releasing any of them sends a zero vector (stick-release), which, when L2 is held, dismisses the radial without activating anything.

### Run with two separate windows (mirrors physical layout)

```sh
make run-standalone
cargo run -p torchform-shell -- --standalone
cargo run -p torchform-shell -- --standalone --demo radial
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

```sh
# Needs /dev/uinput write access — add user to 'input' group or run as root
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

### 3 — Start the shell

```sh
torchform-shell
```

The shell connects to `$WAYLAND_DISPLAY` as a Wayland client and to `/run/torchform/inputd.sock` for decoded input events.

---

## Project layout

```
Torchform/
├── Cargo.toml                    workspace (9 crates)
├── Makefile                      dev targets
├── config/
│   ├── torchform.toml            default DE config
│   └── keybinds.toml             default input → action bindings
├── scripts/
│   ├── send-input.py             mock gamepad event sender
│   └── dev.sh                    dev helpers
└── crates/
    ├── torchform-actions/        ← shared lib, NO Slint dependency
    │   └── src/
    │       ├── lib.rs            re-exports
    │       ├── action.rs         ShellAction enum (serde Serialize/Deserialize)
    │       └── input_map.rs      InputMap — RawInput → ShellAction via keybinds.toml
    ├── torchform-config/         ← shared lib, NO Slint dependency
    │   └── src/
    │       ├── lib.rs            re-exports
    │       ├── config.rs         TorchformConfig — full TOML config tree
    │       └── settings.rs       Settings schema (SCHEMA), SettingsRowData,
    │                             apply_activation, apply_adjustment, focus helpers
    ├── torchform-shell/
    │   ├── build.rs              slint_build — compiles ui/main.slint
    │   ├── src/
    │   │   ├── main.rs           emulator + standalone modes; uses ShellAction
    │   │   ├── apps.rs           try_launch_external — spawns Wayland apps on real DE
    │   │   ├── palette.rs        command palette state machine + registry
    │   │   ├── radial.rs         radial menu state machine + stick navigation
    │   │   ├── settings.rs       re-exports from torchform_config
    │   │   ├── config.rs         re-exports from torchform_config + parse_color
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
    │       ├── app_settings.slint  Settings panel (shared by shell + torchform-settings)
    │       └── app_files.slint     Files panel (shared by shell + torchform-files)
    ├── torchform-settings/       ← standalone Settings Slint app
    │   ├── build.rs
    │   ├── ui/main.slint         SettingsWindow — embeds AppSettings from shell/ui
    │   └── src/main.rs           full nav + activation callbacks
    ├── torchform-files/          ← standalone File Browser Slint app
    │   ├── build.rs
    │   ├── ui/main.slint         FilesWindow — embeds AppFiles from shell/ui
    │   └── src/main.rs           filesystem helpers + callbacks
    ├── torchform-terminal/       ← terminal launcher
    │   └── src/main.rs           writes themed alacritty.toml or kitty.conf,
    │                             then exec()s the terminal binary
    │   NOTE: Intended terminal: Alacritty (https://alacritty.org)
    │         Fallback terminal:  Kitty    (https://sw.kovidgoyal.net/kitty/)
    │         Configured via:     config.toml [apps] terminal = "alacritty"
    ├── torchform-run/            ← universal app launcher
    │   └── src/main.rs           sets Wayland env vars (SDL, Qt, GDK, MOZ, EGL)
    │                             then exec()s the target binary
    ├── torchform-compositor/
    │   └── src/
    │       ├── main.rs           event loop, Winit + UDev backends
    │       ├── compositor.rs     TorchState — all Smithay delegate impls
    │       ├── display.rs        TorchOutput — dual output management
    │       └── input.rs          InputAction, ChordTracker, evdev mappings
    └── torchform-inputd/
        └── src/
            ├── main.rs           input loop; translates chord::Action → ShellAction
            │                     via InputMap, publishes JSON over Unix socket
            ├── chord.rs          ChordDetector, low-level Action, D-pad repeat
            ├── cirque.rs         Cirque SPI driver + kernel evdev fallback
            └── uinput.rs         VirtualGamepad (uinput axes + buttons)
```

---

## Design system

| Token            | Value       | Usage                     |
|------------------|-------------|---------------------------|
| `bg-base`        | `#0d0f14`   | All backgrounds           |
| `bg-surface`     | `#1a1d24`   | Cards, overlays           |
| `bg-elevated`    | `#23273a`   | Highlighted rows          |
| `accent`         | `#00d4ff`   | Focus rings, active items |
| `accent-dim`     | `#007a99`   | Secondary accent          |
| `text-primary`   | `#e8eaf0`   | Body text                 |
| `text-secondary` | `#8892a4`   | Labels, hints             |

---

## Input grammar

All physical inputs are mapped through `InputMap` (loaded from `keybinds.toml`) to `ShellAction` variants before any shell logic sees them. To remap a button, edit `~/.config/torchform/keybinds.toml`.

### Default bindings

| Raw input name    | `ShellAction`                   | Meaning                                   |
|-------------------|---------------------------------|-------------------------------------------|
| `button_a`        | `Confirm`                       | Select focused item                       |
| `button_b`        | `Cancel`                        | Back / dismiss / close app                |
| `button_select`   | `OpenPalette`                   | Toggle command palette                    |
| `button_start`    | `OpenSwitcher`                  | Toggle app switcher                       |
| `l2_hold_true`    | `RadialHold { held: true }`     | Open radial menu                          |
| `l2_hold_false`   | `RadialHold { held: false }`    | Close radial (commit if stick active)     |
| `r2_hold_true`    | `RadialHold { held: true }`     | Same as L2                                |
| `r2_hold_false`   | `RadialHold { held: false }`    | Same as L2                                |
| `dpad_up`         | `NavUp`                         | Move focus up                             |
| `dpad_down`       | `NavDown`                       | Move focus down                           |
| `dpad_left`       | `NavLeft`                       | Move focus left / decrease slider         |
| `dpad_right`      | `NavRight`                      | Move focus right / increase slider        |
| `l1`              | `WorkspacePrev`                 | Previous workspace                        |
| `r1`              | `WorkspaceNext`                 | Next workspace                            |
| `select_long`     | `Sleep`                         | Suspend device                            |
| _(analog axes)_   | `StickMoved { x, y }`           | Steer radial menu (bypass map)            |
| _(Cirque pad)_    | `PadMoved { x, y }`             | Trackpad position (bypass map)            |

---

## Making programs for Torchform

There are two ways to add a program: **external Wayland apps** and **built-in stub panels**.

### Option A — External Wayland app

An external app is a normal Wayland client (GTK, Qt, Slint, terminal, etc.) that the compositor tiles on the upper display. This is how production apps ship.

#### How it works

When the user selects a command from the palette, `main.rs` calls `apps::try_launch_external(command_id)`. If the binary is found and spawned successfully, control returns to the shell. The child process inherits `WAYLAND_DISPLAY` from the compositor, so it connects automatically.

On the emulator / Docker where the binary is not present, `spawn()` returns `Err` and `try_launch_external` returns `false`. The shell then falls through to show a built-in stub panel instead (see Option B).

#### Steps to add an external app

1. **Register a palette entry** in `palette.rs::default_commands()`:

```rust
PaletteEntry {
    id:          "app.myapp".into(),
    label:       "My App".into(),
    description: "What it does".into(),
    category:    "App".into(),
    icon:        "🔧".into(),
    shortcut:    "".into(),
},
```

2. **Add a spawn arm** in `apps.rs::try_launch_external()`:

```rust
"app.myapp" => {
    std::process::Command::new("my-wayland-binary")
        .spawn()
        .is_ok()
}
```

The binary only needs to exist on the real device. On the emulator `spawn()` fails and `false` is returned, which triggers the built-in stub (step 3) if you write one.

3. **Optionally add a built-in stub** (see Option B below) for emulator testing.

### Option B — Built-in stub panel

A built-in app is a Slint `Rectangle` component that renders directly inside the upper-display area of the shell window. Use this for:
- Apps that need to work in the emulator / Docker (no Wayland compositor)
- Simple data views (settings, file browser, status) that don't need a separate process
- Prototyping before writing the full Wayland app

#### Steps to add a built-in stub

**1. Create the Slint component** as a new file, e.g. `ui/app_myapp.slint`:

```slint
import { Tokens } from "tokens.slint";

// IMPORTANT: inherits Rectangle, not Window.
// Window creates a separate OS window; Rectangle embeds inside the shell frame.
export component AppMyApp inherits Rectangle {
    background: Tokens.bg-base;

    // Row navigation — set by the shell when D-pad is pressed
    in property <int> focused-row: 0;

    // B button / close button fires this callback
    callback close-requested();

    // Your UI here
    Text {
        text: "My App";
        color: Tokens.text-primary;
        font-size: Tokens.text-lg;
        horizontal-alignment: center;
        vertical-alignment: center;
    }
}
```

**2. Import it in `emulator.slint`** (and `shell.slint` for standalone mode):

```slint
import { AppMyApp } from "app_myapp.slint";
```

Add properties and a close callback:
```slint
in property <bool>  app-myapp-visible: false;
in property <int>   app-myapp-focused-row: 0;
callback app-closed();   // already present — reuse this
```

Add the conditional panel inside the upper display `Rectangle` (before the overlay layers):
```slint
if app-myapp-visible: AppMyApp {
    x: 0; y: 0;
    width: parent.width; height: parent.height;
    focused-row: app-myapp-focused-row;
    close-requested => { root.app-closed(); }
}
```

**3. Add an `ActiveApp` variant** in `main.rs`:

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ActiveApp { Settings, Files, MyApp }
```

**4. Add state fields** to `ShellApp` if you need row tracking:

```rust
myapp_row: i32,
```

**5. Wire the palette command** in `emu_handle_event`'s `ButtonA` handler:

```rust
"app.myapp" => {
    app.active_app = Some(ActiveApp::MyApp);
    app.myapp_row = 0;
}
```

**6. Update `emu_apply_apps`** to set/clear the visible property:

```rust
Some(ActiveApp::MyApp) => {
    emu.set_app_myapp_visible(true);
    emu.set_app_myapp_focused_row(app.myapp_row);
    emu.set_app_settings_visible(false);
    emu.set_app_files_visible(false);
}
```

Also clear it in the `None` arm.

**7. Add D-pad navigation** in `DpadUp`/`DpadDown` match arms:

```rust
Some(ActiveApp::MyApp) => {
    app.myapp_row = (app.myapp_row + delta).clamp(0, MAX_ROWS);
    emu.set_app_myapp_focused_row(app.myapp_row);
}
```

**8. Repeat steps 2–7** for `shell.slint` and `sa_handle_event` / `sa_apply_apps` if you want the app to work in standalone mode too.

---

## Built-in programs

### Settings (`app.settings`)

**File:** `ui/app_settings.slint`
**Command ID:** `app.settings` (also matches `settings`, `open-settings`)
**External binary:** `gnome-control-center` (tried first on real DE; falls back to stub)

A stub settings panel with a scrollable list of placeholder rows. Each row is navigable with D-pad Up/Down. B closes the panel.

**State:** `settings_row: i32` — currently focused row index, clamped to ≥ 0.

### File Manager (`app.files`)

**File:** `ui/app_files.slint`
**Command ID:** `app.files` (also matches `file-manager`, `open-files`)
**External binary:** `thunar` (tried first; falls back to stub)

A stub file browser showing the current path and a list of entries. Selecting a directory entry fires the `navigate(name)` callback, which appends the name to the path. D-pad Up/Down moves the row highlight. B closes the panel.

**State:**
- `files_row: i32` — focused row index
- `files_path: String` — current directory path (starts at `/home`)

**Navigation:** path is built by appending `/{name}` to the current path. There is no `..` parent navigation yet (see Known Bugs).

---

## Command palette registry

All commands registered in `palette.rs::default_commands()`:

| ID                    | Label                | Category | External binary      |
|-----------------------|----------------------|----------|----------------------|
| `app.settings`        | Open Settings        | App      | `gnome-control-center` |
| `app.files`           | File Manager         | App      | `thunar`             |
| `app.editor`          | Text Editor          | App      | _(stub only)_        |
| `app.browser`         | Web Browser          | App      | _(stub only)_        |
| `app.network`         | Network Manager      | App      | _(stub only)_        |
| `app.gpio`            | GPIO Manager         | App      | _(stub only)_        |
| `sys.brightness.up`   | Brightness Up        | System   | _(not implemented)_  |
| `sys.brightness.down` | Brightness Down      | System   | _(not implemented)_  |
| `sys.volume.up`       | Volume Up            | System   | _(not implemented)_  |
| `sys.volume.down`     | Volume Down          | System   | _(not implemented)_  |
| `sys.wifi.toggle`     | Toggle WiFi          | System   | _(not implemented)_  |
| `sys.bt.toggle`       | Toggle Bluetooth     | System   | _(not implemented)_  |
| `sys.sleep`           | Sleep                | System   | _(not implemented)_  |
| `sys.split.toggle`    | Toggle Split Screen  | System   | _(not implemented)_  |

---

## Status

| Component                  | Status                                                        |
|----------------------------|---------------------------------------------------------------|
| Shell emulator window      | Working — run `make run-emulator`                             |
| Keyboard shortcuts         | Working (includes IJKL stick simulation)                      |
| HID gamepad (gilrs)        | Working in emulator mode                                      |
| Input virtualization       | Working — `ShellAction` + `InputMap` + `keybinds.toml`        |
| Radial menu UI             | Working — stick steers, release activates/dismisses           |
| Command palette UI         | Working — D-pad + virtual keyboard, scrolls correctly         |
| App switcher UI            | Working (display only, no close/switch logic)                 |
| Settings app               | Working — schema-driven, sliders/toggles/selects, scrolls     |
| Files app                  | Working — directory navigation, icons, file sizes             |
| torchform-terminal         | Builds — writes Alacritty/Kitty theme config, exec()s terminal|
| torchform-settings         | Builds — standalone Slint window                              |
| torchform-files            | Builds — standalone Slint window                              |
| torchform-actions lib      | Working — InputMap + ShellAction, 4 unit tests                |
| torchform-config lib       | Working — full settings schema, mutation helpers              |
| Wayland compositor         | Builds; Winit backend functional                              |
| DRM/KMS backend            | Stub — pending hardware integration                           |
| Input daemon               | Builds; translates chord::Action → ShellAction via InputMap   |
| Cirque SPI driver          | Written; requires CM5 hardware                                |

---

## Known bugs

### BUG-001 — Files stub: no parent-directory navigation

**Location:** `main.rs` (`on_app_files_navigate`), `app_files.slint`

The path is built by always appending `/{name}` to the current path. There is no mechanism to navigate to the parent directory (no `..` entry, no backspace). Selecting a file does nothing different from selecting a directory.

**Fix needed:** Add a `..` entry at the top of the file list in `app_files.slint`. In `main.rs`, detect `..` in the navigate handler and strip the last path component with `std::path::PathBuf`.

---

### BUG-002 — `settings_row` and `files_row` have no upper bound

**Location:** `main.rs` `DpadDown` handler, both `emu_handle_event` and `sa_handle_event`

The row index is incremented without knowing the number of rows in the Slint component. The focused highlight will appear past the last visible row if D-pad Down is pressed too many times. (The lower bound is correctly clamped at 0.)

**Fix needed:** Either query the row count from the Slint model or define a `MAX_SETTINGS_ROWS` / `MAX_FILES_ROWS` constant and clamp on the way down.

---

### BUG-003 — Standalone mode missing `on_app_closed` and `on_app_files_navigate` callbacks

**Location:** `main.rs` `run_standalone()`

`on_app_closed` and `on_app_files_navigate` are wired in `run_emulator` but not in `run_standalone`. In standalone mode the B button inside an app panel will not close it (the Slint close callback fires into nothing) and folder navigation does not update the path.

**Fix needed:** Mirror the same two callback registrations from `run_emulator` into `run_standalone`, using `shell.as_weak()` instead of `emu.as_weak()`.

---

### BUG-004 — Radial menu item activation is logged but never acted upon

**Location:** `main.rs` `ButtonA` and `L2Held(false)` handlers

When the user activates a radial slot (via stick-release or A-button), the item label is logged with `info!()` but no action is taken. System commands (brightness, volume, wifi) have no backend implementation.

**Fix needed:** Implement a `handle_radial_action(item_id: &str)` function that dispatches system commands (initially as stubs that log "TODO").

---

### BUG-005 — App switcher has no close or switch logic

**Location:** `main.rs` `on_switcher_app_activated`, `on_switcher_app_closed`

The app switcher overlay renders correctly but the `switcher-app-activated` and `switcher-app-closed` callbacks are not wired in either run mode. Selecting or closing a card does nothing.

**Fix needed:** Wire `on_switcher_app_activated` and `on_switcher_app_closed` to update `WorkspaceManager` and dismiss the switcher.

---

### BUG-006 — `app.editor`, `app.browser`, `app.network`, `app.gpio` palette commands do nothing

**Location:** `apps.rs`, `main.rs`

These four palette entries have no external binary match in `try_launch_external` and no `ActiveApp` variant, so activating them closes the palette and opens nothing.

**Fix needed:** For each, either add a `spawn()` call to `apps.rs` (real DE) or add a stub panel (emulator). At minimum add a `try_launch_external` arm that attempts to launch a sensible default binary.
