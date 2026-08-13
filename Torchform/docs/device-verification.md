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
- [x] `make hdmi-restart` performs the sync, restart, live-output query, and launcher-log collection without compiling QML.
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
- [ ] D-pad repeat has not yet been validated with a held physical direction and release.
- [x] Lower screen mirrors time and active-app state; battery/palette/radial bindings are present.
- [ ] Touch targets exist in QML but touch behavior is not hardware-verified.

### App access

- [x] Terminal mode runs `printf TORCHFORM_TERMINAL_OK` and displays captured output.
- [x] The Terminal app's `Terminal App` button launches the first available Wayland terminal (foot, then alacritty, then kitty) through the external runner; foot maps full-screen on the upper display and `B` closes it with a `terminal closed` banner.
- [ ] Kitty remains unusable on this image: the user-local `kitty-wayland` backend creates a Wayland surface then exits, and its log reports missing `libsystemd.so` and no render frame. foot is the working terminal.
- [x] File browser lists the real home directory and distinguishes directory/file entries.
- [ ] Empty/error directory handling has not been separately exercised.
- [x] System monitor refreshes `/proc`, memory, root-disk, temperature, uptime, and battery state without blocking the UI.
- [x] Quick commands are data-driven and return a visible palette/command surface.
- [x] Media Center is controller-navigable and data-driven: Chromium for web, the built-in Files browser for selection, mpv for video/audio, imv for images, and KOReader for ebooks/PDFs.
- [x] File activation routes supported extensions through `torchform-control.sh media-open`; unknown extensions return an explicit visible error.
- [x] External Wayland apps run in the foreground of `torchform-control.sh` so QuickShell owns their lifetime. While one is mapped the upper layer-shell surface drops to `WlrLayer.Bottom` and releases keyboard focus, so the app is actually visible and interactive; `B` (or Home) terminates it and restores the shell.
- [x] The launcher focuses the upper output before exec, so a new toplevel maps on the main display instead of the small companion screen that owns the focused workspace.
- [x] Real media content was qualified end-to-end on device: a JPEG/PNG in `imv`, an MP4 in `mpv`, and Chromium, each visible full-screen and closed from the controller.
- [x] Unavailable handlers surface explicit errors: an unsupported extension shows `No media handler for .<ext>`, a missing file shows `Media file not found`, and an external app that dies on its own reports `exited unexpectedly (code N)`.

### Notes, logs, packages, settings, and power

- [x] Notes reads and writes Markdown files under `~/.local/share/torchform/notes`; the lower keyboard edits the body and `B` saves atomically through `notes-write`.
- [x] Logview reads the sources that exist on this image — `/var/log/messages`, `dmesg`, and the Torchform session logs. There is no `journalctl` on Alpine/OpenRC.
- [x] Pkgman lists installed `apk` packages and shows `apk info -a` details; install/remove is deliberately absent because it needs root.
- [x] Settings is a two-pane editor generated from `settings-schema.toml` (18 sections, 87 rows). Toggles, sliders, and selects persist to `~/.config/torchform/settings.conf` through an atomic write, and the cursor survives the reload after each write.
- [x] Brightness and volume settings apply to the device when a backlight or mixer exists and otherwise report that the value was only stored.
- [x] The power menu is data-driven, and every destructive entry needs a second `A` to confirm. Reboot/power off report the exact `doas` command when passwordless doas is unavailable, and Sleep states plainly that this board has no suspend-to-RAM.
- [x] The app switcher lists the apps actually opened in this session, newest first; `X` closes one and leaves the app screen if it was active.
- [x] Local programs can post notifications with `torchform-notify`; the shell polls them, banners only genuinely new entries, and `X` dismisses one from the panel.
- [ ] Torchform does not own `org.freedesktop.Notifications`: this QuickShell build (0.3.0) ships no `Quickshell.Services.Notifications` module, so DBus notifications from third-party apps are not received.
- [ ] `apk` install/remove, and any settings row whose backend is missing, remain read-only.

### File manager choice

- [x] The active file manager is Torchform's native `FilesView`: it already routes D-pad/A/B through the shell state machine and uses QML `MouseArea`/`ListView` interaction for touch.
- [x] Each file row gives the tapped item focus before activation; the list is touch-scrollable and stops cleanly at its bounds.
- [x] MauiKit Index was reviewed as a visual candidate. Its official source documents desktop/mobile support and Qt key forwarding, but Alpine has no `index-fm`/MauiKit package and its documented Qt 5/KDE build stack is not a low-risk CM5 deployment.
- [x] CoreFM was tested from the Alpine package repository. It is lightweight and Qt 6 based, but it is a native external window with no gamepad mapping; QuickShell's full-screen layer hides it, so it is not the active choice.
- [ ] Hardware touch behavior remains unverified until a touchscreen input device is enumerated.


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

