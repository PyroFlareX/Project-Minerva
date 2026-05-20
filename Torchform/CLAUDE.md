# Torchform — Claude Context

## What this is
Torchform is the desktop environment for **Project Minerva**: a dual-screen handheld device
(1920×1080 upper display, 640×480 lower display) with a custom controller layout — gamepad
face/shoulder buttons, Cirque GlidePoint SPI trackpad, right stick (TLV493D via MCU), and
analog L2/R2 triggers.

The UI is built with **Rust + Slint**. The shell presents a Nintendo-3DS-style chrome on the
upper display: lock screen → home grid+dock → app window, with a persistent status bar (top),
hint bar (bottom), side-sliding Quick Settings and Notifications panels, a full-screen App
Switcher, and banner toasts. The lower display is a companion screen (idle status, virtual
keyboard, app-context info).

---

## Crate map

| Crate | Role |
|---|---|
| `torchform-shell` | Main Slint UI process — N3DS chrome, overlays, built-in app stubs, event loop |
| `torchform-apps` | Slint component library — all 12 app UIs (embeddable in shell or standalone) |
| `torchform-compositor` | Smithay Wayland compositor, two outputs, XDG tiling (winit backend for dev) |
| `torchform-inputd` | Input daemon — Cirque SPI, USB HID gamepad, uinput virtual device, Unix socket |
| `torchform-actions` | Shared lib — `ShellAction` enum + `InputMap` keybinds. No Slint dep. |
| `torchform-config` | Shared lib — `TorchformConfig` TOML loader + settings schema. No Slint dep. |
| `torchform-settings` | Standalone Settings app (Slint; same `AppSettings` component as shell) |
| `torchform-files` | Standalone File Browser app (Slint; same `AppFiles` component as shell) |
| `torchform-terminal` | Writes themed Alacritty/Kitty config then `exec()`s the terminal |
| `torchform-run` | Sets Wayland env vars then `exec()`s any app binary |
| `minerva-emulator` | Hardware emulator frame (Minerva device UI, separate from shell) |

---

## Shell architecture

### Screen / state machine (`src/shell.rs`)

The entire chrome state lives in `Shell`, driven by `Shell::handle(ShellAction) -> Vec<Effect>`.
No Slint types inside — pure, unit-testable.

```
Screen: Lock | Home | App
Panel:  QuickSettings | Notifications | Switcher   (stored as Option<Panel>)
```

Priority routing in `handle()`:

1. Radial menu (if open) — consumes input
2. Command palette (if open)
3. Open panel (QS / NF / Switcher)
4. Screen (Lock / Home / App)

Side effects are returned as `Vec<Effect>` (Sound, LaunchExternal, ShowBanner, SaveConfig,
Suspend) and applied by the dispatch layer, keeping the state machine pure.

### Render macro (`src/main.rs`)

```rust
macro_rules! push_shell_render { ($ui:expr, $s:expr) => { ... } }
```

Sets all ~40 Slint properties on any type that exposes the generated setter names. Called as
`render_emu(&emu, &shell)` or `render_shell(&win, &shell)` — one path, two window types.

### App IDs (`src/shell.rs`)

```
HOME_GRID: [Media, Email, Settings, Sysmon, Pkgman, Logview, Notes]  (7 tiles, 2 rows)
DOCK:      [Terminal, Browser, Sms, Phone, Files]                      (5 icons, bottom bar)
```

`AppId::from_command(&str)` maps palette command IDs (e.g. `"app.terminal"`) to `AppId`.

### Input pipeline
```
evdev / SPI
  → chord.rs (ChordDetector) — button edges, hat decoding, L2+R2 chord, D-pad repeat
  → InputMap::resolve() — RawInput → ShellAction  (keybinds.toml → defaults)
  → Unix socket JSON → torchform-shell dispatch
  → Shell::handle(action) → Vec<Effect>
  → apply_effects() + render_*()
```
Analog axes (`StickMoved`, `PadMoved`) bypass `InputMap` and are built directly.

### Default button map (configurable in `config/keybinds.toml`)

| Button | Action |
|---|---|
| A | confirm |
| B | cancel |
| Select | go_home |
| Start | open_switcher |
| X | open_palette |
| L1 / ZL | open_notifications |
| R1 / ZR | open_quick_settings |
| L2 / R2 (hold) | radial_hold_true / _false |
| Select (long) | lock |
| D-pad | nav_up / down / left / right |

### Emulator keyboard shortcuts

| Key | Maps to |
|---|---|
| Space | Select / go_home |
| Enter | Start / open_switcher |
| Tab (hold/release) | L2 trigger — radial |
| Esc | B — back/cancel |
| A | A — confirm |
| X | X — palette |
| Z | Quick Settings |
| C | Notifications |
| Arrow keys | D-pad |
| I J K L | Analog stick (N/W/S/E) |

---

## Slint UI layout

