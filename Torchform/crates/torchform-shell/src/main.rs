// =============================================================================
// torchform-shell — Torchform DE shell process
//
// Two run modes:
//
//   Emulator (default)
//     cargo run -p torchform-shell
//     cargo run -p torchform-shell -- --demo radial
//     → Single 768×950 window that shows both displays in a hardware frame,
//       like a DS emulator.  Keyboard shortcuts + HID gamepad work.
//
//   Standalone (two separate windows, mirrors physical hardware layout)
//     cargo run -p torchform-shell -- --standalone
//
// The N3DS-style shell experience (lock → home → app, status/hint bars, panels,
// switcher) is driven by the `shell::Shell` state machine. Both windows expose
// identical generated property/callback names, so a single `push_shell_render!`
// macro renders either one.
// =============================================================================

mod config;
mod palette;
mod radial;
mod workspace;
mod apps;
mod audio;
mod settings;
mod shell;

// All Slint-generated types land here: ShellOverlay, LowerScreen,
// TorchformEmulator, AppSettings, AppFiles, RadialItem, RadialLayer,
// CommandEntry, VoiceState, AppEntry, LowerContext, ShellScreen, HomeTile,
// HintItem.
slint::include_modules!();

use std::{rc::Rc, cell::RefCell, env, sync::mpsc, time::Duration};
use chrono::Local;
use anyhow::Result;
use tracing::info;

fn now_clock() -> String { Local::now().format("%H:%M").to_string() }
fn now_date_long() -> String { Local::now().format("%A, %b %-d").to_string() }
fn now_date_short() -> String { Local::now().format("%a %-d %b").to_string() }

use palette::PaletteState;
use radial::RadialMenuState;
use shell::{Shell, AppId, Screen, Effect};
use torchform_actions::{ShellAction, InputMap, RawInput};

// ===========================================================================
// Render — push the full Shell state to a window. Both TorchformEmulator and
// ShellOverlay expose the same generated setter names, so one macro serves
// both. Defined before its callers (macro_rules are order-sensitive).
// ===========================================================================

macro_rules! push_shell_render {
    ($ui:expr, $s:expr) => {{
        let s: &Shell = $s;
        let ui = $ui;

        let (grid, dock) = home_models(s);
        ui.set_screen(screen_enum(s));
        ui.set_pin_len(s.pin_len as i32);
        ui.set_home_grid_tiles(grid);
        ui.set_home_dock_tiles(dock);
        ui.set_home_focus(s.home_focus as i32);
        ui.set_hint_items(build_hints(s));

        // Status bar
        ui.set_workspace_index(s.workspace_index() as i32);
        ui.set_wifi_connected(s.cfg.wifi);
        ui.set_sb_bt(s.cfg.bt);
        ui.set_sb_dnd(s.cfg.dnd);
        ui.set_sb_airplane(s.cfg.airplane);
        ui.set_sb_notif_count(s.notifs.len() as i32);
        ui.set_sb_app_name(s.app_id.map(|a| a.name()).unwrap_or("").into());
        ui.set_sb_now_playing("".into());

        // App title bar
        ui.set_app_icon(s.app_id.map(|a| a.icon()).unwrap_or("").into());
        ui.set_app_name(s.app_id.map(|a| a.name()).unwrap_or("").into());

        // App-panel visibility (only the active app on the App screen)
        let on_app = s.screen == Screen::App;
        ui.set_app_settings_visible(on_app && s.app_id == Some(AppId::Settings));
        ui.set_app_files_visible(on_app && s.app_id == Some(AppId::Files));
        ui.set_app_browser_visible(on_app && s.app_id == Some(AppId::Browser));
        ui.set_app_media_visible(on_app && s.app_id == Some(AppId::Media));
        ui.set_app_terminal_visible(on_app && s.app_id == Some(AppId::Terminal));
        ui.set_app_camera_visible(false);
        ui.set_app_network_visible(false);
        ui.set_app_keyboard_visible(false);

        // App-widget data — Settings (two-pane)
        ui.set_app_settings_focused_row(*s.app_rows.get(&AppId::Settings).unwrap_or(&0));
        ui.set_app_settings_entries(settings_to_slint(&s.settings_rows));
        ui.set_app_settings_sidebar_entries(settings_sidebar_to_slint(s));
        ui.set_app_settings_sidebar_focus(s.settings_sidebar_focus as i32);
        ui.set_app_settings_sidebar_in_focus(s.settings_sidebar_active);
        ui.set_app_settings_section_title(settings_section_title(s).into());
        ui.set_app_files_path(s.files_path.clone().into());
        ui.set_app_files_focused_row(*s.app_rows.get(&AppId::Files).unwrap_or(&0));
        ui.set_app_files_entries(fs_read_dir(&s.files_path));
        ui.set_app_media_focused_row(*s.app_rows.get(&AppId::Media).unwrap_or(&0));
        ui.set_app_browser_focused_row(*s.app_rows.get(&AppId::Browser).unwrap_or(&0));

        // Radial overlay
        ui.set_radial_visible(s.radial.visible);
        ui.set_radial_layer(make_radial_layer(&s.radial));
        ui.set_radial_focused(s.radial.focused_index as i32);
        ui.set_radial_items(make_radial_items(&s.radial));

        // Command palette overlay
        ui.set_palette_visible(s.palette.visible);
        ui.set_palette_query(s.palette.query.clone().into());
        ui.set_palette_focused(s.palette.focused_index as i32);
        ui.set_palette_entries(make_palette_entries(&s.palette));

        // App switcher (panel)
        ui.set_switcher_visible(s.panel == Some(shell::Panel::Switcher));
        ui.set_switcher_apps(build_switcher(s));
        ui.set_switcher_focused(s.sw_focus as i32);

        // Quick Settings panel
        ui.set_qs_open(s.panel == Some(shell::Panel::QuickSettings));
        ui.set_qs_vol(s.cfg.vol);
        ui.set_qs_bright(s.cfg.bright);
        ui.set_qs_tiles(build_qs_tiles(s));
        ui.set_qs_focus(s.qs_focus as i32);

        // Notifications panel
        ui.set_nf_open(s.panel == Some(shell::Panel::Notifications));
        ui.set_nf_entries(build_notifs(s));
        ui.set_nf_focus(s.nf_focus as i32);
        ui.set_nf_count(
            if s.notifs.is_empty() { "All clear".into() }
            else { slint::format!("{} new", s.notifs.len()) }
        );
        // Quick Menu overlay
        ui.set_qm_open(s.panel == Some(shell::Panel::QuickMenu));
        ui.set_qm_focus(s.qm_focus as i32);
        ui.set_qm_items(build_qm_items());

        // (banner-* are managed transiently by the dispatch layer, not here)
    }};
}

fn render_emu(emu: &TorchformEmulator, s: &Shell) {
    push_shell_render!(emu, s);
    // The emulator embeds the lower companion display, so it owns the context.
    emu.set_context(lower_context(s));
}

