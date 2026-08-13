# Torchform — Master TODO
# Cyberdeck Shell: Field-Ready Checklist

Goal: a fully self-contained Linux shell environment for the Minerva CM5 handheld.
Navigable entirely without a keyboard. OSK appears whenever text input is needed.

**Read this first.** The shipping shell on the device is the QuickShell/QML tree in
`torchform-guishell/`, launched by `start-hdmi.sh` under Sway on the DRM backend.
The Slint crates in `crates/` remain the emulator and standalone-app path. Items
written for the Slint shell that the QuickShell shell already satisfies are marked
**superseded**, with the shipping implementation named. Evidence for every `[x]`
below lives in `docs/device-verification.md`.

The end-to-end readiness and smoke-test program for shell applets, built-in
applications, external media handlers, configuration wiring, lifecycle, and
future testing skills is in `docs/applet-application-readiness-plan.md`.

Device reality that shapes this list: Alpine Linux + OpenRC + musl + `apk`
(no systemd, no journalctl, no pacman); CM5 has no suspend-to-RAM; the installed
QuickShell 0.3.0 has no `Quickshell.Services.Notifications` module.

---

## PHASE 1 — Settings App (2-pane layout)

- [x] 1A `app_settings.slint` rebuilt as a 2-pane layout (Slint/emulator path).
- [x] 1B/1C **superseded** by `torchform-guishell/SettingsView.qml`: sidebar +
      row pane, D-pad moves within a pane, `A` enters rows, `B` returns to the
      sidebar, L/R adjusts. Section and row focus live in `shell.qml`
      (`settingsSection`, `settingsRow`, `settingsPane`).
- [x] 1D Settings is the single controller/touch-first editor for schema-backed
      values: it is generated from `settings-schema.toml` (18 sections, 87 rows),
      edits toggles/sliders/selects, persists atomically to
      `~/.config/torchform/settings.conf`, applies brightness/volume to the
      device when a backend exists, and says so plainly when a value is stored
      only. Row focus survives the reload after each write.
- [ ] 1D-follow-up Rows whose change needs a service restart or elevated
      authorization are not yet flagged in the UI; only power actions report the
      required `doas` command today.
- [ ] Free-text settings rows (`text` widget) are read-only; editing them with
      the OSK is not wired.

---

## PHASE 2 — Layout & Geometry

- [x] **Superseded.** The QuickShell shell is laid out for the live geometry
      reported by `configure-outputs.py` (largest active output = upper), not for
      hardcoded 393 px HTML metrics. Home is a 4-column grid; panels, radial,
      switcher, and hint bars are verified by screenshot at 1920×1080 logical.
- [ ] Panel and list scrolling is `ListView`-based and correct, but no scroll
      indicator is drawn.

---

## PHASE 3 — QuickMenu Overlay

- [x] 3A/3B **superseded** by `torchform-guishell/QuickMenu.qml`: a data-driven
      power overlay (`data.js → overlayConfig.quickMenu`) with Lock, End session,
      Reboot, and Power Off. D-pad selects, `A` activates, `B` closes.
- [x] Destructive entries require a second `A` to confirm; reboot/power off
      report the exact `doas` command when passwordless doas is unavailable.
- [x] Reachable from the command palette (`sys.power`) and from the
      `power_menu` chord published by `torchform-inputd`.

---

## PHASE 4 — Input Context Wiring

- [x] 4A **superseded**: the QuickShell shell resolves context itself —
      app-local buttons only override the global palette/radial bindings inside
      the apps whose hint bar advertises them.
- [x] 4B `torchform-inputd` loads `input.toml`, resolves chords/holds, and
      publishes the action manifest the QML `Gamepad` plugin reads
      (`$XDG_RUNTIME_DIR/torchform/inputd-actions.json`).
- [ ] Chord actions are not exercised by the smoke suite: the virtual-gamepad
      test backend emits buttons and axes, not daemon-resolved chords.

---

## PHASE 5 — Live System State

- [x] 5A Live clock on a 1 s timer, mirrored to both displays.
- [x] 5B Brightness through `torchform-control.sh brightness-step` and the
      `display.brightness` setting; reports when no writable backlight exists.
- [x] 5C Volume through `amixer`/`pactl` with the same honest fallback.
- [x] 5D Battery, load, memory, disk, temperature, and uptime sampled from
      `/proc` and `/sys` by the `sysmon` helper; the UI shows an explicit
      unknown battery state when the device exposes no battery.

---

## PHASE 6 — OSK Full Integration

- [x] 6A One text-target router in `shell.qml` (`textTarget` +
      `activeText()`/`applyText()`) feeds the palette, Wi-Fi passphrase,
      Bluetooth PIN, note body, and package search from the lower keyboard.
