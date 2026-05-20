# Torchform DE — User Guide

Torchform is the desktop environment for Project Minerva: a dual-screen handheld device with a
gamepad controller, SPI trackpad, and analog triggers. The shell presents a Nintendo-3DS-style
interface on the upper display.

## Screens

### Lock screen

Torchform boots to the lock screen. A large clock and date are shown in the center.

- Press **A** four times to enter a PIN and unlock to the Home screen.
- The PIN dots at the bottom fill in as you press A.
- Press **B** to erase the last digit.

### Home screen

The Home screen has two zones:

**App grid** — the top area shows up to 7 app tiles arranged in a 6-column grid. Navigate with
the D-pad. Press **A** to launch the focused app.

**Dock** — the bottom bar shows 5 pinned apps. D-pad left/right navigates into the dock once you
reach the bottom row of the grid.

The focused tile is highlighted with a glow border and the app name is shown in the status bar.

### App screen

When an app is open, a title bar appears at the top showing the app icon and name. Two buttons
sit on the right side of the title bar:

- **⌂** — return to the Home screen (same as pressing **Select**).
- **⧉** — open the App Switcher.

The app widget fills the space below the title bar. Navigation inside the app uses the D-pad and
A/B buttons.

## Overlays and panels

### Quick Settings panel

Slides in from the **right**. Opens with **R1 / ZR** (default).

Contains:

- **Volume** slider — drag or press D-pad left/right when focused.
- **Brightness** slider — same.
- **Tile grid** — 2-column grid of toggle tiles: Wi-Fi, Bluetooth, Do Not Disturb, Airplane
  Mode, VPN, and more. Press **A** to toggle the focused tile.

Navigate tiles with the D-pad. Press **B** or re-press **R1** to close.

### Notifications panel

Slides in from the **left**. Opens with **L1 / ZL** (default).

Shows a list of recent notifications with icon, app name, title, body, and timestamp. Navigate
with the D-pad. Press **A** to open the source app. Press **Clear all** (focused with D-pad,
confirmed with A) to dismiss all notifications.

Press **B** or re-press **L1** to close.

### App Switcher

Full-screen card row showing all running apps. Opens with **Start**.

- D-pad left/right moves focus between cards.
- **A** resumes the focused app.
- **X** closes (kills) the focused app.
- **B** or **Start** dismisses the switcher without changing the active app.

### Command Palette

Overlay search and launcher. Opens with **X** (default).

Type to filter commands (on hardware this uses the virtual keyboard on the lower display; in the
emulator type directly). Press **A** or **Enter** to run the focused command. Press **B** or
**Esc** to dismiss.

### Radial Menu

Circular quick-action ring. Hold **L2** or **R2** (either trigger). The ring appears centred on
screen. Use the left analog stick or D-pad to steer the highlight to a slot. Release the trigger
to activate.

Default slots: Brightness, Volume, Wi-Fi toggle, Bluetooth toggle, Cellular, VPN, Sleep, Settings.

### Banner toasts

Small notifications slide in from the top and auto-dismiss after 3.5 seconds. They appear when
an action produces a notification (e.g. a screenshot is taken). No interaction required.

## Navigation reference

| Button | Action |
| --- | --- |
| A | Confirm / activate |
| B | Back / cancel / dismiss |
| X | Open command palette |
| Select | Go to Home screen |
| Start | Open App Switcher |
| L1 / ZL | Open Notifications panel |
| R1 / ZR | Open Quick Settings panel |
| L2 / R2 (hold) | Open radial menu |
| Select (long press) | Lock screen |
| D-pad | Navigate |

## Apps

| App | Command ID | Description |
| --- | --- | --- |
| Terminal | `app.terminal` | Shell emulator (external binary on hardware) |
| Browser | `app.browser` | Web browser (external binary on hardware) |
| Files | `app.files` | File browser with directory navigation |
| Media | `app.media` | Music/video player with transport controls |
| Phone | `app.phone` | Dialer with dialpad keypad |
| Messages | `app.sms` | SMS thread list and bubble chat view |
| Email | `app.email` | Email inbox with unread badge |
| Settings | `app.settings` | System settings (display, audio, input, network, privacy) |
| Monitor | `app.sysmon` | CPU, RAM, GPU usage bars; per-core view; process table |
| Packages | `app.pkgman` | Package install / remove / update |
| Logs | `app.logview` | Filtered system log viewer with tail mode |
| Notes | `app.notes` | Note list and plain-text editor |

### External vs. built-in apps

Terminal, Browser, Files, Media, and Network Manager have configurable external binaries (e.g.
`foot`, `firefox`, `thunar`). If the binary is found, Torchform launches it as a Wayland client.
If the binary is absent (emulator mode, or not configured), the built-in stub widget is shown
instead. Configure external binaries in `[apps]` in `config/torchform.toml`.

## Emulator keyboard shortcuts

The emulator window maps keyboard keys to controller inputs for desktop testing.

| Key | Controller |
| --- | --- |
| Space | Select (Home) |
| Enter | Start (Switcher) |
| Tab (hold/release) | L2 trigger (Radial) |
| Esc | B (back) |
| A | A (confirm) |
| X | X (palette) |
| Z | R1 — Quick Settings |
| C | L1 — Notifications |
| Arrow keys | D-pad |
| I / K / J / L | Stick North / South / West / East |

## Themes

Three themes ship in `config/themes/`:

| Theme file | Name | Accent |
| --- | --- | --- |
| `minerva-dark.toml` | Minerva Dark | Electric teal `#00d4ff` |
| `ember-light.toml` | Ember Light | Warm orange |
| `torchform-os.toml` | Torchform OS | Electric yellow `#e8ff47` |

To change theme, set `theme_file` in `[theme]` in your config (see
[torchform-config.md](torchform-config.md)).

## Running on hardware (Minerva)

```bash
# Build release binary:
make remote-build

# View via VNC (cage + wayvnc on device, gvncviewer locally):
make remote-vnc

# Kill VNC session:
make remote-vnc-kill
```

The `remote-build` target syncs the repository to `~/torchform-dev/` on the device and builds
natively with the device's Rust toolchain.

## Development workflow

```bash
# Check (fastest — no codegen):
make check

# Build and run emulator:
make run-emulator

# Run with a specific overlay open on launch:
make run-shell-radial
make run-shell-switcher
make run-shell-idle

# Two separate windows (mirrors physical device layout):
make run-standalone

# Run all tests (no hardware required):
cargo test -p torchform-shell --bin torchform-shell
cargo test -p torchform-actions

# Docker dev container (if native Rust/libs unavailable):
make dev
```