fn render_shell(win: &ShellOverlay, s: &Shell) {
    push_shell_render!(win, s);
}

fn screen_enum(s: &Shell) -> ShellScreen {
    match s.screen {
        Screen::Lock => ShellScreen::Lock,
        Screen::Home => ShellScreen::Home,
        Screen::App  => ShellScreen::App,
    }
}

fn lower_context(s: &Shell) -> LowerContext {
    if s.palette.visible {
        LowerContext::Keyboard
    } else if s.radial.visible {
        LowerContext::RadialMenu
    } else {
        LowerContext::Idle
    }
}

fn home_models(s: &Shell) -> (slint::ModelRc<HomeTile>, slint::ModelRc<HomeTile>) {
    let grid: Vec<HomeTile> = shell::HOME_GRID.iter().enumerate().map(|(i, app)| HomeTile {
        index:   i as i32,
        name:    app.name().into(),
        icon:    app.icon().into(),
        bg:      config::parse_color(app.bg()),
        running: s.run_apps.contains(app),
    }).collect();
    let base = shell::HOME_GRID.len();
    let dock: Vec<HomeTile> = shell::DOCK.iter().enumerate().map(|(i, app)| HomeTile {
        index:   (base + i) as i32,
        name:    app.name().into(),
        icon:    app.icon().into(),
        bg:      config::parse_color(app.bg()),
        running: s.run_apps.contains(app),
    }).collect();
    (
        Rc::new(slint::VecModel::from(grid)).into(),
        Rc::new(slint::VecModel::from(dock)).into(),
    )
}

fn build_switcher(s: &Shell) -> slint::ModelRc<AppEntry> {
    let v: Vec<AppEntry> = s.run_apps.iter().map(|app| AppEntry {
        id:           app.id().into(),
        title:        app.name().into(),
        icon:         app.icon().into(),
        accent_color: config::parse_color(app.bg()),
        is_running:   true,
        tile_slot:    0,
    }).collect();
    Rc::new(slint::VecModel::from(v)).into()
}

fn build_qs_tiles(s: &Shell) -> slint::ModelRc<QsTile> {
    let ws = s.workspace_index();
    let on_off = |b: bool| -> slint::SharedString { if b { "On".into() } else { "Off".into() } };
    let tiles = vec![
        QsTile {
            index: 0,
            icon:  if s.cfg.wifi { "📶".into() } else { "📵".into() },
            name:  "Wi-Fi".into(),
            value: if s.cfg.wifi { s.cfg.wifi_net.clone().into() } else { "Off".into() },
            on:    s.cfg.wifi,
        },
        QsTile {
            index: 1, icon: "📡".into(), name: "Bluetooth".into(),
            value: if s.cfg.bt { s.cfg.bt_dev.clone().into() } else { "Off".into() },
            on: s.cfg.bt,
        },
        QsTile { index: 2, icon: "🔕".into(), name: "Do Not Disturb".into(), value: on_off(s.cfg.dnd),      on: s.cfg.dnd },
        QsTile { index: 3, icon: "✈️".into(), name: "Airplane Mode".into(),  value: on_off(s.cfg.airplane), on: s.cfg.airplane },
        QsTile { index: 4, icon: "📷".into(), name: "Screenshot".into(),     value: "Press A".into(),       on: false },
        QsTile { index: 5, icon: "🔒".into(), name: "Lock".into(),           value: "Press A".into(),       on: false },
        QsTile { index: 6, icon: "⬛".into(), name: "Workspace 1".into(),    value: if ws == 0 { "Active".into() } else { "".into() }, on: ws == 0 },
        QsTile { index: 7, icon: "⬜".into(), name: "Workspace 2".into(),    value: if ws == 1 { "Active".into() } else { "".into() }, on: ws == 1 },
    ];
    Rc::new(slint::VecModel::from(tiles)).into()
}

fn build_notifs(s: &Shell) -> slint::ModelRc<NotifEntry> {
    let v: Vec<NotifEntry> = s.notifs.iter().enumerate().map(|(i, n)| NotifEntry {
        index: i as i32,
        icon:  n.icon.clone().into(),
        app:   n.app.clone().into(),
        title: n.title.clone().into(),
        body:  n.body.clone().into(),
        time:  n.time.clone().into(),
    }).collect();
    Rc::new(slint::VecModel::from(v)).into()
}

fn build_qm_items() -> slint::ModelRc<QuickMenuItem> {
    let items = vec![
        QuickMenuItem { index: 0, icon: "⏻".into(),  label: "Power Off".into(), key: "power_off".into() },
        QuickMenuItem { index: 1, icon: "💤".into(),  label: "Sleep".into(),     key: "sleep".into()     },
        QuickMenuItem { index: 2, icon: "🔒".into(),  label: "Lock".into(),      key: "lock".into()      },
        QuickMenuItem { index: 3, icon: "⚙".into(),   label: "Settings".into(),  key: "settings".into()  },
    ];
    Rc::new(slint::VecModel::from(items)).into()
}

fn build_hints(s: &Shell) -> slint::ModelRc<HintItem> {
    let mk = |k: &str, l: &str| HintItem { key: k.into(), label: l.into() };
    let v: Vec<HintItem> = if s.radial.visible {
        vec![mk("Stick", "Aim"), mk("A", "Select"), mk("L2", "Hold")]
    } else if s.palette.visible {
        vec![mk("↑↓", "Navigate"), mk("A", "Run"), mk("B", "Close")]
    } else if let Some(panel) = s.panel {
        match panel {
            shell::Panel::QuickSettings =>
                vec![mk("ZL", "Close"), mk("A", "Toggle"), mk("↑↓←→", "Navigate"), mk("B", "Back")],
            shell::Panel::Notifications =>
                vec![mk("ZR", "Close"), mk("A", "Open"), mk("X", "Dismiss"), mk("B", "Back")],
            shell::Panel::Switcher =>
                vec![mk("A", "Resume"), mk("X", "Close"), mk("L/R", "Scroll"), mk("B", "Cancel")],
            shell::Panel::QuickMenu =>
                vec![mk("↑↓", "Navigate"), mk("A", "Select"), mk("B", "Close")],
        }
    } else {
        match s.screen {
            Screen::Lock => vec![mk("A", "Unlock")],
            Screen::Home => vec![
                mk("A", "Launch"), mk("ZL", "Quick Settings"),
                mk("ZR", "Notifications"), mk("START", "Switcher"), mk("Y", "Search"),
            ],
            Screen::App => vec![
                mk("B", "Back"), mk("SEL", "Home"),
                mk("ZL", "⚙"), mk("ZR", "🔔"), mk("START", "Switch"),
            ],
        }
    };
    Rc::new(slint::VecModel::from(v)).into()
}

// ===========================================================================
// Effects — side effects that the pure state machine cannot perform itself.
// ===========================================================================