- [x] 6B Opening any text sink shows the lower OSK; `B` closes it and returns
      the target to the palette.
- [x] 6C The upper hint bar shows the per-app and per-overlay bindings,
      including which button opens the keyboard.

---

## PHASE 7 — App Backends

- [ ] 7A Terminal: the built-in app is a command runner (`terminal-exec`), not a
      PTY. Interactive work uses the external terminal (foot) through the
      external-app runner. **A real gamepad-driven shell is Phase 15.**
- [x] 7B Browser: Chromium runs as an external Wayland client through the
      external-app runner, visible full-screen and closable from the controller.
      The in-shell HTML stub renderer was dropped as dead weight.
- [x] 7C Files: real `readdir` with type icons, bookmarks, `A` opens, `B` goes
      up, D-pad and analogue-stick navigation, and touch rows.
- [x] 7D Notes: Markdown files under `~/.local/share/torchform/notes`; list,
      open, create (`X`), delete (`Y`), OSK editing, atomic save on `B`.
- [x] 7E Sysmon: live `/proc` sampling with history, on a 2 s timer while open.
- [x] 7F Logview **re-targeted to Alpine**: `/var/log/messages`, `dmesg`, and the
      Torchform session logs, with L1/R1 switching source. There is no
      `journalctl` on this image.
- [x] 7G Pkgman **re-targeted to apk**: `apk info -v` list, `apk info -a`
      details, OSK search filter.
- [ ] 7G-follow-up Install/remove is deliberately absent — it needs root; wire it
      only behind an explicit authorization flow.
- [ ] Email, SMS, and Phone remain stubs (no backend on this device).

---

## PHASE 8 — Network & Bluetooth

- [x] 8A Wi-Fi panel: scan (`Y`), list with signal and security, connect with an
      OSK passphrase, and visible errors when the backend is unavailable.
- [x] 8B Bluetooth panel: scan, list, pair with an OSK PIN, connect.
- [x] 8C Both panels report the real backend state — including "BlueZ is not
      running" and "Wi-Fi scan needs iwd/wpa_supplicant control" — instead of
      optimistic UI-only toggles.
- [ ] 8A/8B remain unproven end-to-end on this image: `iwctl` is absent (the `iw`
      fallback is read-only) and the BlueZ service is not enabled.
- [ ] 8D SIM/WWAN manager (ModemManager + NetworkManager): discovery, SIM/PIN,
      operator, registration, signal, APN, connect/disconnect, roaming, usage,
      recovery. Keep raw AT commands in a privileged diagnostics path.
- [ ] 8E WWAN power/privacy: airplane/radio kill, modem reset, explicit
      data-cost/roaming confirmation.

---

## PHASE 9 — Process & Workspace Management

- [x] 9A The switcher lists the apps actually opened this session, newest first,
      with `X` to close one; the external Wayland client is tracked separately
      (`externalApp`) and terminated by `B`/Home.
- [ ] 9A-follow-up Built-in apps are in-process, so there are no PIDs or run
      times to show; only the external client has a real process.
- [ ] 9B Workspace persistence and the WorkspaceNext chord.

---

## PHASE 10 — Notifications

- [x] 10A-partial Local programs post notifications with `torchform-notify`; the
      shell polls them every 5 s, banners only genuinely new entries, and merges
      them above the sample entries in the panel.
- [ ] 10A A real `org.freedesktop.Notifications` server is blocked: QuickShell
      0.3.0 on this device is built without `Quickshell.Services.Notifications`.
      Either rebuild QuickShell with that module or run a sidecar daemon that
      owns the name and writes to the same intake file.
- [x] 10B `X` dismisses the focused live notification from the panel.
- [ ] 10B-follow-up Swipe-to-dismiss needs a touchscreen, which is not
      enumerated on this device.

---

## PHASE 11 — Lower Screen Polish

- [x] 11A Live time, battery, active app, and low-battery strip.
- [ ] 11B Radial touch targets on the lower screen.
- [x] 11C Per-app context line: Files path, last terminal command, note title,
      log source and line count, package count and query, sysmon load/memory,
      or the active settings section.

---

## PHASE 12 — Hardware Input Daemon

- [x] 12A `torchform-inputd` enumerates evdev devices and normalizes any
      detected controller into one `torchform-virtpad` uinput device.
- [ ] 12B Cirque GlidePoint SPI: real PINNACLE register sequence and tap
      synthesis. No trackpad is attached to the current bring-up hardware.

---

## PHASE 13 — Compositor

- [x] **Superseded for the device.** Sway on the DRM backend hosts QuickShell
      layer-shell surfaces; external apps map as ordinary toplevels while the
      shell drops to `WlrLayer.Bottom`. `torchform-compositor` stays a
      development experiment.
