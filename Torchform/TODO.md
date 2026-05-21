# Torchform — Master TODO
# Cyberdeck Shell: Field-Ready Checklist

Goal: a fully self-contained Linux shell environment for the Minerva CM5 handheld.
Navigable entirely without a keyboard. OSK appears whenever text input is needed.
Reference design: torchform-os.html — match it exactly, then extend.

---

## PHASE 1 — Settings App (2-pane layout)

**Why:** Current Rust settings renders as one giant flat scroll list (~90 entries).
HTML prototype is a sidebar (section list) + main pane (section rows only).
This is the most user-visible deficiency.

- [x] 1A  Rebuild `app_settings.slint` as 2-pane: left sidebar (section list), right pane (rows for active section only)
          Sidebar: D-pad Up/Down navigates sections. A selects. Section groups (SYSTEM / CONNECTIVITY / PRIVACY / DEVICE) shown as dividers.
          Right pane: D-pad Up/Down navigates rows. L/R adjusts sliders/selects. A confirms toggles/actions.
          Focus starts in sidebar; pressing A (or Right) moves focus to the row pane; B returns focus to sidebar.
- [ ] 1B  Add `settings_section: usize` and `settings_pane: SettingsPane { Sidebar, Rows }` to `Shell`
          `nav_app(Settings, Up/Down)` moves sidebar focus when pane=Sidebar, row focus when pane=Rows
          `confirm_app(Settings)` in Sidebar pane: switch active section, move focus to Rows
          `route_cancel` in Settings with pane=Rows: return focus to Sidebar (not GoHome)
- [ ] 1C  Wire `settings_section` + `settings_pane` into `push_shell_render!`
          Pass `app_settings_section` and `app_settings_sidebar_focus` as Slint properties
          Right pane receives only the rows for the active section (filter by section ID in Rust)
          Remove B-back badge from settings header (B is no longer back-nav in apps)

---

## PHASE 2 — Layout & Geometry Fixes

**Why:** Hardcoded pixel values designed for 393px HTML view look wrong on 1920×1080.

- [ ] 2A  Home grid: change from 6-column 80px cells to 4-column layout with ~110px cells
          Dock: increase icon size from 44px to 56px; spacing 12px
          Ambient wash: make radial gradient cover more area
- [ ] 2B  QS panel: change `width: 310px` → `width: min(420px, parent.width * 0.22)`
          Tile grid: replace absolute-position for loop with a scrollable `VerticalLayout`
          Scroll the focused tile into view: add `tile_scroll_offset` property computed from focus-index
- [ ] 2C  Notifications panel: similar width fix (currently mirrors QS at 310px)
          Add scroll tracking for focused notification entry
- [ ] 2D  Status bar: increase height from 28px to 36px; increase font sizes (currently 10-12px, too small at 1080p)
          Hint bar: increase height from 24px to 32px; hint chip font 11px → 13px
          App title bar: increase from 32px to 42px

---

## PHASE 3 — QuickMenu Overlay (L1+R1 hold 3s)

**Why:** Hold engine fires `HoldFired { name: "l1+r1" }` → `ShellAction::OpenQuickMenu`,
but no Slint component exists to render it. The panel is invisible.

- [ ] 3A  Create `ui/quick_menu.slint` — centered dark card, 4 items (Sleep / Power Off / Lock / Settings)
          D-pad Up/Down navigates. A confirms. B closes. Slide-in animation from bottom.
          Export `QuickMenu` component with `open`, `focused-index`, `callback item-activated(int)`, `callback dismissed()`
- [ ] 3B  Add `QuickMenu` to `main.slint` imports; add `qm-open` / `qm-focus` properties to emulator and shell windows
          Wire `set_qm_open` / `set_qm_focus` in `push_shell_render!`
          Wire `on_qm_item_activated` and `on_qm_dismissed` callbacks in dispatch

---

## PHASE 4 — Input Context Wiring

**Why:** `KeybindContext` was added but never used. `ChordMap` loads empty defaults.
Both mean the context-separation work is dead code.

- [ ] 4A  `shell/src/main.rs`: replace `map.resolve(&raw)` with `map.resolve_ctx(&raw, ctx)` where
          `ctx = if s.screen == Screen::App && s.panel.is_none() { App } else { Shell }`
- [ ] 4B  `torchform-inputd/src/main.rs`: load `KeybindFile::load()` at startup;
          build `ChordMap::from_config(&kf.chords, &kf.holds)`;
          pass real chord_map to `chord_action_to_shell_with_chords()`
          Also load `[[chords]]` and `[[holds]]` into `ChordDetector::with_patterns()`