fn apply_effects(s: &Shell, effects: &[Effect]) {
    for e in effects {
        match e {
            Effect::Sound(cue) => audio::play(*cue),
            Effect::LaunchExternal(id) => {
                apps::try_launch_external(id, &s.config.apps, &s.config.launch);
            }
            Effect::SaveConfig => {
                let _ = s.config.save(&config::user_config_path());
            }
            Effect::ShowBanner(_b) => { /* TODO(M3): drive the Banner widget */ }
            Effect::Suspend => info!("System action: suspend requested"),
        }
    }
}

// ---------------------------------------------------------------------------
// Gamepad thread — reads HID controllers via gilrs, maps to ShellAction
// ---------------------------------------------------------------------------

fn spawn_gamepad_thread(tx: mpsc::Sender<ShellAction>) {
    std::thread::spawn(move || {
        let mut gilrs = match gilrs::Gilrs::new() {
            Ok(g) => g,
            Err(e) => {
                tracing::warn!("gilrs init failed (no gamepad support): {e}");
                return;
            }
        };
        info!("Gamepad thread started ({} gamepads detected)",
              gilrs.gamepads().count());
        let map = InputMap::load();
        let mut stick_x = 0.0f32;
        let mut stick_y = 0.0f32;
        loop {
            while let Some(ev) = gilrs.next_event() {
                use gilrs::{Axis, EventType};
                let action = match ev.event {
                    EventType::AxisChanged(Axis::LeftStickX, v, _) => {
                        stick_x = v;
                        Some(ShellAction::StickMoved { x: stick_x, y: stick_y })
                    }
                    EventType::AxisChanged(Axis::LeftStickY, v, _) => {
                        stick_y = -v; // gilrs Y+ = up, shell Y+ = down
                        Some(ShellAction::StickMoved { x: stick_x, y: stick_y })
                    }
                    other => gilrs_event_to_raw(other)
                                .and_then(|raw| map.resolve(&RawInput::new(raw))),
                };
                if let Some(a) = action {
                    if tx.send(a).is_err() { return; }
                }
            }
            std::thread::sleep(Duration::from_millis(4)); // 250 Hz poll
        }
    });
}

/// Convert a gilrs event into a raw input name, then let InputMap resolve it.
fn gilrs_event_to_raw(ev: gilrs::EventType) -> Option<&'static str> {
    use gilrs::{Button, EventType};
    match ev {
        EventType::ButtonPressed(btn, _) => match btn {
            Button::South         => Some("button_a"),
            Button::East          => Some("button_b"),
            Button::Select        => Some("button_select"),
            Button::Start         => Some("button_start"),
            Button::LeftTrigger   => Some("l1"),
            Button::RightTrigger  => Some("r1"),
            Button::LeftTrigger2  => Some("l2_hold_true"),
            Button::RightTrigger2 => Some("r2_hold_true"),
            Button::DPadUp        => Some("dpad_up"),
            Button::DPadDown      => Some("dpad_down"),
            Button::DPadLeft      => Some("dpad_left"),
            Button::DPadRight     => Some("dpad_right"),
            _ => None,
        },
        EventType::ButtonReleased(btn, _) => match btn {
            Button::LeftTrigger2  => Some("l2_hold_false"),
            Button::RightTrigger2 => Some("r2_hold_false"),
            _ => None,
        },
        _ => None,
    }
}

// ---------------------------------------------------------------------------
// Slint model helpers — convert Rust types → Slint-generated structs
// ---------------------------------------------------------------------------

fn make_radial_items(state: &RadialMenuState) -> slint::ModelRc<RadialItem> {
    let items: Vec<RadialItem> = state.items.iter().map(|i| RadialItem {
        label:     i.label.clone().into(),
        icon:      i.icon.clone().into(),
        enabled:   i.enabled,
        is_nested: i.is_nested,
    }).collect();
    Rc::new(slint::VecModel::from(items)).into()
}

fn make_radial_layer(state: &RadialMenuState) -> RadialLayer {
    use radial::MenuLayer;
    match state.layer {
        MenuLayer::App1   => RadialLayer::App1,
        MenuLayer::App2   => RadialLayer::App2,
        MenuLayer::System => RadialLayer::System,
    }
}

fn make_palette_entries(state: &PaletteState) -> slint::ModelRc<CommandEntry> {
    let entries: Vec<CommandEntry> = state.filtered.iter().map(|e| CommandEntry {
        id:          e.id.clone().into(),
        label:       e.label.clone().into(),
        description: e.description.clone().into(),
        category:    e.category.clone().into(),
        icon:        e.icon.clone().into(),
        shortcut:    e.shortcut.clone().into(),
    }).collect();
    Rc::new(slint::VecModel::from(entries)).into()
}

// ---------------------------------------------------------------------------
// Filesystem helpers — build Slint model from a real directory listing
// ---------------------------------------------------------------------------

fn fs_read_dir(path: &str) -> slint::ModelRc<FileEntry> {
    let mut items: Vec<(bool, String, u64)> = match std::fs::read_dir(path) {
        Ok(rd) => rd.filter_map(|e| e.ok()).map(|e| {
            let meta   = e.metadata().ok();
            let is_dir = meta.as_ref().map_or(false, |m| m.is_dir());
            let size   = meta.as_ref().map_or(0u64, |m| m.len());
            (is_dir, e.file_name().to_string_lossy().into_owned(), size)
        }).collect(),
        Err(e) => {
            tracing::warn!("read_dir({path}): {e}");
            vec![]
        }
    };
    items.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(&b.1)));

    let entries: Vec<FileEntry> = items.into_iter().map(|(is_dir, name, size)| {
        if is_dir {
            FileEntry { icon: "📁".into(), name: name.into(), kind: "dir".into(), size: "—".into() }
        } else {
            FileEntry {
                icon: file_icon(&name),
                size: format_size(size).into(),
                kind: "file".into(),
                name: name.into(),
            }
        }
    }).collect();
    Rc::new(slint::VecModel::from(entries)).into()
}

fn file_icon(name: &str) -> slint::SharedString {
    match name.rsplit('.').next().unwrap_or("") {
        "rs" | "toml" | "json" | "yaml" | "yml" | "md" => "📝",
        "png" | "jpg" | "jpeg" | "gif" | "webp"        => "🖼",
        "mp3" | "ogg" | "flac" | "wav"                 => "🎵",
        "mp4" | "mkv" | "webm" | "mov"                 => "🎬",
        "pdf"                                           => "📄",
        "zip" | "tar" | "gz" | "xz" | "zst"            => "📦",
        _                                               => "📄",
    }.into()
}

fn format_size(bytes: u64) -> String {
    const KB: u64 = 1024;
    const MB: u64 = KB * 1024;
    const GB: u64 = MB * 1024;
    if bytes >= GB      { format!("{:.1} GB", bytes as f64 / GB as f64) }
    else if bytes >= MB { format!("{:.1} MB", bytes as f64 / MB as f64) }
    else if bytes >= KB { format!("{:.1} KB", bytes as f64 / KB as f64) }
    else                { format!("{} B", bytes) }
}

