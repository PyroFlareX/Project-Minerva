# Torchform Applet and Application Readiness Plan

## Goal

Make every shipping Torchform applet and application operable on Minerva from a cold boot to a clean shutdown using the physical input grammar: controller first, lower-screen touch where hardware exists, and the lower-screen OSK for text. A surface is not ready merely because it renders or launches. It is ready only when its controls, focus handoffs, dependent applets, configuration source, Settings integration, app switching, close path, failure path, and restart behavior are exercised on the shipping QuickShell/QML stack.

This plan targets the implementation that actually ships on Minerva:

- `torchform-guishell/start-hdmi.sh` starts input first, then Sway, derives upper/lower display roles from live geometry, and finally starts QuickShell.
- `torchform-guishell/shell.qml` owns app, overlay, OSK, switcher, and external-process state.
- `torchform-guishell/data.js` is the built-in app and overlay registry.
- `torchform-guishell/torchform-control.sh` supplies file, media, settings, radio, notes, logs, package, notification, power, and external-launch backends.
- `scripts/device-smoke-test.py` and `scripts/device-scenarios.json` are the current device harness and scenario catalog.
- `config/settings-schema.toml` is the Settings UI schema. The live store is `${XDG_CONFIG_HOME:-$HOME/.config}/torchform/settings.conf`.
- `~/.config/torchform/input.toml` is the production input-daemon configuration installed on first start when absent.

The older Slint crates remain emulator and standalone-app paths. They do not substitute for a pass on the shipping QuickShell/QML device path.

## Minerva requirements carried into the gate

The plan preserves the constraints in `CONTEXT.md` sections 18 and 19:

- Every interactive element is reachable with D-pad navigation.
- Text input uses the lower OSK, voice, or a connected keyboard; no app may silently require a desktop keyboard.
- Controls use sliders, toggles, and enumeration pickers rather than mouse-only dropdowns.
- The upper display is the primary full-screen viewport; the lower display has an explicit contextual role.
- App switching is controller-accessible.
- App-specific and system actions do not steal each other's input context.

Live geometry decides which output is upper or lower. Tests must never assume an HDMI connector name.

## Definitions

**Applet:** a shell-owned temporary or contextual surface. This includes Command Palette, Radial Menu, Quick Settings, Notifications, App Switcher, Quick Menu, Wi-Fi, Bluetooth, the lower OSK, control hints, and lower-screen context/actions.

**Built-in application:** an in-process QML surface selected from `data.js`, including Media, Settings, Sysmon, Pkgman, Logview, Notes, Terminal, Files, and the current Email/SMS/Phone placeholders.

**External application:** an ordinary Wayland client owned by QuickShell's foreground `Process`, currently including browser, terminal/file-manager launch helpers and media handlers such as mpv, imv, KOReader, and Chromium.

**Dependency activation:** one surface opening another required surface without losing state. Examples: Media opens Files; Wi-Fi and Bluetooth open the OSK; Notes and package search open the OSK; Files opens a media handler; an external app exits back to Files; Settings opens an action editor.

## Definition of ready

Every applet or app must pass all applicable gates below. “Not applicable” requires a reason in the coverage report.

1. **Registration:** it is present in the runtime registry, launcher, palette, quick action, or documented parent surface exactly once.
2. **Cold start:** it works after a fresh production-style session, not only after another app initialized shared state.
3. **Input:** every advertised controller action causes an observable state change. D-pad, A, B, shoulders, chords/holds, analogue repeat, and touch are covered where the surface advertises them.
4. **Focus:** focus starts on a valid control, stays visible while navigating and scrolling, follows overlay priority, and returns to the exact owning surface after a child applet closes.
5. **Dependent surfaces:** OSK, Files, radio panels, confirmation dialogs, and external handlers open with the right context and return without losing the parent state.
6. **Lifecycle:** open, background/home, switch back, close, reopen, and unexpected child-process exit all reach deterministic states. Only one external client may own the upper display at a time unless a future workspace design explicitly changes that rule.
7. **Configuration:** the effective config file and precedence are recorded; the runtime demonstrably reads the intended value; malformed, missing, and unwritable config paths produce a visible error or documented default.
8. **Settings integration:** every user-adjustable app/applet option appears in Settings, shows the effective value, writes the authoritative store or generated native config, applies live or clearly says “restart required,” and survives a session restart.
9. **Failure behavior:** absent service, absent binary, unsupported file, missing permission, bad data, and backend timeout never look like success and never strand focus.
10. **Dual-display behavior:** upper content, lower context, OSK, hints, and external-app handoff are correct on geometry-derived roles. Screenshots of both displays are evidence.
11. **Shutdown and recovery:** normal app close, End Session, compositor exit, and session restart leave no orphan app, stale virtual input backend, stale socket, or duplicate Sway/QuickShell/inputd process.
12. **Evidence:** state assertions, process/file assertions, both-display screenshots for visual transitions, relevant logs, and a machine-readable report are retained per run.