### GTK/Qt application input

- [x] A temporary bridge read `torchform-virtpad` with `evdev` and emitted ordinary keyboard events through a separate `/dev/uinput` device.
- [x] GTK 4 Demo accepted D-pad keyboard events: `DOWN DOWN A` moved its sidebar selection and ran the selected example.
- [x] Qt FeatherPad accepted the same bridge; `X` was mapped to `KEY_A` and inserted `a` into the editor.
- [ ] Production routing must be focus-aware. A global bridge would otherwise deliver the same controller action to both Torchform and the focused application.
- [ ] The external-window visibility/focus policy must be solved separately; QuickShell currently covers native external windows.


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
python3 scripts/device-smoke-test.py --host Minerva --restart --scenario media-routing
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
| 2026-08-09 | Temporary evdev/uinput keyboard bridge + GTK 4 Demo | `DOWN DOWN A` moved the GTK sidebar selection and ran the selected example through the normal Wayland keyboard path. |
| 2026-08-09 | Temporary evdev/uinput keyboard bridge + Qt FeatherPad | A controller `X` mapped to `KEY_A` inserted `a` into the focused Qt editor. |
| 2026-08-09 | Remapping cleanup and `make hdmi-restart MINERVA_HOST=Minerva` | Temporary packages, bridge, test apps, and test virtual pad were removed; production Torchform inputd, Sway, and QuickShell were restored. |
| 2026-08-09 | `make deploy-hdmi MINERVA_HOST=Minerva` | Synced the active `torchform-guishell` tree to `~/projects/torchform-guishell` without compiling QML. |
| 2026-08-09 | `device-smoke-test.py --restart --scenario overlay-focus` | Radial, Quick Settings/Wi-Fi, Notifications, and Switcher focus capture, navigation, close, and owner restoration passed; screenshots stored under `/tmp/torchform-overlay-final`. |
| 2026-08-09 | `device-smoke-test.py --restart --artifact-dir /tmp/torchform-final-smoke` | 44 controller/state assertions passed; touch-controls skipped because no touch-capable input was enumerated. |
| 2026-08-09 | `/tmp/torchform-overlay-final` and `/tmp/torchform-final-smoke` | Visual evidence shows focused overlay borders and controller hints on both displays; Quick Settings, Notifications, Radial, and Switcher render without obscuring the lower companion screen. |
| 2026-08-09 | Terminal smoke scenario | A/confirm runs the entered command and displays `TORCHFORM_TERMINAL_OK`; Select remains App Switcher. |
| 2026-08-09 | `device-smoke-test.py --restart --scenario media-routing` | Media Center focus and Files handoff passed; state export recorded `mediaFocus: 0`; handler smoke checks launched Chromium, imv, mpv, and KOReader with user-local libraries. |
| 2026-08-09 | Media handler process inventory and cleanup | Browser/image/ebook subprocesses were started and terminated cleanly; extracted user-local media runtime is approximately 1.0 GiB and redundant APK archives were removed. |
| 2026-08-09 | CoreFM Alpine package smoke launch | External Qt window was hidden behind the full-screen QuickShell layer; package removed after the test. Native FilesView remains the controller/touch integration point. |
| 2026-08-09 | `device-smoke-test.py --restart --scenario files` after FilesView touch update | Home → Files → first-row focus and next-row navigation passed; screenshot shows full-width selectable file rows and controller hints. |
| 2026-08-09 | Post-run `free -m`, `df -h /`, `uptime`, and process inventory | 7.8 GiB RAM total / 7.1 GiB available, root filesystem 38% used, one Sway + one QuickShell session. |