fn settings_to_slint(rows: &[settings::SettingsRowData]) -> slint::ModelRc<SettingsEntry> {
    let entries: Vec<SettingsEntry> = rows.iter().map(|r| SettingsEntry {
        widget:        r.widget.clone().into(),
        icon:          r.icon.clone().into(),
        label:         r.label.clone().into(),
        description:   r.description.clone().into(),
        value:         r.value.clone().into(),
        value_index:   r.value_index,
        min:           r.min,
        max:           r.max,
        step:          r.step,
        pct:           r.pct,
        key:           r.key.clone().into(),
        scroll_offset: r.scroll_offset,
    }).collect();
    Rc::new(slint::VecModel::from(entries)).into()
}

fn settings_sidebar_to_slint(s: &Shell) -> slint::ModelRc<SidebarEntry> {
    use shell::section_group;
    let mut entries: Vec<SidebarEntry> = Vec::new();
    let mut last_group = String::new();
    let active_id = s.active_section_id().unwrap_or_default();

    for (i, sec) in s.settings_schema.sections.iter().enumerate() {
        let group = section_group(&sec.id);
        if group != last_group {
            entries.push(SidebarEntry {
                index:        entries.len() as i32,
                id:           "".into(),
                label:        group.clone().into(),
                icon:         "".into(),
                group:        group.clone().into(),
                is_selected:  false,
            });
            last_group = group;
        }
        entries.push(SidebarEntry {
            index:       i as i32,
            id:          sec.id.clone().into(),
            label:       sec.title.clone().into(),
            icon:        section_icon(&sec.id).into(),
            group:       "".into(),
            is_selected: sec.id == active_id,
        });
    }
    Rc::new(slint::VecModel::from(entries)).into()
}

fn section_icon(id: &str) -> &'static str {
    match id {
        "display"     => "🖥",
        "audio"       => "🔊",
        "input"       => "🎮",
        "power"       => "🔋",
        "datetime"    => "🕐",
        "storage"     => "💾",
        "network"     => "📶",
        "bluetooth"   => "📡",
        "vpn"         => "🛡",
        "cellular"    => "📱",
        "netmon"      => "📊",
        "security"    => "🔒",
        "permissions" => "🧩",
        "firewall"    => "🧱",
        "apps"        => "📦",
        "keybinds"    => "🎮",
        "about"       => "ℹ",
        "sysapps"     => "⚙",
        _             => "•",
    }
}

fn settings_section_title(s: &Shell) -> String {
    s.active_section_id()
        .and_then(|id| s.settings_schema.sections.iter().find(|sec| sec.id == id))
        .map(|sec| sec.title.clone())
        .unwrap_or_else(|| "Settings".into())
}

// ===========================================================================
// Emulator mode — one combined 768×950 window
// ===========================================================================

fn dispatch_emu(cell: &Rc<RefCell<Shell>>, action: ShellAction, emu: &TorchformEmulator) {
    let effects = cell.borrow_mut().handle(action);
    {
        let s = cell.borrow();
        apply_effects(&s, &effects);
        render_emu(emu, &s);
    }
    for e in &effects {
        if let Effect::ShowBanner(b) = e {
            emu.set_banner_icon(b.icon.clone().into());
            emu.set_banner_app(b.app.clone().into());
            emu.set_banner_title(b.title.clone().into());
            emu.set_banner_body(b.body.clone().into());
            emu.set_banner_open(true);
            let w = emu.as_weak();
            slint::Timer::single_shot(Duration::from_millis(3500), move || {
                if let Some(e) = w.upgrade() { e.set_banner_open(false); }
            });
        }
    }
}

