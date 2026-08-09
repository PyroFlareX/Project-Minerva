# Torchform Device Verification

This is the field checklist for the active Torchform QuickShell runtime on Minerva. It is intentionally separate from the Rust/Slint workspace checklist: the device currently launches `~/projects/torchform-guishell/start-hdmi.sh`, while the Rust shell is developed locally and is not the active device compositor path.

## Operating assumptions

- The largest active display is the upper display.
- The smallest active display is the lower display.
- Connector names and final panel resolutions are provisional; role selection must be geometry-driven, not `HDMI-A-1`/`HDMI-A-2`-driven.
- The current portrait high-resolution panel is rotated 270° (90° landscape orientation plus a 180° flip) by the launcher; `TORCHFORM_UPPER_TRANSFORM` overrides it.
- The upper output is scaled to the QML design space (nominally 1920×1080); the lower output remains independently scaled.
- Controller input is the production path. The device smoke harness uses the same QML Gamepad plugin through a deterministic `/dev/uinput` virtual pad; `wtype` is used only to enter the terminal command payload.
- Touch is an additional input path. It is not considered hardware-verified until a touchscreen/touchpad input device is enumerated and a pointer/touch scenario passes.

## Controller vocabulary and icon reference

The menu UI now names the physical gamepad controls, not development keyboard keys:

| UI control | Torchform logical input | Menu meaning |
|---|---|---|
| `A` | South | Confirm, launch, activate |
| `B` | East | Back, close, parent |
| `X` | West | Command palette |
| `Y` | North | Radial menu |
| `D-PAD` | D-pad | Navigate and adjust |
| `L1` | L1 | Notifications |
| `R1` | R1 | Quick Settings |
| `START` | Start | Home |
| `SELECT` | Select | App Switcher |

The face-button diamond and control silhouettes are based on the standard Nintendo Switch/3DS-style reference layout. The action assignment above remains Minerva's current logical mapping; it is not silently changed to Nintendo's physical A/B positions. `gamepad-controls-base.svg` is the neutral source sheet and `gamepad-controls-teal.svg` is the Torchform recolor. The reusable `GamepadGlyph.qml` component uses the recolored vector shapes in menu hints and the lower-screen shortcut grid.

Reference images and button inventories:

