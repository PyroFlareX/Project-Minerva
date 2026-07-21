# Repository Guidelines

## Project Overview

Project Minerva is a custom clamshell handheld computer built around the Raspberry Pi Compute Module 5 (CM5): dual displays (5.5" 1080p upper, 3.5" touch lower), controller-only input (no keyboard/mouse), cellular WWAN, NFC, and a security-first Alpine-based OS. This monorepo holds everything: KiCad hardware design, the OS build system, the Torchform desktop environment, and provisioning scripts.

`CONTEXT.md` (repo root, ~900 lines) is the authoritative design reference — consult it before making design-level decisions. `README.MD` is the short overview.

## Architecture & Data Flow

Four largely independent components:

1. **`Minerva-Hardware/`** — KiCad 9 carrier-board project (CM5 Hirose connector, MIPI DSI, USB 3.0, PCIe/M.2, power/battery, face board). Treat as hardware artifacts; do not parse/edit KiCad files unless explicitly asked.
2. **`Project-Minerva-OS/`** — Rust workspace + Make-driven build producing an Alpine Linux 3.21 aarch64 disk image with four Rust daemons: `minerva-compositor` (DRM/fbdev, working skeleton), `minerva-shell`, `minerva-workspaced`, `minerva-inputd` (stubs). Daemons communicate over Unix sockets with newline-delimited tagged-JSON (e.g. `WorkspaceCommand`/`WorkspaceEvent` on `/run/minerva/workspaced.sock`; schema in `crates/minerva-workspaced/src/workspace.rs`).
3. **`Torchform/`** — the desktop environment (Rust + Slint + Smithay), 11-crate workspace. This is where most active development happens. Input/data flow:

```
evdev / SPI / gamepad
  → torchform-inputd (ChordDetector: chords, holds, d-pad repeat)
  → RawInput → InputMap::resolve_ctx(raw, KeybindContext) → ShellAction   (torchform-actions)
  → JSON over Unix socket
  → Shell::handle(ShellAction) → Vec<Effect>        (pure state machine, shell.rs — no Slint, no I/O)
  → dispatch_*() applies effects (audio, spawn, config save, suspend)
  → push_shell_render!(ui, shell) sets ~40 Slint properties
```

4. **`rpi-scripts/`** — POSIX shell provisioning for a physical CM5 (`setup-fresh-alpine-install.sh`) and WWAN modem management (`minerva-wwan.sh`, documented in `Manual/WWAN.md`).

Torchform shell state machine (`Torchform/crates/torchform-shell/src/shell.rs`): `Screen` (Lock → Home → App), optional `Panel` overlay (QuickSettings | Notifications | Switcher | QuickMenu), routing priority radial menu > command palette > panel > screen. `Effect` enum: Sound, LaunchExternal, ShowBanner, SaveConfig, Suspend, SaveNotes, KillApp.

## Key Directories

| Path | Purpose |
|---|---|
| `Torchform/crates/torchform-shell` | Main shell binary: `main.rs` (dispatch + render macro), `shell.rs` (state machine), `ui/*.slint` |
| `Torchform/crates/torchform-actions` | Input→action mapping lib (`ShellAction`, `InputMap`, keybinds). **No Slint dependency** |
| `Torchform/crates/torchform-config` | Config/settings/theme schema loader. **No Slint dependency** |
| `Torchform/crates/torchform-apps` | Canonical home of all 14 Slint app components (shell and standalone binaries import from here) |
| `Torchform/crates/torchform-compositor` | Smithay 0.5 Wayland compositor, dual-display; winit backend works, DRM/KMS is a stub |
| `Torchform/crates/torchform-inputd` | Input daemon: evdev/gilrs, chord detection, uinput |
| `Torchform/config/` | Dev-fallback configs: `torchform.toml`, `keybinds.toml`, `settings-schema.toml`, `themes/*.toml` |
| `Torchform/docs/` | User guide (`torchform.md`) and config reference (`torchform-config.md`) |
| `Project-Minerva-OS/crates/` | OS daemons (mostly stubs) |
| `Project-Minerva-OS/os/build.sh` | Rootfs + 4GB ext4 disk image builder (needs sudo, alpine-make-rootfs) |
| `Project-Minerva-OS/qemu/` | QEMU aarch64 launcher (direct kernel boot, cortex-a76) |
| `Minerva-Hardware/` | KiCad project: `Minerva-Carrier.kicad_pro/sch/pcb`, sub-sheets `CM5_GPIO/CM5_HighSpeed/PCIe-M2/face_board.kicad_sch` |

## Development Commands

Both Rust projects are Make-driven; each Makefile is the source of truth.

**Torchform** (`cd Torchform`):
```sh
make check          # cargo check -p torchform-shell (fast; use for iteration)
make build-shell    # debug build of shell
make build-all      # full workspace (needs libseat, libinput, libgbm, libdrm)
make run-emulator   # single window, both screens in a DS-style frame (default dev mode)
make run-standalone # two windows mirroring the physical 1920x1080 + 640x480 layout
make run-compositor # Wayland compositor on winit backend
make remote-build   # rsync + native aarch64-musl build on the device
make remote-vnc     # cage+wayvnc on device, view locally
cargo test -p torchform-shell   # unit tests (also: -p torchform-actions, -p torchform-inputd, ...)
```
Demo flags: `--demo radial|switcher|idle`, `--standalone`. Emulator keys: Space=Select, Enter=Start, Tab=L2, Esc=B, arrows=D-pad, I/J/K/L=right stick.