| 2026-08-09 | `make hdmi-restart MINERVA_HOST=Minerva` after the lower-screen OSK and radio-panel changes | Production QuickShell loaded the synchronized QML tree; geometry classified HDMI-A-1 YDK WS-55-2K as upper (logical 1920×1080) and HDMI-A-2 Mediatrix MPI5008 as lower (800×480). |
| 2026-08-09 | Synthetic Wayland pointer click on the lower display OSK button and key | Lower OSK opened on the 800×480 companion screen, accepted a tapped `q`, and updated the upper command-palette query; this is not physical touchscreen evidence. |
| 2026-08-09 | Controller smoke path: Quick Settings → Wi-Fi | Wi-Fi panel opened through D-pad/A; the `iw` fallback reported the active network and signal data without recording its SSID. |
| 2026-08-09 | Controller smoke path: Quick Settings → Bluetooth | Bluetooth panel opened and reported the actionable unavailable-service state because BlueZ is not running; no pairing claim was made. |
| 2026-08-09 | Final production `free -m`, `df -h /`, `uptime`, and process inventory | 7.8 GiB RAM total / 7.1 GiB available, root filesystem 38% used, and one production Sway + QuickShell + inputd session with no virtual test backend. |
| 2026-08-09 | Controller smoke path: Wi-Fi scan (`Y`) | Wi-Fi scan action reached the panel and reported that `iw`/`wpa_supplicant`/elevated `iw` access is unavailable; the active network remained visible. |
| 2026-08-09 | Controller smoke path: Bluetooth scan (`Y`) | Bluetooth scan action reached the panel and displayed the explicit scan-start state; pairing/device discovery still requires the BlueZ service. |
| 2026-08-09 | Controller smoke path: Search and radial | Search opened with the lower-display OSK and D-pad focus moved across command results; radial opened with descriptive destination text and navigated across system actions. |
| 2026-08-09 | Files controller regression reproduction | D-pad taps changed the shell focus state but the Files delegate remained visually stuck on the first row; held D-pad repeat was also disabled by the `appMode` guard, and analogue axes had no QML navigation handler. |
| 2026-08-09 | `device-smoke-test.py --restart --scenario files` after controller-navigation fix | D-pad and left-stick navigation passed; final screenshots show the second row highlighted after D-pad input and the fifth row highlighted after analogue input. Held D-pad repeat advanced through multiple file rows. |
| 2026-08-09 | Media launch regression reproduction | Selecting a media file started `imv`/`mpv` (visible in the Sway tree) but nothing appeared: the client mapped on the small companion output and the shell's full-screen `WlrLayer.Overlay` surface covered both displays. |
| 2026-08-09 | Controller path: Media → Choose Media File → image | `imv` filled the upper display, the companion screen showed `RUNNING GOOD_HEADSHOT.JPG · B CLOSES IT`, and `B` terminated it and restored the Files view with focus intact. |
| 2026-08-09 | Controller path: Files → LOGH episode 001 (`.mp4`) | `mpv` played full-screen on the upper display and `B` closed it; state export recorded `externalRunning` true then false. |
| 2026-08-09 | Controller path: Media → Web Browser | Chromium mapped full-screen on the upper display through the same external runner and closed cleanly from the controller. |
| 2026-08-09 | Controller path: unsupported file (`sway-headless.conf`) | Banner reported `No media handler for .conf`, no external process started, and Files focus stayed on the selected row. |
| 2026-08-09 | Keyboard-focus reclaim after external exit | Before the fix, `wtype` text no longer reached the shell once an external app had run (Sway kept focus on the dead toplevel's workspace); the shell now claims exclusive keyboard focus for 400 ms on exit and the terminal scenario passes again. |
| 2026-08-09 | `device-smoke-test.py --restart` (full suite) | 0 assertion failures across navigation, quick-commands, panels, radial, files, media-routing, media-open, terminal, sysmon, and overlay-focus; touch-controls skipped because no touch-capable input is enumerated. |
| 2026-08-09 | Terminal app external launch (synthetic pointer click on `Terminal App`) | foot mapped full-screen on the upper display through the external runner; `B` terminated it, the shell returned to the Terminal view, and the banner read `terminal closed`. |
| 2026-08-12 | Notes app on device | `Scratch.md` opened from disk, the lower keyboard appended characters through the shared text-target router, and `B` wrote the file back: `hello from torchformqw`. |
| 2026-08-12 | Logview on device | `system` source returned 200 lines from `/var/log/messages`; `R1` switched to `kernel` and returned 200 lines of `dmesg`. |
| 2026-08-12 | Pkgman on device | 581 installed apk packages listed; `A` showed `apk info -a alpine-baselayout` details and `B` returned to the list. |
| 2026-08-12 | Settings editor on device | 18 sections and the DISPLAY rows rendered from `settings-schema.toml`; a toggle and a select persisted to `~/.config/torchform/settings.conf` (`display.refresh_rate=120 Hz`) and the row cursor stayed put across the reload. |
| 2026-08-12 | Power menu on device | Opened from the command palette, `A` on Reboot armed the confirm state without acting, and `B` closed it. |
| 2026-08-12 | Notification intake on device | `torchform-notify "Sysmon" "Disk check finished" …` appeared in the panel within one poll, the banner announced it once, and `X` dismissed it (4 entries → 3). |
| 2026-08-12 | Companion-screen app context | Lower display showed `Files` with the live path represented as `$HOME` while the Files app was active. |
| 2026-08-12 | `device-smoke-test.py --restart` (full suite, 16 scenarios) | 0 assertion failures including the new notes, logview, pkgman, settings, quick-menu, and notifications scenarios; touch-controls skipped because no touch-capable input is enumerated. |

Update this log after every on-device smoke run. Do not call DRC/fabrication or touchscreen behavior verified from this checklist; those require direct evidence.