## Current baseline and known coverage gaps

The current scenario catalog contains 17 scenarios: navigation, quick commands, panels, radial, files, media routing, media open, terminal, sysmon, overlay focus, notes, logview, pkgman, settings, quick menu, notifications, and touch controls.

That baseline already exercises substantial shell behavior, but it does not yet prove full applet/app readiness:

- `media-open` proves a PNG can open visibly and close back to Files. It does not exercise video, audio, ebook/PDF, HTML, or player controls.
- While an external client owns the display, `shell.qml` currently handles only B to close and Start/Mode to close-and-go-home. Playback, paging, zoom, browser navigation, and other app controls need explicit routing and tests.
- The smoke backend emits buttons and axes but not the daemon-resolved chord/hold actions from `input.toml`.
- OpenRC units exist, but installation, boot start, dependency ordering, stop, and reboot recovery have not been device-tested.
- Touch is currently skipped because no touchscreen input device is enumerated; synthetic pointer evidence must remain labeled synthetic.
- Settings text rows are read-only. In particular, `apps.terminal`, `apps.browser`, `apps.editor`, and `apps.media` appear in the schema but do not currently select the binaries used by `torchform-control.sh`.
- Most settings are stored in `settings.conf` without a runtime backend. Only values with a real consumer may be called working.
- Wi-Fi has a read-only `iw` fallback and Bluetooth lacks a running BlueZ service on the current image, so connect/pair cannot yet pass end to end.
- Email, SMS, and Phone remain placeholders and must be reported as such rather than counted ready.

## Work plan

### Phase A — Build a complete runtime inventory

1. Export an introspection record from `shell.qml` into the smoke state containing:
   - registered grid and dock apps;
   - registered applets and nested applets;
   - palette commands and quick actions;
   - app-specific hint actions;
   - active config paths and schema version;
   - available external handlers and binaries.
2. Have the harness compare that runtime record with scenario coverage. A new app, applet, setting section, handler class, or advertised control without a mapped test must fail coverage review.
3. Keep launch commands and UI labels in their existing runtime sources. The test inventory may map runtime IDs to scenarios, dependencies, and expected settings keys, but must not become a second launcher registry.
4. Classify each item as `ready`, `degraded`, `blocked-hardware`, `placeholder`, or `uncovered`. A placeholder is never a pass.

**Exit gate:** one generated coverage report accounts for every app, applet, command, advertised control, dependency, and settings section found at runtime.

### Phase B — Extend the harness before adding more scenarios

Add deterministic actions and assertions to `device-smoke-test.py` rather than encoding timing guesses into long button sequences:

- Fixture actions to create per-run directories and representative text, image, audio, video, PDF/ebook, HTML, unsupported, and missing files.
- Process assertions for exact executable, process count, start, exit, and orphan detection.
- Sway-tree assertions for toplevel output, visibility, focus, and disappearance after close.
- File assertions for persisted settings, native app config, notes, notifications, and cleanup.
- Log assertions for QuickShell QML warnings, inputd failures, helper errors, and compositor errors.
- Config-path assertions that record which schema, input config, settings store, and native app config were selected.
- Wait conditions based on state/process/socket changes instead of fixed sleeps wherever possible.
- Held-button and daemon-action support so repeat, long press, and configured chords exercise the production inputd path as well as the direct virtual-gamepad path.
- A destructive-action guard: reboot/poweroff scenarios run only under an explicit harness flag and use a post-boot reconnect check.
- Automatic production restoration in a `finally` path, followed by process and log verification.

Use a per-run fixture root and never depend on a user's Pictures, Downloads, notes, or existing settings. Back up and restore any production config that cannot yet be redirected through XDG paths.