### `ui/` directory
```
ui/
  main.slint            — entry point; imports + re-exports all structs
  tokens.slint          — Tokens global (colors, fonts, spacing, radii, animations)
  emulator.slint        — TorchformEmulator window (both displays in one frame)
  shell.slint           — ShellOverlay window (standalone; upper display only)
  lower_screen.slint    — StatusPanel + VirtualKeyboard (lower display)
  radial_menu.slint     — RadialMenu overlay
  command_palette.slint — CommandPalette overlay
  app_switcher.slint    — AppSwitcher overlay (full-screen card row)
  chrome/
    shell_screen.slint  — ShellScreen enum { Lock, Home, App }
    status_bar.slint    — StatusBar (28px, top) — workspace dots, clock, icons, battery
    hint_bar.slint      — HintBar (24px, bottom) — {key, label} chip row
    lock_screen.slint   — LockScreen — big clock, date, 4-dot PIN
    home_screen.slint   — HomeScreen — 7-tile grid + 5-icon dock + search bar
    app_window.slint    — AppTitleBar — icon + name + ⌂ home + ⧉ switcher buttons
    quick_settings.slint — QuickSettings — right-slide panel; sliders + 2-col tile grid
    notifications.slint — Notifications — left-slide panel; NotifEntry list
    banner.slint        — Banner — top-slide toast (auto-cleared after 3500 ms)
```

### `crates/torchform-apps/ui/` — all 12 app components

All import Tokens via `../../torchform-shell/ui/tokens.slint`.

| File | Component | Key structs |
| --- | --- | --- |
| `app_settings.slint` | `AppSettings` | `SettingsEntry` |
| `app_files.slint` | `AppFiles` | `FileEntry` |
| `app_file_manager.slint` | `AppFileManager` | (uses FileEntry) |
| `app_camera.slint` | `AppCamera` | — |
| `app_web_browser.slint` | `AppWebBrowser` | — |
| `app_media_player.slint` | `AppMediaPlayer` | — |
| `app_network_manager.slint` | `AppNetworkManager` | `WifiNetwork`, `BtDevice` |
| `app_terminal.slint` | `AppTerminal` | `TermLine` |
| `app_phone.slint` | `AppPhone` | — |
| `app_sms.slint` | `AppSms` | `SmsThread`, `SmsMessage` |
| `app_email.slint` | `AppEmail` | `EmailMsg` |
| `app_sysmon.slint` | `AppSysmon` | — |
| `app_pkgman.slint` | `AppPkgman` | `PkgEntry` |
| `app_logview.slint` | `AppLogview` | `LogLine` |
| `app_notes.slint` | `AppNotes` | `NoteEntry` |

App component contract:

- Inherits `Rectangle`
- `in property <int> focused-row` — D-pad focus position
- `callback close-requested()` — B/back button
- App-specific `in` data models pushed from Rust

---

## Key design rules
- **Never use physical button names in shell logic** — always `ShellAction` variants.
- `torchform-actions` and `torchform-config` have no Slint dep — compile in daemons/launchers.
- External apps launch via `try_launch_external()` in `apps.rs`; binary absent → built-in stub.
- Both `torchform-settings` and `torchform-files` can run **standalone or embedded** — same
  Slint component, different window wrapper. Import from `torchform-apps/ui/`, not shell.
- `torchform-apps` is the canonical home for all app Slint components. The shell and standalone
  crates all import from there.
- Effects from `Shell::handle()` are pure — no Slint types, no I/O. Apply them in `dispatch_*`.
- `font-display` (Barlow Condensed) is for lock clock, panel headers, app-bar titles, section
  labels. `font-mono` (DM Mono) for system data. `font-sans` (Inter) for body.

---

## Build / run

```bash
# Shell only (no hardware libs needed):
cargo check -p torchform-shell
cargo build -p torchform-shell
cargo run  -p torchform-shell          # emulator mode (default)
cargo run  -p torchform-shell -- --standalone

# Demo modes:
cargo run  -p torchform-shell -- --demo radial
cargo run  -p torchform-shell -- --demo switcher
cargo run  -p torchform-shell -- --demo idle

# Tests (no hardware required):
cargo test -p torchform-shell --bin torchform-shell   # 16 tests
cargo test -p torchform-actions

# Full workspace (needs libseat, libinput, libgbm):
cargo build --workspace

# Makefile shortcuts:
make run-emulator        # single hardware-frame window (both displays)
make run-standalone      # two separate windows
make run-shell-radial    # emulator + radial open
make check               # cargo check torchform-shell
make build-all           # full workspace
make dev                 # Docker dev container
make remote-vnc          # run on Minerva, view via VNC
```

---

## Config files (runtime)

| File | Purpose |
|---|---|
| `~/.config/torchform/config.toml` | Main config — theme, audio, apps, radial slots |
| `~/.config/torchform/keybinds.toml` | Button → ShellAction overrides |
| `config/torchform.toml` | Dev fallback (checked in, Minerva Dark theme) |
| `config/keybinds.toml` | Dev fallback keybinds |
| `config/themes/minerva-dark.toml` | Built-in teal theme |
| `config/themes/ember-light.toml` | Built-in light theme |
| `config/themes/torchform-os.toml` | N3DS-style theme (near-black + yellow accent) |

---

## Known gaps / active work

- App switcher full-screen card layout (HTML `#psw`) not yet wired to running-app data.
- Sysmon, Pkgman, Logview: Slint components ready; Rust state modules (CPU poll, pacman,
  journald) not yet implemented.
- Phone / SMS / Email: UI components ready; no backend integration.
- System actions (brightness, volume, sleep, wifi) have UI but no backend syscall.
- Compositor DRM/KMS backend is a stub — only winit (dev) works today.
- `font-display` (Barlow Condensed) must be installed on the device; falls back to Inter.