fn run_emulator(demo_mode: Option<&str>) -> Result<()> {
    let cfg = config::TorchformConfig::load();
    let emu = TorchformEmulator::new()?;
    apply_theme_emu(&emu, &cfg.theme.resolve());
    let shell = Rc::new(RefCell::new(Shell::new(cfg)));

    let (gp_tx, gp_rx) = mpsc::channel::<ShellAction>();
    spawn_gamepad_thread(gp_tx);

    macro_rules! key_cb {
        ($action:expr) => {{
            let e = emu.as_weak();
            let sh = shell.clone();
            move || {
                if let Some(e) = e.upgrade() {
                    dispatch_emu(&sh, $action, &e);
                }
            }
        }};
    }

    emu.on_key_select(key_cb!(ShellAction::OpenPalette));
    emu.on_key_start (key_cb!(ShellAction::OpenSwitcher));
    emu.on_key_b     (key_cb!(ShellAction::Cancel));
    emu.on_key_a     (key_cb!(ShellAction::Confirm));
    emu.on_key_up    (key_cb!(ShellAction::NavUp));
    emu.on_key_down  (key_cb!(ShellAction::NavDown));
    emu.on_key_left  (key_cb!(ShellAction::NavLeft));
    emu.on_key_right (key_cb!(ShellAction::NavRight));
    emu.on_key_l2({
        let e = emu.as_weak(); let sh = shell.clone();
        move |held| {
            if let Some(e) = e.upgrade() {
                dispatch_emu(&sh, ShellAction::RadialHold { held }, &e);
            }
        }
    });
    emu.on_key_stick_n(key_cb!(ShellAction::StickMoved { x:  0.0, y: -0.8 }));
    emu.on_key_stick_s(key_cb!(ShellAction::StickMoved { x:  0.0, y:  0.8 }));
    emu.on_key_stick_w(key_cb!(ShellAction::StickMoved { x: -0.8, y:  0.0 }));
    emu.on_key_stick_e(key_cb!(ShellAction::StickMoved { x:  0.8, y:  0.0 }));
    emu.on_key_stick_release(key_cb!(ShellAction::StickMoved { x: 0.0, y: 0.0 }));

    emu.on_radial_dismissed (key_cb!(ShellAction::Cancel));
    emu.on_palette_dismissed(key_cb!(ShellAction::Cancel));
    emu.on_app_closed       (key_cb!(ShellAction::Cancel));
    emu.on_switcher_dismissed(key_cb!(ShellAction::Cancel));
    emu.on_app_home_pressed     (key_cb!(ShellAction::GoHome));
    emu.on_app_switcher_pressed (key_cb!(ShellAction::OpenSwitcher));

    emu.on_home_tile_activated({
        let e = emu.as_weak(); let sh = shell.clone();
        move |i| {
            if let Some(e) = e.upgrade() {
                {
                    let mut s = sh.borrow_mut();
                    let order = s.home_order();
                    if let Some(app) = order.get(i as usize).copied() {
                        s.launch(app);
                    }
                }
                render_emu(&e, &sh.borrow());
            }
        }
    });

    emu.on_switcher_app_activated({
        let e = emu.as_weak(); let sh = shell.clone();
        move |i| {
            if let Some(e) = e.upgrade() {
                sh.borrow_mut().switcher_activate(i as usize);
                render_emu(&e, &sh.borrow());
            }
        }
    });
    emu.on_switcher_app_closed({
        let e = emu.as_weak(); let sh = shell.clone();
        move |i| {
            if let Some(e) = e.upgrade() {
                sh.borrow_mut().switcher_close(i as usize);
                render_emu(&e, &sh.borrow());
            }
        }
    });

    emu.on_palette_entry_activated({
        let e = emu.as_weak(); let sh = shell.clone();
        move |i| {
            if let Some(e) = e.upgrade() {
                sh.borrow_mut().palette.focused_index = i as usize;
                dispatch_emu(&sh, ShellAction::Confirm, &e);
            }
        }
    });
    emu.on_radial_item_activated({
        let e = emu.as_weak(); let sh = shell.clone();
        move |i| {
            if let Some(e) = e.upgrade() {
                sh.borrow_mut().radial.focused_index = i as usize;
                dispatch_emu(&sh, ShellAction::Confirm, &e);
            }
        }
    });

    // Quick Settings / Notifications panel callbacks
    emu.on_key_quick_settings(key_cb!(ShellAction::OpenQuickSettings));
    emu.on_key_notifications (key_cb!(ShellAction::OpenNotifications));
    emu.on_key_x({
        let e = emu.as_weak(); let sh = shell.clone();
        move || {
            if let Some(e) = e.upgrade() {
                sh.borrow_mut().secondary();
                render_emu(&e, &sh.borrow());
            }
        }
    });
    emu.on_qs_volume_changed({
        let e = emu.as_weak(); let sh = shell.clone();
        move |v| {
            if let Some(e) = e.upgrade() {
                sh.borrow_mut().cfg.vol = v.clamp(0, 100);
                render_emu(&e, &sh.borrow());
            }
        }
    });
    emu.on_qs_brightness_changed({
        let e = emu.as_weak(); let sh = shell.clone();
        move |v| {
            if let Some(e) = e.upgrade() {
                sh.borrow_mut().cfg.bright = v.clamp(0, 100);
                render_emu(&e, &sh.borrow());
            }
        }
    });
    emu.on_qs_tile_activated({
        let e = emu.as_weak(); let sh = shell.clone();
        move |i| {
            if let Some(e) = e.upgrade() {
                sh.borrow_mut().qs_focus = i as usize;
                dispatch_emu(&sh, ShellAction::Confirm, &e);
            }
        }
    });
    emu.on_nf_activated({
        let e = emu.as_weak(); let sh = shell.clone();
        move |i| {
            if let Some(e) = e.upgrade() {
                sh.borrow_mut().nf_focus = i as usize;
                dispatch_emu(&sh, ShellAction::Confirm, &e);
            }
        }
    });
    emu.on_nf_clear_all({
        let e = emu.as_weak(); let sh = shell.clone();
        move || {
            if let Some(e) = e.upgrade() {
                sh.borrow_mut().notifs.clear();
                render_emu(&e, &sh.borrow());
            }
        }
    });
    emu.on_qm_item_activated({
        let e = emu.as_weak(); let sh = shell.clone();
        move |key| {
            if let Some(e) = e.upgrade() {
                let idx = match key.as_str() {
                    "power_off" => 0, "sleep" => 1, "lock" => 2, "settings" => 3, _ => return,
                };
                sh.borrow_mut().qm_focus = idx;
                dispatch_emu(&sh, ShellAction::Confirm, &e);
            }
        }
    });
    emu.on_qm_close_requested({
        let e = emu.as_weak(); let sh = shell.clone();
        move || {
            if let Some(e) = e.upgrade() {
                dispatch_emu(&sh, ShellAction::Cancel, &e);
            }
        }
    });

    emu.on_palette_query_changed({
        let e = emu.as_weak(); let sh = shell.clone();
        move |q| {
            if let Some(e) = e.upgrade() {
                if let Ok(mut s) = sh.try_borrow_mut() {
                    s.palette.set_query(&q);
                }
                render_emu(&e, &sh.borrow());
            }
        }
    });

    emu.on_app_settings_section_selected({
        let e = emu.as_weak(); let sh = shell.clone();
        move |sidebar_idx| {
            if let Some(e) = e.upgrade() {
                let mut s = sh.borrow_mut();
                s.settings_sidebar_focus = sidebar_idx as usize;
                s.settings_enter_rows();
                drop(s);
                render_emu(&e, &sh.borrow());
            }
        }
    });
    emu.on_app_settings_setting_activated({
        let e = emu.as_weak(); let sh = shell.clone();
        move |key| {
            if let Some(e) = e.upgrade() {
                {
                    let mut s = sh.borrow_mut();
                    if settings::apply_activation(key.as_str(), &mut s.config) {
                        let _ = s.config.save(&config::user_config_path());
                    }
                    s.settings_switch_section();
                }
                render_emu(&e, &sh.borrow());
            }
        }
    });
    emu.on_app_settings_setting_adjusted({
        let e = emu.as_weak(); let sh = shell.clone();
        move |key, delta| {
            if let Some(e) = e.upgrade() {
                {
                    let mut s = sh.borrow_mut();
                    let schema = s.settings_schema.clone();
                    if settings::apply_adjustment(key.as_str(), delta, &mut s.config, &schema) {
                        let _ = s.config.save(&config::user_config_path());
                    }
                    s.rebuild_settings();
                }
                render_emu(&e, &sh.borrow());
            }
        }
    });

    emu.on_app_files_navigate({
        let e = emu.as_weak(); let sh = shell.clone();
        move |name| {
            if let Some(e) = e.upgrade() {
                {
                    let mut s = sh.borrow_mut();
                    let candidate = format!("{}/{}", s.files_path.trim_end_matches('/'), name);
                    if std::path::Path::new(&candidate).is_dir() {
                        s.files_path = candidate;
                        s.app_rows.insert(AppId::Files, 0);
                    }
                }
                render_emu(&e, &sh.borrow());
            }
        }
    });
    emu.on_app_files_navigate_parent({
        let e = emu.as_weak(); let sh = shell.clone();
        move || {
            if let Some(e) = e.upgrade() {
                {
                    let mut s = sh.borrow_mut();
                    let parent = std::path::Path::new(&s.files_path)
                        .parent()
                        .map(|p| p.to_string_lossy().into_owned())
                        .unwrap_or_else(|| "/".into());
                    s.files_path = parent;
                    s.app_rows.insert(AppId::Files, 0);
                }
                render_emu(&e, &sh.borrow());
            }
        }
    });

    emu.on_lower_key_pressed({
        let e = emu.as_weak(); let sh = shell.clone();
        move |k| {
            if let Some(e) = e.upgrade() {
                sh.borrow_mut().palette.append_char(k.chars().next().unwrap_or(' '));
                render_emu(&e, &sh.borrow());
            }
        }
    });
    emu.on_lower_backspace({
        let e = emu.as_weak(); let sh = shell.clone();
        move || {
            if let Some(e) = e.upgrade() {
                sh.borrow_mut().palette.backspace();
                render_emu(&e, &sh.borrow());
            }
        }
    });
    emu.on_lower_submit(key_cb!(ShellAction::Confirm));

    // Gamepad drain timer
    let gp_timer = slint::Timer::default();
    gp_timer.start(slint::TimerMode::Repeated, Duration::from_millis(8), {
        let e = emu.as_weak(); let sh = shell.clone();
        move || {
            while let Ok(event) = gp_rx.try_recv() {
                if let Some(e) = e.upgrade() {
                    dispatch_emu(&sh, event, &e);
                }
            }
        }
    });

    // --- Initial state -----------------------------------------------------
    emu.set_time_str(now_clock().into());
    emu.set_date_str(now_date_long().into());
    emu.set_battery_pct(87);
    emu.set_lower_time_str(now_clock().into());
    emu.set_lower_date_str(now_date_short().into());
    emu.set_lower_battery_pct(87);
    emu.set_lower_wifi_connected(true);
    emu.set_lower_notification_count(3);

    if let Some(mode) = demo_mode {
        // Demos skip the lock screen for convenience.
        if matches!(mode, "radial" | "switcher" | "palette") {
            shell.borrow_mut().screen = Screen::Home;
        }
    }
    match demo_mode {
        Some("radial")   => dispatch_emu(&shell, ShellAction::RadialHold { held: true }, &emu),
        Some("switcher") => dispatch_emu(&shell, ShellAction::OpenSwitcher, &emu),
        Some("palette")  => dispatch_emu(&shell, ShellAction::OpenPalette, &emu),
        _                => render_emu(&emu, &shell.borrow()),
    }

    // Live clock — update every second
    let clock_timer = slint::Timer::default();
    clock_timer.start(slint::TimerMode::Repeated, Duration::from_secs(1), {
        let e = emu.as_weak();
        move || {
            if let Some(e) = e.upgrade() {
                e.set_time_str(now_clock().into());
                e.set_date_str(now_date_long().into());
                e.set_lower_time_str(now_clock().into());
                e.set_lower_date_str(now_date_short().into());
            }
        }
    });

    emu.run()?;
    // Keep timers alive until window closes.
    drop(clock_timer);
    Ok(())
}