- [ ] 13A/13B remain open only if Torchform ever replaces Sway.

---

## PHASE 14 — Quality & Shipping

- [x] 14A `cargo clippy --workspace --all-targets -- -D warnings` is clean.
- [x] 14B `cargo test --workspace` is green (42 tests: shell 16, inputd 13,
      run 6, actions 4, config 3).
- [x] 14C Emulator smoke checklist **superseded** by the device harness:
      `scripts/device-smoke-test.py` drives the production QML through the
      virtual gamepad. 16 scenarios, 0 assertion failures; `touch-controls`
      skips because no touch device is enumerated.
- [x] 14D Service units **re-targeted to OpenRC**: `packaging/openrc/`
      (`torchform-inputd`, `torchform-session`) with README and exact `doas`
      install commands.
- [ ] 14D-follow-up The OpenRC services have not been installed or boot-tested
      on Minerva; that needs an interactive `doas` session.
- [x] 14E Font provisioning: `packaging/install-fonts.sh` (+ `make install-fonts`,
      `check-fonts`, `remote-install-fonts`). Barlow Condensed, Inter, JetBrains
      Mono, and DM Mono are installed on Minerva and the shell renders with them.
- [ ] `cargo fmt --all -- --check` is not clean; the workspace has broad
      pre-existing formatting drift. Reformat in one dedicated commit.

---

## PHASE 15 — Gamepad Shell (GPSH-SDS-001)

**Why:** the built-in terminal is a one-shot command runner, and an external
terminal needs a keyboard the handheld does not have. `Gamepad-Shell-Plan.md`
specifies the replacement: an application that owns a real PTY, runs bash/zsh
below it, and lets the operator build commands by *selection* instead of
spelling. Read that document before starting; the summary below is the task
breakdown, not a substitute.

Design decisions already fixed by the plan: Option B (TUI front end over a PTY)
with the Option C command model; the operator edits an AST, not a string; two
input layers (physical event → Action → state change); and a pure
`update(state, event) -> (new_state, effects)` core with no I/O.

- [ ] 15A **M0 skeleton.** Cargo workspace `gpsh/` with `gpsh-core` (no I/O),
      `gpsh-input`, `gpsh-pty`, `gpsh-ui`, `gpsh-catalog`, and the binary.
      Event loop, `portable-pty` session running the operator's shell, `vte`
      parser, and a raw terminal view. Frame coalescing at 30 fps.
- [ ] 15B **M1 catalog.** `PATH` scan grouped by source directory, cached index,
      fuzzy filter (`nucleo`), shoulder buttons switch groups. FR-01…FR-05.
- [ ] 15C **M2 draft.** Token/Redirect/Node/Pipeline model, token-strip UI,
      correct POSIX/zsh quoting, dangerous-command detector, explicit Run.
      FR-09…FR-13.
- [ ] 15D **M3 paths and pipes.** Gamepad file browser and the connector menu
      (`|`, `>`, `>>`, `<`, `2>`, `2>&1`, `&&`, `;`). FR-07, FR-08.
      *M0–M3 is the minimum usable product and satisfies the Section 2.3
      criterion: build `ls -la /var/log | grep err > out.txt` in under 20 s
      without the OSK.*
- [ ] 15E **M4 text.** OSK integration for free text only, search, suggestion
      row. FR-04, FR-24.
- [ ] 15F **M5 environment and safety.** Variable editor and the confirmation
      dialog. FR-17, FR-18, FR-13.
- [ ] 15G **M6 specifications.** Flag menus from `--help` parsing plus the
      bundled specification files. FR-06.
- [ ] 15H **M7 scripts.** Save a draft as a named script, list saved scripts in
      the catalog, parameters, export. FR-19, FR-20.
- [ ] 15I **M8 polish.** Remap file, theme, framebuffer backend, packaging as one
      static binary. FR-22, NFR-09.
- [ ] 15J **Torchform integration.** Launch `gpsh` as the Terminal app through
      the external-app runner (foot hosts it until the framebuffer backend
      exists), feed it the `torchform-virtpad` device, and add a device smoke
      scenario that builds and runs a pipeline with the controller only.
- [ ] 15K **Decide the language before M2** with the rule in plan §8.8. Rust is
      the default for this target; C++20 only if a vendor BSP or a bare-TTY v1
      forces it.

---

## Deferred / Future

- Full keybind rebind UI (listen-mode row in Settings → Input)
- Dotfile editor (parsed TOML/YAML into a structured editor view)
- Split-screen tiling (two apps side by side)
- Phone / SMS / Email backends (need the cellular modem and a SIM)
- Camera (v4l2 capture)
- Media player backend (mpv IPC socket) — playback works today by launching mpv
- NFC/QR code reader
- Touch verification for every `MouseArea` once a touchscreen is enumerated