**Exit gate:** harness self-test detects a deliberately missing process, stale state file, wrong output, config mismatch, and QML warning; failed setup still restores production mode.

### Phase C — Prove shell and applet lifecycle

Create focused scenarios for the following matrix.

| Surface | Required smoke path | Required assertions |
|---|---|---|
| Lock/Home | cold start, unlock, relock, wrong/partial PIN, return Home | input accepted only in valid context; no previous app name leaks on Lock; Home focus resets predictably |
| Command Palette | open globally, filter with lower OSK, navigate, launch app/action, cancel | OSK target is `palette`; focused result remains visible; close restores prior owner |
| Radial Menu | hold/release path, D-pad path, each enabled destination, cancel | configured hold/chord works; action matches highlighted item; parent focus restored |
| Quick Settings | open, navigate sliders/tiles, activate Wi-Fi/Bluetooth, close | value/action reaches backend; nested panel returns to Quick Settings row |
| Notifications | ingest live notification, open, navigate, dismiss, empty state | only new entries banner; persisted intake changes; focus remains valid after deletion |
| App Switcher | populate with two built-ins, switch in both directions, close inactive and active entry | newest-first list; selected app restores; closing active app goes Home; no duplicate entries |
| Quick Menu | open through palette and configured chord, cancel confirmation, End Session | destructive second-confirm enforced; cancel is harmless; session stop cleans children |
| Wi-Fi | unavailable, scan, open secured network, OSK passphrase, connect, cancel | backend truth shown; password stays in target; success requires real connected state |
| Bluetooth | unavailable, scan, select, OSK PIN, pair/connect, cancel | backend truth shown; success requires paired/connected state; scan stops on exit |
| Lower OSK | open from every text target, D-pad/type/backspace/submit/cancel, touch when available | correct target only; text preserved or discarded by contract; parent focus restored |
| Lower panel and hints | Home, each app, each overlay, external client | active app/context and controls match actual current routing; no stale labels |
| Touch surfaces | every `MouseArea` once hardware exists | touch reaches same state transition as controller and does not break controller focus |

Run overlay-priority permutations, not just isolated opens: OSK over palette, OSK over Wi-Fi/Bluetooth, nested radio panel over Quick Settings, notification/switcher/radial attempts while another exclusive overlay is open, and Home/B behavior from each depth.

**Exit gate:** every applet passes its applicable readiness gates through real controller input; touch remains explicitly blocked rather than silently passed until hardware is enumerated.

### Phase D — Prove built-in application lifecycle

For every built-in app, use the same lifecycle spine before app-specific checks:

1. Launch from Home.
2. Launch from Command Palette where registered.
3. Navigate first, middle, last, empty, loading, and error states.
4. Activate each advertised action.
5. Open and close every dependent applet.
6. Go Home without deleting session state.
7. Launch a second app; use App Switcher to return to the first.
8. Close the inactive app, then the active app.
9. Reopen and verify the documented persistence/reset behavior.
10. Restart the session and verify durable data/config only; ephemeral focus and process state must reset.

| App | App-specific proof |
|---|---|
| Files | empty/large directory, hidden entries, parent traversal, unreadable path, D-pad, analogue and held-repeat navigation, touch, supported/unsupported activation, file-selector return contract |
| Media | every launcher tile; Media-to-Files handoff; image, audio, video, ebook/PDF, and HTML fixtures; missing handler and unsupported extension |
| Settings | all 18 sections; every widget type; scroll/focus bounds; persistence; live apply; restart-required and authorization labels; reset defaults; malformed schema/store errors |
| Notes | list, create, OSK edit, atomic save, reopen, delete, filename/path safety, empty state and write failure |
| Sysmon | repeated samples, unknown battery, missing optional `/sys` values, bounded history, no polling after close |
| Logview | all Alpine sources, refresh, empty/unreadable source, shoulder switching, bounded rendering |
| Pkgman | list, search through OSK, details, empty query result, unavailable `apk`, authorization boundary for future install/remove |
| Terminal | harmless success, non-zero exit, multiline/large output bounds, OSK/controller text route; later replace this gate with the GPSH controller-only workflow |
| Browser | visible upper-output launch, navigation/scroll, link activation, text-entry/OSK route, return/close, missing browser |
| Email/SMS/Phone | remain `placeholder` until real backends and controller flows exist; tests must verify the UI says unavailable rather than presenting false functionality |