- [Nintendo Switch technical specifications](https://www.nintendo.com/us/gaming-systems/switch/tech-specs/) — official controller button inventory and reference imagery.
- [Switch Button Icons and Controls](https://zacksly.itch.io/switch-button-icons-and-controls) — community visual reference for compact game UI glyph proportions; no third-party files were copied into Torchform.

## Requirements and acceptance checks

### Console and development loop

- [x] SSH host alias `Minerva` reaches the CM5 without requiring X11 forwarding.
- [x] Active source path is identified as `~/projects/torchform-guishell`.
- [x] `make hdmi-restart` syncs the tree, clears stale QuickShell/QML caches, restarts the session, and collects launcher output without compiling QML.
- [x] `make deploy-hdmi` syncs `Torchform/torchform-guishell`, not the obsolete `demo-quickshell` path.
- [x] Local and device OMP runtimes are present; the device model cache and auth metadata were synchronized without exposing credentials in logs.

### Display roles and geometry

- [x] Current live inventory observed: high-resolution `1440×2560` YDK WS-55-2K and low-resolution `800×480` Mediatrix MPI5008.
- [x] The high-resolution output is selected as upper by pixel area.
- [x] The low-resolution output is selected as lower by pixel area.
- [x] Re-running the launcher selects roles by live output geometry rather than connector names.
- [x] The portrait high-resolution output is rotated and scaled to the QML 1920×1080 logical design space.
- [x] The two outputs are arranged vertically: upper at `(0,0)`, lower immediately below upper.
- [ ] Re-running with swapped connector names has been tested on the physical IO board.
- [x] Final panel modes can change without QML source edits.

### Navigation and shell chrome

- [x] Lock screen accepts the current development unlock sequence.
- [x] Home focus follows the rendered four-column grid and dock boundaries.
- [x] A/confirm launches the focused app; B/back returns to the preceding shell state.
- [x] Home, command palette, quick settings, notifications, switcher, and radial overlays open and close through the virtual controller path.
- [x] Overlay focus is explicit: opening radial, Quick Settings/Wi-Fi, Notifications, or Switcher captures controller/keyboard focus for that overlay.
- [x] Closing a nested overlay restores the previously focused app or shell owner; state export records `focusOwner`, `focusCaptured`, and `focusEpoch`.
- [x] Overlay content, geometry, initial focus, and tile states are registry-driven in `torchform-guishell/data.js`; changes do not require QML recompilation.
- [x] Quick Settings and Notifications use geometry-scaled widths (`22%`, minimum 280/300px, maximum 420px) and responsive notification text; verified on the live `1920×1080` upper layout.
- [ ] D-pad repeat has not yet been validated with a held physical direction and release.
- [x] Lower screen mirrors time and active-app state; battery/palette/radial bindings are present.
- [ ] Touch targets exist in QML but touch behavior is not hardware-verified.

### App access

- [x] Terminal mode runs `printf TORCHFORM_TERMINAL_OK` and displays captured output.
- [x] The control helper launches the user-local Foot Wayland terminal with the required library path and confirms the child survives startup; Kitty remains an optional fallback and is still unavailable on this Alpine image.
- [x] File browser lists the real home directory and distinguishes directory/file entries.
- [ ] Empty/error directory handling has not been separately exercised.
- [x] System monitor refreshes `/proc`, memory, root-disk, temperature, uptime, and battery state without blocking the UI.
- [x] Quick commands are data-driven and return a visible palette/command surface.
- [ ] Unavailable external-app error handling has not been separately exercised.

### Power and low-battery behavior

- [x] When the device exposes no battery source, the UI reports an explicit unknown battery state instead of inventing a percentage.
- [ ] Battery percentage/charging-state reads and the ≤20% discharging treatment require a real battery telemetry source or a controlled sysfs test fixture.
- [ ] Low-battery mode remains UI-only and has not been enabled as a power policy.
- [x] Brightness/volume helpers are script-backed and can report unsupported device controls without crashing the shell.

### Touch and controller input

- [x] `torchform-virtpad` is present before QuickShell starts in smoke mode.
- [x] The smoke harness exercises the production QML Gamepad plugin with deterministic controller button/D-pad events.
- [ ] Physical controller navigation remains to be tested with the final controller wiring.
- [ ] Touchscreen/touchpad appears in `/proc/bus/input/devices`.
- [ ] Touch home/app/panel/lower-screen actions remain unverified.
- [x] Touch absence is reported as a skipped hardware check, never falsely marked pass.

### Resource headroom

- [x] The full smoke report records `free -m`, root filesystem usage, and uptime.
- [x] Post-run process check showed one `quickshell`, one `sway`, and one virtual-gamepad `python3` process; no duplicate UI session.
- [x] Normal status polling is low frequency; Sysmon refresh is 2 seconds only while the Sysmon app is active.
- [x] Screenshot artifacts are stored outside the source tree under `/tmp`.
- [x] UI remained responsive while file, Sysmon, and terminal subprocesses ran.

## Automation

Run from `Torchform/`:

```sh
make deploy-hdmi MINERVA_HOST=Minerva
make hdmi-restart MINERVA_HOST=Minerva
python3 scripts/device-smoke-test.py --host Minerva --restart
python3 scripts/capture-device-screens.py --host Minerva --output-dir /tmp/torchform-captures --label manual
```

python3 scripts/device-smoke-test.py --host Minerva --restart --scenario navigation --scenario panels
python3 scripts/device-smoke-test.py --host Minerva --restart --scenario files --scenario terminal --scenario sysmon
python3 scripts/device-smoke-test.py --host Minerva --restart --scenario overlay-focus
python3 scripts/device-smoke-test.py --host Minerva --restart --no-screenshots

The harness loads `scripts/device-scenarios.json`, restarts the DRM/Sway session in virtual-gamepad mode, sends deterministic `/dev/uinput` events, reads the QML state export, captures both outputs with `grim`, and writes a Markdown report plus screenshots under `/tmp/torchform-device-*` by default. Terminal text entry uses `wtype` only for the harmless command payload. Touch scenarios are skipped when no touch-capable input device is enumerated.

`scripts/emulate-controller.py` is the ad-hoc controller helper. It sends logical button presses to the same device-side `/dev/uinput` backend used by the smoke harness:

```sh
python3 scripts/emulate-controller.py --host Minerva list
python3 scripts/emulate-controller.py --host Minerva tap A
python3 scripts/emulate-controller.py --host Minerva hold L1 1.0
python3 scripts/emulate-controller.py --host Minerva sequence A UP RIGHT
```

The helper requires a running virtual-gamepad session. Start one with the smoke harness, use the helper for focused checks, then restart normally with `make hdmi-restart MINERVA_HOST=Minerva`.

`capture-device-screens.py` is the lightweight screenshot path: it uses the same geometry-derived upper/lower role ordering as the launcher and writes `*-upper.png`, `*-lower.png`, and `outputs.json`.

## Evidence log

| UTC date | Evidence | Result |
|---|---|---|
| 2026-08-08 | `ssh -T Minerva 'swaymsg -t get_outputs'` | Two active HDMI outputs: 1440×2560 YDK WS-55-2K and 800×480 Mediatrix MPI5008. |
| 2026-08-08 | `/proc/bus/input/devices` | `torchform-virtpad` exists; no touchscreen/touchpad input was enumerated. |
| 2026-08-08 | `configure-outputs.py` + live Sway status | Largest output selected as upper, portrait output transformed 90°, upper scaled 1.3333, lower placed below at logical y=1080. |
| 2026-08-09 | `configure-outputs.py --status` after `make hdmi-restart` | Upper YDK output transformed 270° (the requested 180° flip from its prior 90° landscape orientation), scaled 1.3333; lower remains at logical y=1080. |
| 2026-08-09 | USB Gamepad 0810:0001 raw capture + `torchform-inputd` output trace | Legacy ABS_X/Y d-pad events are normalized to d-pad buttons; the physical bottom face button is remapped to South/Confirm and unlocked Torchform. |
| 2026-08-09 | `make deploy-hdmi MINERVA_HOST=Minerva` | Synced the active `torchform-guishell` tree to `~/projects/torchform-guishell` without compiling QML. |
| 2026-08-09 | `device-smoke-test.py --restart --scenario overlay-focus` | Radial, Quick Settings/Wi-Fi, Notifications, and Switcher focus capture, navigation, close, and owner restoration passed; screenshots stored under `/tmp/torchform-overlay-final`. |
| 2026-08-09 | `device-smoke-test.py --restart --artifact-dir /tmp/torchform-final-smoke` | 44 controller/state assertions passed; touch-controls skipped because no touch-capable input was enumerated. |
| 2026-08-09 | `/tmp/torchform-overlay-final` and `/tmp/torchform-final-smoke` | Visual evidence shows focused overlay borders and controller hints on both displays; Quick Settings, Notifications, Radial, and Switcher render without obscuring the lower companion screen. |
| 2026-08-09 | Terminal smoke scenario | A/confirm runs the entered command and displays `TORCHFORM_TERMINAL_OK`; Select remains App Switcher. |
| 2026-08-09 | Post-run `free -m`, `df -h /`, `uptime`, and process inventory | 7.8 GiB RAM total / 7.1 GiB available, root filesystem 38% used, one Sway + one QuickShell session. |
| 2026-08-09 | `device-smoke-test.py --restart --scenario panels` after main-branch geometry pass | Quick Settings and Notifications controller assertions passed; live screenshots under `/tmp/torchform-main-layout-final` show expanded responsive panels and readable notification text. |
| 2026-08-09 | `torchform-control.sh launch terminal` on Minerva | User-local Foot launched under Wayland with `LD_LIBRARY_PATH`, remained alive after startup, and replaced the failing Kitty-only path. |

Update this log after every on-device smoke run. Do not call DRC/fabrication or touchscreen behavior verified from this checklist; those require direct evidence.