---

## PHASE 5 — Live System State

**Why:** Time is hardcoded "14:32". Brightness/volume sliders have no backend.
Battery is hardcoded 87%. None of these update at runtime.

- [ ] 5A  Live clock: add a `slint::Timer` repeating every 1s; call `chrono::Local::now()`;
          push `time_str` and `date_str` to both upper and lower display
- [ ] 5B  Brightness: on `Effect::SetBrightness(pct)`, write to
          `/sys/class/backlight/$(ls /sys/class/backlight | head -1)/brightness`
          Scale 0-100 to 0-max_brightness (read from `max_brightness` file)
- [ ] 5C  Volume: on `Effect::SetVolume(pct)`, run `amixer sset Master {pct}% --quiet`
          or `pactl set-sink-volume @DEFAULT_SINK@ {pct}%` (detect which is available)
- [ ] 5D  Battery: add a 30s timer; read `/sys/class/power_supply/BAT0/capacity` and
          `status` (Charging/Discharging/Full); push to status bar and lower screen

---

## PHASE 6 — OSK Full Integration

**Why:** VirtualKeyboard on lower screen only feeds chars to the command palette.
Any app that needs text (browser URL, notes, SMS, etc.) must also be able to receive input.

- [ ] 6A  Add `TextTarget` enum to shell: `{ Palette, BrowserUrl, NotesEditor, SmsCompose, SearchBar }`
          Shell tracks `text_target: Option<TextTarget>`; OSK key presses are routed to the active target
          Each app's text buffer is a field on `Shell`
- [ ] 6B  `LowerContext::Keyboard` is set whenever `text_target.is_some()`
          Pressing B or Submit from OSK clears `text_target` → lower returns to `Idle`
          X button in the active app's text field sets `text_target`
- [ ] 6C  Add OSK-trigger hints to each app's hint bar entry (e.g. "Y — Type" for Notes, "Y — URL" for Browser)

---

## PHASE 7 — App Backends

**Why:** All app Slint components exist but Rust state is stub/empty.
These need real data to be a usable system.

### 7A — Terminal (portable-pty)
- [ ] Add `portable-pty` crate; spawn a shell (bash/fish) in a PTY
- [ ] Stream PTY output into `Vec<TermLine>` model; push to Slint
- [ ] D-pad Up/Down scrolls viewport; Up/Down arrow keys feed to PTY history
- [ ] OSK input goes to PTY stdin; Enter sends line
- [ ] Handle ANSI escape codes (at minimum: clear, colour, cursor up)

### 7B — Browser (stub rendering)
- [ ] URL bar activated by Y button → sets `text_target = BrowserUrl` → OSK appears
- [ ] Back/Forward: maintain `history: Vec<String>` stack; L=back, R=forward
- [ ] D-pad scroll: track `browser_scroll: i32`; push to `app_browser_focused_row`
- [ ] Content area renders the existing HTML stub pages from `apps.rs`

### 7C — Files (real readdir)
- [ ] Replace stub `fs_read_dir()` with real `std::fs::read_dir()`
- [ ] Show file type icon (📁 dir, 📄 file, 🔗 symlink)
- [ ] A opens (directory: cd into it; file: attempt to launch associated app)
- [ ] B goes up one directory
- [ ] L/R cycles sidebar (bookmarks: Home, Downloads, Documents, NVMe)

### 7D — Notes (file persistence)
- [ ] Store notes in `~/.local/share/torchform/notes/*.md`
- [ ] List view: D-pad navigates, A opens, X creates new, Y deletes with confirm
- [ ] Edit view: OSK feeds `notes_buf`; B saves and returns to list

### 7E — Sysmon (live /proc)
- [ ] 2s timer: read `/proc/stat` for per-core CPU%, `/proc/meminfo` for RAM, `/proc/net/dev` for net I/O
- [ ] Push to `AppSysmon` Slint model
- [ ] D-pad Up/Down scrolls process list from `/proc/*/status`

### 7F — Logview (journalctl)
- [ ] Spawn `journalctl -f --output=short-iso -n 200` as a subprocess
- [ ] Stream lines into a capped ring buffer (max 500 lines); push to Slint model
- [ ] D-pad scroll; L/R switches tabs (All / kernel / torchform / err)

### 7G — Pkgman (pacman)
- [ ] On open: run `pacman -Q` in background thread; push results into model
- [ ] Search: OSK feeds query, filter model client-side
- [ ] A on package: show details (`pacman -Qi <pkg>`)
- [ ] Install/remove flow: confirmation dialog before running pacman -S/-R

---

## PHASE 8 — Network & Bluetooth