**Exit gate:** each non-placeholder built-in app has a scenario report covering the common spine and its app-specific contract.

### Phase E — Add an external-application control contract

Visibility and B-to-close are necessary but insufficient. Introduce one shell-owned external-app profile per handler class. Each profile defines:

- executable resolution and launch arguments;
- upper-output focus and layer handoff;
- controller action mapping;
- lower-screen context and control hints;
- OSK/file-selector integration;
- observable health/readiness signal;
- clean close and unexpected-exit behavior;
- native config path and Settings keys.

Prefer a real control API over synthetic keys. For example, mpv should expose a per-run IPC socket so play/pause, seek, volume, mute, track/subtitle selection, and position can be asserted. If another application has no stable remote-control interface, either select a controllable application or document and test a focused key-translation adapter; do not call process existence proof of working controls.

Required handler matrix:

| Handler | Minimum controller checks | Observable proof |
|---|---|---|
| mpv video/audio | play/pause, seek backward/forward, volume/mute, track/subtitle where fixture supports it, Home/B close | IPC playback state/position/volume plus both-display screenshots |
| imv image | next/previous, zoom, pan or fit, rotate if advertised, close | selected image and view state change, not only process state |
| KOReader ebook/PDF | next/previous page, menu/back, zoom or reading mode where advertised, close | current page/view state changes and returns to Files |
| Chromium/browser | directional/scroll navigation, activate, back/forward, address/search text through OSK, close | URL/title/focus or accessibility state plus visible upper-output capture |
| external terminal/GPSH | controller navigation, command construction, run, output, close | command result and process/PTY state; no desktop keyboard dependency |

During external ownership, the shell must continue receiving the reserved system controls without forwarding them twice. The lower display must show the profile's real controls. On exit, QuickShell must reclaim focus, restore `WlrLayer.Overlay`, clear `externalApp`, and return to the parent app or Home according to the initiating path.

**Exit gate:** one representative fixture per handler proves every advertised control and all four exit paths: B, Home, app self-exit, and launch failure.

### Phase F — Make configuration and Settings authoritative

Build a configuration map for every app and applet with these columns:

- runtime setting ID;
- Settings section/row/widget;
- default source;
- user override path;
- effective-value reader;
- writer or generated native config;
- live-apply/reload/restart behavior;
- authorization requirement;
- scenario ID.

Resolve the current split explicitly:

1. Keep `settings-schema.toml` discovery precedence testable: XDG user path, `/etc/torchform`, repository/deployed fallback.
2. Confirm `settings.conf` is either the authoritative value consumed by runtime code or an input to a deterministic native-config generator. Storing an unused value is a failure.
3. Make app selector rows such as `apps.terminal`, `apps.browser`, `apps.editor`, and `apps.media` editable through the OSK or a discovered enumeration picker, validate the selected executable, and make `torchform-control.sh` consume them.
4. Expose input mappings in Settings without creating a second input source. Writes must update `~/.config/torchform/input.toml` atomically, validate before replacement, and require an inputd reload/restart with visible status.
5. Add applicable media settings: preferred handlers, audio output, default volume, subtitle behavior, hardware decoding, image fit, reader mode, and browser privacy/startup options. Only add settings the selected application can actually consume.
6. Mark rows as live, session-restart, service-restart, reboot, or privileged. Never imply that a stored-only value is active.
7. Test missing schema, user override, system fallback, malformed value, duplicate key, unwritable store, atomic interruption, reset, and restart persistence.
8. Verify Settings search/navigation can reach every configurable app and applet. A new configurable feature is incomplete until its row and scenario exist.

**Exit gate:** change each representative widget type in Settings, observe the target app/applet behavior change, restart the session, and observe the same effective value. No shipped settings row may be silently disconnected.

### Phase G — Startup, shutdown, boot, and recovery

Test both manual development startup and installed OpenRC startup.