// ===========================================================================
// Standalone mode — separate ShellOverlay (upper) + LowerScreen (lower)
// ===========================================================================

fn dispatch_shell(cell: &Rc<RefCell<Shell>>, action: ShellAction, win: &ShellOverlay) {
    let effects = cell.borrow_mut().handle(action);
    {
        let s = cell.borrow();
        apply_effects(&s, &effects);
        render_shell(win, &s);
    }
    for e in &effects {
        if let Effect::ShowBanner(b) = e {
            win.set_banner_icon(b.icon.clone().into());
            win.set_banner_app(b.app.clone().into());
            win.set_banner_title(b.title.clone().into());
            win.set_banner_body(b.body.clone().into());
            win.set_banner_open(true);
            let w = win.as_weak();
            slint::Timer::single_shot(Duration::from_millis(3500), move || {
                if let Some(win) = w.upgrade() { win.set_banner_open(false); }
            });
        }
    }
}

fn run_standalone(demo_mode: Option<&str>) -> Result<()> {
    let win   = ShellOverlay::new()?;
    let lower = LowerScreen::new()?;

    win.window().set_size(slint::LogicalSize::new(1280.0, 720.0));
    lower.window().set_size(slint::LogicalSize::new(640.0, 480.0));

    let cfg = config::TorchformConfig::load();
    apply_theme_shell(&win, &cfg.theme.resolve());
    let shell = Rc::new(RefCell::new(Shell::new(cfg)));

    let (gp_tx, gp_rx) = mpsc::channel::<ShellAction>();
    spawn_gamepad_thread(gp_tx);

    macro_rules! key_cb {
        ($action:expr) => {{
            let w = win.as_weak();
            let sh = shell.clone();
            move || {
                if let Some(w) = w.upgrade() {
                    dispatch_shell(&sh, $action, &w);
                }
            }
        }};
    }

    win.on_key_select(key_cb!(ShellAction::OpenPalette));
    win.on_key_start (key_cb!(ShellAction::OpenSwitcher));
    win.on_key_b     (key_cb!(ShellAction::Cancel));
    win.on_key_a     (key_cb!(ShellAction::Confirm));
    win.on_key_up    (key_cb!(ShellAction::NavUp));
    win.on_key_down  (key_cb!(ShellAction::NavDown));
    win.on_key_left  (key_cb!(ShellAction::NavLeft));
    win.on_key_right (key_cb!(ShellAction::NavRight));
    win.on_key_l2({
        let w = win.as_weak(); let sh = shell.clone();
        move |held| {
            if let Some(w) = w.upgrade() {
                dispatch_shell(&sh, ShellAction::RadialHold { held }, &w);
            }
        }
    });
    win.on_key_stick_n(key_cb!(ShellAction::StickMoved { x:  0.0, y: -0.8 }));
    win.on_key_stick_s(key_cb!(ShellAction::StickMoved { x:  0.0, y:  0.8 }));
    win.on_key_stick_w(key_cb!(ShellAction::StickMoved { x: -0.8, y:  0.0 }));
    win.on_key_stick_e(key_cb!(ShellAction::StickMoved { x:  0.8, y:  0.0 }));
    win.on_key_stick_release(key_cb!(ShellAction::StickMoved { x: 0.0, y: 0.0 }));

    win.on_radial_dismissed (key_cb!(ShellAction::Cancel));
    win.on_palette_dismissed(key_cb!(ShellAction::Cancel));
    win.on_app_closed       (key_cb!(ShellAction::Cancel));
    win.on_switcher_dismissed(key_cb!(ShellAction::Cancel));
    win.on_app_home_pressed     (key_cb!(ShellAction::GoHome));
    win.on_app_switcher_pressed (key_cb!(ShellAction::OpenSwitcher));

    win.on_home_tile_activated({
        let w = win.as_weak(); let sh = shell.clone();
        move |i| {
            if let Some(w) = w.upgrade() {
                {
                    let mut s = sh.borrow_mut();
                    let order = s.home_order();
                    if let Some(app) = order.get(i as usize).copied() { s.launch(app); }
                }
                render_shell(&w, &sh.borrow());
            }
        }
    });
    win.on_switcher_app_activated({
        let w = win.as_weak(); let sh = shell.clone();
        move |i| {
            if let Some(w) = w.upgrade() {
                sh.borrow_mut().switcher_activate(i as usize);
                render_shell(&w, &sh.borrow());
            }
        }
    });
    win.on_switcher_app_closed({
        let w = win.as_weak(); let sh = shell.clone();
        move |i| {
            if let Some(w) = w.upgrade() {
                sh.borrow_mut().switcher_close(i as usize);
                render_shell(&w, &sh.borrow());
            }
        }
    });
    win.on_palette_entry_activated({
        let w = win.as_weak(); let sh = shell.clone();
        move |i| {
            if let Some(w) = w.upgrade() {
                sh.borrow_mut().palette.focused_index = i as usize;
                dispatch_shell(&sh, ShellAction::Confirm, &w);
            }
        }
    });
    win.on_radial_item_activated({
        let w = win.as_weak(); let sh = shell.clone();
        move |i| {
            if let Some(w) = w.upgrade() {
                sh.borrow_mut().radial.focused_index = i as usize;
                dispatch_shell(&sh, ShellAction::Confirm, &w);
            }
        }
    });

    win.on_key_quick_settings(key_cb!(ShellAction::OpenQuickSettings));
    win.on_key_notifications (key_cb!(ShellAction::OpenNotifications));
    win.on_key_x({
        let w = win.as_weak(); let sh = shell.clone();
        move || {
            if let Some(w) = w.upgrade() {
                sh.borrow_mut().secondary();
                render_shell(&w, &sh.borrow());
            }
        }
    });
    win.on_qs_volume_changed({
        let w = win.as_weak(); let sh = shell.clone();
        move |v| {
            if let Some(w) = w.upgrade() {
                sh.borrow_mut().cfg.vol = v.clamp(0, 100);
                render_shell(&w, &sh.borrow());
            }
        }
    });
    win.on_qs_brightness_changed({
        let w = win.as_weak(); let sh = shell.clone();
        move |v| {
            if let Some(w) = w.upgrade() {
                sh.borrow_mut().cfg.bright = v.clamp(0, 100);
                render_shell(&w, &sh.borrow());
            }
        }
    });
    win.on_qs_tile_activated({
        let w = win.as_weak(); let sh = shell.clone();
        move |i| {
            if let Some(w) = w.upgrade() {
                sh.borrow_mut().qs_focus = i as usize;
                dispatch_shell(&sh, ShellAction::Confirm, &w);
            }
        }
    });
    win.on_nf_activated({
        let w = win.as_weak(); let sh = shell.clone();
        move |i| {
            if let Some(w) = w.upgrade() {
                sh.borrow_mut().nf_focus = i as usize;
                dispatch_shell(&sh, ShellAction::Confirm, &w);
            }
        }
    });
    win.on_nf_clear_all({
        let w = win.as_weak(); let sh = shell.clone();
        move || {
            if let Some(w) = w.upgrade() {
                sh.borrow_mut().notifs.clear();
                render_shell(&w, &sh.borrow());
            }
        }
    });
    win.on_qm_item_activated({
        let w = win.as_weak(); let sh = shell.clone();
        move |key| {
            if let Some(w) = w.upgrade() {
                let idx = match key.as_str() {
                    "power_off" => 0, "sleep" => 1, "lock" => 2, "settings" => 3, _ => return,
                };
                sh.borrow_mut().qm_focus = idx;
                dispatch_shell(&sh, ShellAction::Confirm, &w);
            }
        }
    });
    win.on_qm_close_requested({
        let w = win.as_weak(); let sh = shell.clone();
        move || {
            if let Some(w) = w.upgrade() {
                dispatch_shell(&sh, ShellAction::Cancel, &w);
            }
        }
    });

    win.on_palette_query_changed({
        let w = win.as_weak(); let sh = shell.clone();
        move |q| {
            if let Some(w) = w.upgrade() {
                if let Ok(mut s) = sh.try_borrow_mut() { s.palette.set_query(&q); }
                render_shell(&w, &sh.borrow());
            }
        }
    });
    win.on_app_settings_section_selected({
        let w = win.as_weak(); let sh = shell.clone();
        move |sidebar_idx| {
            if let Some(w) = w.upgrade() {
                let mut s = sh.borrow_mut();
                s.settings_sidebar_focus = sidebar_idx as usize;
                s.settings_enter_rows();
                drop(s);
                render_shell(&w, &sh.borrow());
            }
        }
    });
    win.on_app_settings_setting_activated({
        let w = win.as_weak(); let sh = shell.clone();
        move |key| {
            if let Some(w) = w.upgrade() {
                {
                    let mut s = sh.borrow_mut();
                    if settings::apply_activation(key.as_str(), &mut s.config) {
                        let _ = s.config.save(&config::user_config_path());
                    }
                    s.settings_switch_section();
                }
                render_shell(&w, &sh.borrow());
            }
        }
    });
    win.on_app_settings_setting_adjusted({
        let w = win.as_weak(); let sh = shell.clone();
        move |key, delta| {
            if let Some(w) = w.upgrade() {
                {
                    let mut s = sh.borrow_mut();
                    let schema = s.settings_schema.clone();
                    if settings::apply_adjustment(key.as_str(), delta, &mut s.config, &schema) {
                        let _ = s.config.save(&config::user_config_path());
                    }
                    s.rebuild_settings();
                }
                render_shell(&w, &sh.borrow());
            }
        }
    });
    win.on_app_files_navigate({
        let w = win.as_weak(); let sh = shell.clone();
        move |name| {
            if let Some(w) = w.upgrade() {
                {
                    let mut s = sh.borrow_mut();
                    let candidate = format!("{}/{}", s.files_path.trim_end_matches('/'), name);
                    if std::path::Path::new(&candidate).is_dir() {
                        s.files_path = candidate;
                        s.app_rows.insert(AppId::Files, 0);
                    }
                }
                render_shell(&w, &sh.borrow());
            }
        }
    });
    win.on_app_files_navigate_parent({
        let w = win.as_weak(); let sh = shell.clone();
        move || {
            if let Some(w) = w.upgrade() {
                {
                    let mut s = sh.borrow_mut();
                    let parent = std::path::Path::new(&s.files_path)
                        .parent()
                        .map(|p| p.to_string_lossy().into_owned())
                        .unwrap_or_else(|| "/".into());
                    s.files_path = parent;
                    s.app_rows.insert(AppId::Files, 0);
                }
                render_shell(&w, &sh.borrow());
            }
        }
    });

    lower.on_key_pressed({
        let w = win.as_weak(); let sh = shell.clone();
        move |k| {
            if let Some(w) = w.upgrade() {
                sh.borrow_mut().palette.append_char(k.chars().next().unwrap_or(' '));
                render_shell(&w, &sh.borrow());
            }
        }
    });
    lower.on_backspace({
        let w = win.as_weak(); let sh = shell.clone();
        move || {
            if let Some(w) = w.upgrade() {
                sh.borrow_mut().palette.backspace();
                render_shell(&w, &sh.borrow());
            }
        }
    });
    lower.on_submit({
        let w = win.as_weak(); let sh = shell.clone();
        move || {
            if let Some(w) = w.upgrade() {
                dispatch_shell(&sh, ShellAction::Confirm, &w);
            }
        }
    });

    win.window().on_close_requested({
        let lo = lower.as_weak();
        move || {
            lo.upgrade().map(|l| l.hide().ok());
            slint::CloseRequestResponse::HideWindow
        }
    });

    let gp_timer = slint::Timer::default();
    gp_timer.start(slint::TimerMode::Repeated, Duration::from_millis(8), {
        let w = win.as_weak(); let sh = shell.clone();
        move || {
            while let Ok(event) = gp_rx.try_recv() {
                if let Some(w) = w.upgrade() {
                    dispatch_shell(&sh, event, &w);
                }
            }
        }
    });

    // --- Initial state -----------------------------------------------------
    lower.set_time_str(now_clock().into());
    lower.set_date_str(now_date_short().into());
    lower.set_battery_pct(87);
    lower.set_wifi_connected(true);
    lower.set_notification_count(3);
    win.set_time_str(now_clock().into());
    win.set_date_str(now_date_long().into());
    win.set_battery_pct(87);

    if let Some(mode) = demo_mode {
        if matches!(mode, "radial" | "switcher" | "palette") {
            shell.borrow_mut().screen = Screen::Home;
        }
    }
    match demo_mode {
        Some("radial")   => dispatch_shell(&shell, ShellAction::RadialHold { held: true }, &win),
        Some("switcher") => dispatch_shell(&shell, ShellAction::OpenSwitcher, &win),
        Some("palette")  => dispatch_shell(&shell, ShellAction::OpenPalette, &win),
        _                => render_shell(&win, &shell.borrow()),
    }

    // Keep the lower window's context in sync via a light timer.
    let lower_timer = slint::Timer::default();
    lower_timer.start(slint::TimerMode::Repeated, Duration::from_millis(80), {
        let l = lower.as_weak(); let sh = shell.clone();
        move || {
            if let Some(l) = l.upgrade() {
                l.set_context(lower_context(&sh.borrow()));
            }
        }
    });

    // Live clock — update every second
    let clock_timer = slint::Timer::default();
    clock_timer.start(slint::TimerMode::Repeated, Duration::from_secs(1), {
        let w = win.as_weak(); let l = lower.as_weak();
        move || {
            if let Some(w) = w.upgrade() {
                w.set_time_str(now_clock().into());
                w.set_date_str(now_date_long().into());
            }
            if let Some(l) = l.upgrade() {
                l.set_time_str(now_clock().into());
                l.set_date_str(now_date_short().into());
            }
        }
    });

    lower.show()?;
    win.run()?;
    // Keep timers alive until window closes.
    drop(clock_timer);
    Ok(())
}