- [ ] 8A  Wi-Fi: run `nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list` on QS open
           Show network list in Network settings section; A connects (ask passphrase via OSK if needed)
           Toggle in QS calls `nmcli radio wifi on/off`
- [ ] 8B  Bluetooth: run `bluetoothctl devices Paired` for paired list
           Connect/disconnect: `bluetoothctl connect/disconnect <addr>`
           Show device name + battery in QS tile value

---

## PHASE 9 — Process & Workspace Management

- [ ] 9A  App switcher: track real PIDs in `run_apps`; kill sends `SIGTERM` via `nix` crate
           App card shows actual run time (started_at timestamp)
- [ ] 9B  Workspace persist: save `active_index` to `~/.config/torchform/config.toml` on switch
           WorkspaceNext chord (L1+X) fires `ShellAction::WorkspaceNext`
           Status bar workspace dots reflect `WorkspaceManager.active_index`

---

## PHASE 10 — Notifications

- [ ] 10A DBus `org.freedesktop.Notifications` server in `torchform-shell` (or a sidecar)
            Receive `Notify` calls from system apps; push into `Shell.notifs`
            Trigger banner + notification dot automatically
- [ ] 10B  Swipe-to-dismiss on lower touchscreen; X button on notification row dismisses

---

## PHASE 11 — Lower Screen Polish

- [ ] 11A  Live state: time/date on 1s timer; battery/network mirror upper state changes
- [ ] 11B  RadialMenu context: 8 touch rectangles on lower screen map to the 8 radial slots
            Touch fires `item-activated(i)` callback up to upper shell
- [ ] 11C  App context: each app can push a `LowerContext::AppContext` companion view
            (e.g. Terminal shows last few lines; Notes shows word count)

---

## PHASE 12 — Hardware Input Daemon

- [ ] 12A  `torchform-inputd`: use `evdev` crate with `EVIOCGBIT` to properly detect
            gamepad vs. keyboard vs. touchpad; don't grab first event device blindly
- [ ] 12B  Cirque GlidePoint: implement real PINNACLE register read sequence over SPI
            Feed absolute coordinates into uinput ABS_X/ABS_Y
            Tap detection: short contact → synthesize BTN_LEFT

---

## PHASE 13 — Compositor

- [ ] 13A  `torchform-compositor`: DRM/KMS backend via Smithay `DrmBackend`
            Two `DrmOutput`s mapped to DSI-0 (1920×1080) and DSI-1 (640×480)
            Replaces the winit dev backend for on-device use
- [ ] 13B  XDG shell surface protocol: external apps (Alacritty, Firefox, etc.) can be
            tiled by the compositor and presented in the App screen `AppWindow` frame
            Compositor notifies shell via a Unix socket when a surface is ready

---

## PHASE 14 — Quality & Shipping

- [ ] 14A  `cargo clippy --workspace -- -D warnings` clean
- [ ] 14B  `cargo test --workspace` all green
- [ ] 14C  Emulator smoke test checklist:
            - Lock → Konami → Home ✓
            - Home grid nav (4×2) ✓
            - Launch Settings → sidebar → Display section → adjust Brightness ✓
            - QS panel (ZR/R1) — all tiles visible, scroll works ✓
            - Notifications panel (ZL/L1) — entries scroll ✓
            - App Switcher (Start) — resume, kill ✓
            - Radial (L2+R2 hold) — 8 items, D-pad navigate, confirm ✓
            - QuickMenu (L1+R1 hold 3s) — 4 items, Sleep/Power/Lock/Settings ✓
            - Command palette (X) — search, launch app ✓
            - Terminal — type command, get output ✓
            - Files — browse, enter dir, B goes up ✓
            - OSK feeds text to palette, browser URL, notes ✓
            - B in any app does NOT navigate out ✓
            - GoHome (Select) exits any app to Home ✓
- [ ] 14D  systemd unit files: `torchform-shell.service`, `torchform-inputd.service`,
            `torchform-compositor.service` — proper ordering, restart policy
- [ ] 14E  Font installation check: Barlow Condensed, Inter, JetBrains Mono, DM Mono
            Makefile target `make install-fonts` that fetches from Google Fonts

---

## Deferred / Future

- Full keybind rebind UI (listen-mode row in Settings → Input)
- Dotfile editor (read parsed TOML/YAML into a structured editor view)
- Split-screen tiling (two apps side by side via compositor tile slots)
- Phone / SMS / Email backends (requires cellular modem + SIM integration)
- Camera (v4l2 capture)
- Media player backend (mpv IPC socket)
- NFC/QR code reader
- Headless test harness (run shell state machine without display)