**Project-Minerva-OS** (`cd Project-Minerva-OS`):
```sh
make build          # cargo build --release --target aarch64-unknown-linux-musl
make image          # build disk image via os/build.sh (sudo)
make run / run-headless / run-vnc / run-kvm   # QEMU (SSH forwarded to localhost:2222)
make ssh            # into running VM
make deploy-bins    # rsync binaries only to CM5 (fast iteration; CM5_IP via .env)
```

There is no repo-wide lint config; standard `cargo fmt` / `cargo clippy` apply (VS Code workspace enables formatOnSave with rust-analyzer).

## Code Conventions & Common Patterns

- **Rust edition 2021**; error handling via `anyhow::Result` + `.context(...)` in binaries, `thiserror` for typed errors; logging via `tracing`/`tracing-subscriber` (env-filter); async via `tokio`; `serde` with tagged enums for IPC JSON.
- **Purity rule (Torchform's core invariant):** `Shell::handle(ShellAction) -> Vec<Effect>` must stay free of Slint types and I/O. Side effects go through the `Effect` enum, applied in `main.rs` dispatch functions. This keeps the state machine unit-testable.
- **No physical button names in shell logic** — only `ShellAction` variants. Button→action mapping lives in `keybinds.toml` / `torchform-actions`.
- **No Slint in `torchform-actions` or `torchform-config`** — they must compile inside daemons and launchers.
- External apps launch via `try_launch_external()` in `apps.rs`; missing binary falls back to a built-in stub component.
- Config merge priority: `~/.config/torchform/` > `/etc/torchform/` > `./config/` > built-in defaults.
- Slint design tokens are centralized in `torchform-shell/ui/tokens.slint`; app components inherit `Rectangle` and expose `in property focused-row` + `callback close-requested()`.
- Fonts: Barlow Condensed (display), DM Mono (system data), Inter (body).
- `Torchform/CLAUDE.md` is the prescriptive convention guide for that subtree — read it before touching Torchform code. `Torchform/TODO.md` tracks the 14-phase roadmap (know which phase a stub belongs to before "fixing" it).

## Important Files

- `CONTEXT.md` — authoritative design doc (hardware, boot chain, OS, DE).
- `Torchform/CLAUDE.md`, `Torchform/TODO.md` — conventions + roadmap.
- `Torchform/crates/torchform-shell/src/{main.rs,shell.rs}` — dispatch/render and state machine (largest, most central files).
- `Torchform/Cargo.toml`, `Project-Minerva-OS/Cargo.toml` — workspace roots with shared `[workspace.dependencies]`.
- `Project-Minerva-OS/crates/minerva-workspaced/src/workspace.rs` — workspace IPC protocol definition.
- `Project-Minerva-OS/Makefile`, `Torchform/Makefile` — all build/run/deploy entry points.
- `Project Minerva.code-workspace` — VS Code tasks (Build ARM64, Run QEMU, Deploy) and rust-analyzer cross-target settings.

## Runtime/Tooling Preferences

- **Rust + Cargo** everywhere; no Node/Bun/Python runtimes in the build path (Python only for a mock-input helper script).
- **Cross-compilation target: `aarch64-unknown-linux-musl`.**
  - Minerva-OS: `aarch64-linux-musl-gcc` linker (`Project-Minerva-OS/.cargo/config.toml`); devcontainer-based dev expected (`scripts/setup.sh`).
  - Torchform: clang + **mold** linker for host builds (`sudo apt install mold clang`); `cross` via `Cross.toml` + `docker/cross-aarch64-musl.Dockerfile` for device builds.
- Host-side Torchform dev runs on Linux x86_64 via Slint's winit backend; full-workspace builds need system libs (libseat, libinput, libgbm, libdrm).
- QEMU (`qemu-system-aarch64`) and `alpine-make-rootfs` required for OS image work; image build requires sudo.
- Deployment to hardware is rsync-over-SSH (`make deploy-bins`, `make remote-build`); device IP configured via gitignored `.env`.

## Testing & QA

- **Framework:** built-in Rust `#[cfg(test)]` unit tests; no integration-test harness or coverage tooling.
- Test hotspots: `torchform-shell/src/shell.rs` (state-machine behavior: unlock flows, launch, panels, radial), `torchform-actions/src/input_map.rs` (keybind resolution/round-trip), `torchform-inputd/src/chord.rs` (chord/hold/repeat timing), `torchform-run`, `torchform-config/src/dotfiles.rs`.
- Run: `cargo test -p <crate>` from `Torchform/`. `make remote-test` cross-builds and rsyncs to the device.
- Minerva-OS crates are stubs with no tests yet.
- When changing shell behavior, add/extend tests in `shell.rs`'s test module — the pure `handle()` API makes this cheap; assert on returned `Effect`s and state transitions, not rendering.
- QEMU (`make run-kvm` in Project-Minerva-OS) is the smoke-test path for OS-level changes; physical CM5 via `make deploy-bins` for hardware-dependent work (DRM, input, WWAN).