// ---------------------------------------------------------------------------
// Theme application — push resolved theme values to Slint's Tokens global
// ---------------------------------------------------------------------------

fn apply_theme_emu(emu: &TorchformEmulator, theme: &config::ResolvedTheme) {
    use config::parse_color as c;
    let t = emu.global::<Tokens>();
    let col = &theme.colors;
    t.set_bg_base(c(&col.bg_base));
    t.set_bg_surface(c(&col.bg_surface));
    t.set_bg_elevated(c(&col.bg_elevated));
    t.set_bg_overlay(c(&col.bg_overlay));
    t.set_accent(c(&col.accent));
    t.set_accent_dim(c(&col.accent_dim));
    t.set_accent_glow(c(&col.accent_glow));
    t.set_primary(c(&col.primary));
    t.set_primary_hover(c(&col.primary_hover));
    t.set_secondary(c(&col.secondary));
    t.set_success(c(&col.success));
    t.set_warning(c(&col.warning));
    t.set_error(c(&col.error));
    t.set_text_primary(c(&col.text_primary));
    t.set_text_secondary(c(&col.text_secondary));
    t.set_text_disabled(c(&col.text_disabled));
    t.set_text_on_accent(c(&col.text_on_accent));
    t.set_text_on_primary(c(&col.text_on_primary));
    t.set_border(c(&col.border));
    t.set_border_focused(c(&col.border_focused));
    t.set_border_subtle(c(&col.border_subtle));
    t.set_lower_bg(c(&col.lower_bg));
    t.set_lower_surface(c(&col.lower_surface));
    t.set_lower_accent(c(&col.lower_accent));
    t.set_font_sans(theme.typography.font_sans.clone().into());
    t.set_font_mono(theme.typography.font_mono.clone().into());
    t.set_font_display(theme.typography.font_display.clone().into());
    info!("Theme applied: {}", theme.name);
}