1. Fresh boot with no stale runtime directory.
2. Inputd readiness and action manifest before QuickShell begins accepting controller input.
3. Sway socket discovery and geometry-derived output configuration.
4. QuickShell startup with zero QML warnings and correct upper/lower surfaces.
5. First-run installation of `input.toml`, followed by second start without overwriting user changes.
6. Applet and app launch immediately after boot.
7. End Session confirmation: external apps stop first, QuickShell exits, Sway exits, input backend exits, runtime sockets/directories are removed.
8. OpenRC stop/restart and service dependency ordering.
9. Device reboot and reconnect; services return exactly once in production mode with `TORCHFORM_VIRTUAL_GAMEPAD=0`.
10. Crash recovery for QuickShell, external app, inputd, and Sway. Record which component restarts automatically and which requires the session service.
11. Resource check after repeated open/switch/close cycles: process count, file descriptors, memory, CPU, disk space, and logs do not grow without bound.

Destructive tests require an interactive authorization setup and an explicit harness flag. The report must distinguish “confirmation UI passed” from “device actually rebooted/powered off and recovered.”

**Exit gate:** a real boot-to-controller-input run and a real stop/restart run pass on Minerva; a reboot run proves production services and configs return without manual cleanup.

### Phase H — Regression suite and release gate

Split execution by cost while keeping one coverage report:

- **Per-change:** affected helper contract checks and focused device scenarios.
- **Pre-merge:** all non-destructive controller scenarios, both-display captures at key transitions, config round trips, and production restoration.
- **Release/device image:** physical input sample, touch when available, real Wi-Fi/Bluetooth services, media controls, OpenRC boot/stop/restart, reboot recovery, and resource soak.

A release fails on any uncovered registered surface/control, assertion failure, unexpected skip, new QML warning, orphan process, config mismatch, wrong-output toplevel, stale focus owner, or production-restoration failure.

## Evidence format

Each run should retain:

- `report.json`: device identity, revision, scenario results, skips with reasons, runtime inventory, selected config paths, process assertions, and resource measurements;
- `report.txt`: operator-readable failures and exact rerun command;
- role-labeled upper/lower screenshots and `outputs.json`;
- relevant startup, QuickShell, Sway, inputd, helper, and external-app logs;
- redacted effective configuration and checksums before/after restoration;
- fixture manifest and cleanup result.

No report may promote a synthetic touch, unavailable backend, confirmation-only power action, or visible-but-uncontrolled external process into a pass.

## Reusable testing skill

After Phases A–C stabilize the harness interface, create a managed skill named `minerva-torchform-app-readiness-testing`. It should not duplicate the existing virtual-gamepad procedure; it should build on `minerva-hdmi-virtual-gamepad-smoke` and specialize the app/applet workflow.

The skill must contain:

1. Preconditions and device/project paths for the active `~/projects/torchform-guishell` deployment.
2. How to generate and review the runtime coverage inventory.
3. How to create isolated fixtures and protect/restore production configs.
4. Focused commands for one applet, one built-in app, one external handler, config precedence, lifecycle, and boot testing.
5. How to drive controller buttons, axes, holds/chords, OSK, and physical/synthetic touch without overstating evidence.
6. How to inspect both outputs, Sway focus/tree state, app IPC state, exact processes, and logs.
7. The external-app layer/focus handoff and focus-reclaim invariants.
8. Failure triage for stale state, missing handlers, wrong output, lost focus, inputd/plugin mismatches, unavailable services, and failed production restoration.
9. The required evidence bundle and pass/blocked/placeholder terminology.
10. The mandatory final production-mode restoration check.

Update that skill whenever the harness action grammar, state schema, config paths, process ownership, or production restoration command changes. Validate the skill by giving it to a fresh session to run one applet, one media handler, and one config round trip without undocumented steps. If common virtual-gamepad or restoration behavior changes, update `minerva-hdmi-virtual-gamepad-smoke` in the same change rather than letting the two skills disagree.

## Completion criteria

This plan is complete when:

- every runtime-registered applet, app, external handler, and advertised control appears in the generated coverage report;
- every non-placeholder item passes its applicable readiness gates on Minerva;
- each dependency activation path returns to the correct parent state;
- image, audio, video, ebook/PDF, browser, and terminal/GPSH controls are demonstrated, not inferred from process launch;
- each applicable config is editable in Settings, consumed by the real runtime, and persistent with honest reload/restart status;
- manual and OpenRC startup/shutdown/restart behavior is proven without orphan processes or test-mode leftovers;
- blocked hardware/service checks remain explicit and cannot be counted as passes;
- the managed testing skill is created, dry-run validated, and kept synchronized with the harness.
