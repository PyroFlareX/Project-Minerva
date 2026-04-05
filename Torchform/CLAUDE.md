# Torchform — Claude Context

## What this is
Torchform is the desktop environment for **Project Minerva**: a dual-screen handheld device (1920×1080 upper, 640×480 lower) with a custom controller layout — gamepad buttons, Cirque GlidePoint SPI trackpad, right stick (TLV493D via MCU), and analog L2/R2 triggers.

## Crate map
| Crate | Role |
|---|---|
| `torchform-shell` | Main Slint UI process — overlays, built-in stub apps, event loop |
| `torchform-compositor` | Smithay Wayland compositor, two outputs, XDG tiling (winit backend for dev) |
| `torchform-inputd` | Input daemon — Cirque SPI, USB HID gamepad, uinput virtual device, Unix socket |
| `torchform-actions` | Shared lib — `ShellAction` enum + `InputMap` keybinds. No Slint dep. |
| `torchform-config` | Shared lib — `TorchformConfig` TOML loader + settings schema. No Slint dep. |
| `torchform-settings` | Standalone Settings app (Slint, same UI as shell stub) |
| `torchform-files` | Standalone File Browser app (Slint, same UI as shell stub) |
| `torchform-terminal` | Writes themed Alacritty/Kitty config then `exec()`s the terminal |
| `torchform-run` | Sets Wayland env vars then `exec()`s any app binary |

## Input pipeline
```
evdev / SPI
  → chord.rs (ChordDetector) — button edges, hat decoding, L2+R2 chord, D-pad repeat
  → InputMap::resolve() — RawInput name → ShellAction (keybinds.toml, falls back to defaults)
  → Unix socket JSON → torchform-shell
  → emu_handle_event() / sa_handle_event()
```
Analog axes (`StickMoved`, `PadMoved`) bypass `InputMap` and are constructed directly.

## Key design rules
- **Never use physical button names in shell logic** — always `ShellAction` variants.
- `torchform-actions` and `torchform-config` have no Slint dep so they compile in daemons and launchers.
- External apps launch via `try_launch_external()` in `apps.rs`; if the binary is absent, the built-in stub panel shows instead.
- Both `torchform-settings` and `torchform-files` can run standalone *or* be embedded in the shell.

## Build / run
```bash
# Shell only (no hardware libs needed):
cargo build -p torchform-shell
cargo run -p torchform-shell -- --emulator

# All tests (no hardware required):
cargo test -p torchform-actions
cargo test -p torchform-inputd   # tests are in chord.rs #[cfg(test)]

# Full workspace (needs libseat, libinput, libgbm):
cargo build --workspace
```

## Config files (runtime)
| File | Purpose |
|---|---|
| `~/.config/torchform/config.toml` | Main config — display, audio, apps, theme, radial slots |
| `~/.config/torchform/keybinds.toml` | Button → action overrides (snake_case ShellAction names) |
| `config/torchform.toml` | Dev fallback (Minerva Dark theme defaults) |
| `config/keybinds.toml` | Dev fallback keybinds |

## Known gaps (as of 2026-04)
- Settings/files built-in panels: D-pad navigation works; row upper-bound not clamped (BUG-002).
- Radial item activation is logged but not dispatched (BUG-004).
- App switcher close/switch callbacks not wired (BUG-005).
- Compositor DRM/KMS backend is a stub — only winit (dev) works today.
- System actions (brightness, volume, sleep, wifi) have UI but no backend syscall.