fn apply_theme_shell(win: &ShellOverlay, theme: &config::ResolvedTheme) {
    use config::parse_color as c;
    let t = win.global::<Tokens>();
    let col = &theme.colors;
    t.set_bg_base(c(&col.bg_base));
    t.set_bg_surface(c(&col.bg_surface));
    t.set_bg_elevated(c(&col.bg_elevated));
    t.set_bg_overlay(c(&col.bg_overlay));
    t.set_accent(c(&col.accent));
    t.set_accent_dim(c(&col.accent_dim));
    t.set_accent_glow(c(&col.accent_glow));
    t.set_primary(c(&col.primary));
    t.set_primary_hover(c(&col.primary_hover));
    t.set_secondary(c(&col.secondary));
    t.set_success(c(&col.success));
    t.set_warning(c(&col.warning));
    t.set_error(c(&col.error));
    t.set_text_primary(c(&col.text_primary));
    t.set_text_secondary(c(&col.text_secondary));
    t.set_text_disabled(c(&col.text_disabled));
    t.set_text_on_accent(c(&col.text_on_accent));
    t.set_text_on_primary(c(&col.text_on_primary));
    t.set_border(c(&col.border));
    t.set_border_focused(c(&col.border_focused));
    t.set_border_subtle(c(&col.border_subtle));
    t.set_lower_bg(c(&col.lower_bg));
    t.set_lower_surface(c(&col.lower_surface));
    t.set_lower_accent(c(&col.lower_accent));
    t.set_font_sans(theme.typography.font_sans.clone().into());
    t.set_font_mono(theme.typography.font_mono.clone().into());
    t.set_font_display(theme.typography.font_display.clone().into());
    info!("Theme applied: {}", theme.name);
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("torchform_shell=debug".parse().unwrap()),
        )
        .init();

    let args: Vec<String> = env::args().collect();
    let demo_mode = args.windows(2)
        .find(|w| w[0] == "--demo")
        .map(|w| w[1].as_str());
    let standalone = args.contains(&"--standalone".to_string());

    info!("torchform-shell starting (mode={}, demo={:?})",
          if standalone { "standalone" } else { "emulator" }, demo_mode);

    if standalone {
        run_standalone(demo_mode)
    } else {
        run_emulator(demo_mode)
    }
}
