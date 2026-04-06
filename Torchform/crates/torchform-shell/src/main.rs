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
//     cargo run -p torchform-shell -- --standalone --demo palette
//
// Demo overlays: radial | palette | switcher | idle
// =============================================================================

mod config;
mod palette;
mod radial;
mod workspace;
mod apps;
mod audio;
mod settings;

// All Slint-generated types land here: ShellOverlay, LowerScreen,
// TorchformEmulator, AppSettings, AppFiles, RadialItem, RadialLayer,
// CommandEntry, VoiceState, AppEntry, LowerContext.
slint::include_modules!();

use std::{collections::HashMap, rc::Rc, cell::RefCell, env, sync::mpsc, time::Duration};
use anyhow::Result;
use tracing::info;

use palette::PaletteState;
use radial::{Direction, MenuLayer, RadialMenuState, system_radial_items};
use workspace::WorkspaceManager;
use torchform_actions::{ShellAction, InputMap, RawInput};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
enum ActiveApp {
    Settings,
    Files,
    Camera,
    WebBrowser,
    MediaPlayer,
    Network,
    Keyboard,
    Terminal,
}

// ---------------------------------------------------------------------------
// Application state (shared across both run modes)
// ---------------------------------------------------------------------------

struct ShellApp {
    config:     config::TorchformConfig,
    input_map:  InputMap,
    radial:     RadialMenuState,
    palette:    PaletteState,
    workspaces: WorkspaceManager,
    stick_x:             f32,
    stick_y:             f32,
    radial_stick_active: bool,
    active_app:          Option<ActiveApp>,
    /// Focused row index per app (replaces flat settings_row / files_row).
    app_rows:            HashMap<ActiveApp, i32>,
    /// Per-app string state (e.g. current path for the file manager).
    files_path:          String,
    /// Cached settings rows — rebuilt whenever config changes.
    settings_rows:       Vec<settings::SettingsRowData>,
}

impl ShellApp {
    fn new(cfg: config::TorchformConfig) -> Self {
        let settings_rows = settings::make_settings_entries(&cfg);
        Self {
            config:              cfg,
            input_map:           InputMap::load(),
            radial:              RadialMenuState::new(),
            palette:             PaletteState::new(),
            workspaces:          WorkspaceManager::new(),
            stick_x:             0.0,
            stick_y:             0.0,
            radial_stick_active: false,
            active_app:          None,
            app_rows:            HashMap::new(),
            files_path:          "/home".into(),
            settings_rows,
        }
    }

    fn rebuild_settings(&mut self) {
        self.settings_rows = settings::make_settings_entries(&self.config);
    }

    fn row(&self, app: ActiveApp) -> i32 {
        *self.app_rows.get(&app).unwrap_or(&0)
    }

    fn set_row(&mut self, app: ActiveApp, row: i32) {
        self.app_rows.insert(app, row);
    }

    fn nav_up(&mut self, app: ActiveApp) {
        let r = (self.row(app) - 1).max(0);
        self.set_row(app, r);
    }

    fn nav_down(&mut self, app: ActiveApp) {
        let r = self.row(app) + 1;
        self.set_row(app, r);
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
                // gilrs not critical — keyboard shortcuts still work
                tracing::warn!("gilrs init failed (no gamepad support): {e}");
                return;
            }
        };
        info!("Gamepad thread started ({} gamepads detected)",
              gilrs.gamepads().count());
        let map = InputMap::load();
        // Track both stick axes so we always emit a combined vector.
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
// Emulator mode — one combined 768×950 window
// ---------------------------------------------------------------------------

fn run_emulator(demo_mode: Option<&str>) -> Result<()> {
    let cfg = config::TorchformConfig::load();
    let emu = TorchformEmulator::new()?;
    apply_theme_emu(&emu, &cfg.theme.resolve());
    let app = Rc::new(RefCell::new(ShellApp::new(cfg)));

    let (gp_tx, gp_rx) = mpsc::channel::<ShellAction>();
    spawn_gamepad_thread(gp_tx);

    macro_rules! key_cb {
        ($action:expr) => {{
            let emu2 = emu.as_weak();
            let app2 = app.clone();
            move || {
                if let Some(e) = emu2.upgrade() {
                    emu_handle_event(&mut app2.borrow_mut(), $action, &e);
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
        let emu2 = emu.as_weak(); let app2 = app.clone();
        move |held| {
            if let Some(e) = emu2.upgrade() {
                emu_handle_event(&mut app2.borrow_mut(), ShellAction::RadialHold { held }, &e);
            }
        }
    });

    emu.on_key_stick_n(key_cb!(ShellAction::StickMoved { x:  0.0, y: -0.8 }));
    emu.on_key_stick_s(key_cb!(ShellAction::StickMoved { x:  0.0, y:  0.8 }));
    emu.on_key_stick_w(key_cb!(ShellAction::StickMoved { x: -0.8, y:  0.0 }));
    emu.on_key_stick_e(key_cb!(ShellAction::StickMoved { x:  0.8, y:  0.0 }));
    emu.on_key_stick_release(key_cb!(ShellAction::StickMoved { x: 0.0, y: 0.0 }));

    emu.on_radial_dismissed(key_cb!(ShellAction::Cancel));
    emu.on_palette_dismissed(key_cb!(ShellAction::Cancel));
    emu.on_app_closed(key_cb!(ShellAction::Cancel));
    emu.on_switcher_dismissed({
        let emu2 = emu.as_weak();
        move || { emu2.upgrade().map(|e| e.set_switcher_visible(false)); }
    });
    emu.on_app_files_navigate({
        let emu2 = emu.as_weak(); let app2 = app.clone();
        move |name| {
            if let Some(e) = emu2.upgrade() {
                let mut a = app2.borrow_mut();
                let candidate = format!("{}/{}", a.files_path.trim_end_matches('/'), name);
                if std::path::Path::new(&candidate).is_dir() {
                    a.files_path = candidate.clone();
                    a.set_row(ActiveApp::Files, 0);
                    e.set_app_files_path(candidate.clone().into());
                    e.set_app_files_entries(fs_read_dir(&candidate));
                    e.set_app_files_focused_row(0);
                }
                // File: no-op for now (future: open in editor)
            }
        }
    });
    emu.on_app_files_navigate_parent({
        let emu2 = emu.as_weak(); let app2 = app.clone();
        move || {
            if let Some(e) = emu2.upgrade() {
                let mut a = app2.borrow_mut();
                let parent = std::path::Path::new(&a.files_path)
                    .parent()
                    .map(|p| p.to_string_lossy().into_owned())
                    .unwrap_or_else(|| "/".into());
                a.files_path = parent.clone();
                a.set_row(ActiveApp::Files, 0);
                e.set_app_files_path(parent.clone().into());
                e.set_app_files_entries(fs_read_dir(&parent));
                e.set_app_files_focused_row(0);
            }
        }
    });
    emu.on_app_settings_setting_activated({
        let emu2 = emu.as_weak(); let app2 = app.clone();
        move |key| {
            if let Some(e) = emu2.upgrade() {
                let mut a = app2.borrow_mut();
                let changed = settings::apply_activation(key.as_str(), &mut a.config);
                if changed { let _ = a.config.save(&config::user_config_path()); }
                a.rebuild_settings();
                e.set_app_settings_entries(settings_to_slint(&a.settings_rows));
            }
        }
    });
    emu.on_app_settings_setting_adjusted({
        let emu2 = emu.as_weak(); let app2 = app.clone();
        move |key, delta| {
            if let Some(e) = emu2.upgrade() {
                let mut a = app2.borrow_mut();
                let changed = settings::apply_adjustment(key.as_str(), delta, &mut a.config);
                if changed { let _ = a.config.save(&config::user_config_path()); }
                a.rebuild_settings();
                e.set_app_settings_entries(settings_to_slint(&a.settings_rows));
            }
        }
    });

    emu.on_palette_query_changed({
        let emu2 = emu.as_weak(); let app2 = app.clone();
        move |q| {
            if let Some(e) = emu2.upgrade() {
                if let Ok(mut a) = app2.try_borrow_mut() {
                    a.palette.set_query(&q);
                    e.set_palette_entries(make_palette_entries(&a.palette));
                    e.set_palette_focused(a.palette.focused_index as i32);
                }
            }
        }
    });
    emu.on_lower_key_pressed({
        let emu2 = emu.as_weak(); let app2 = app.clone();
        move |k| {
            if let Some(e) = emu2.upgrade() {
                let ch = k.chars().next().unwrap_or(' ');
                let mut a = app2.borrow_mut();
                a.palette.append_char(ch);
                e.set_palette_entries(make_palette_entries(&a.palette));
                e.set_palette_query(a.palette.query.clone().into());
                e.set_palette_focused(a.palette.focused_index as i32);
            }
        }
    });
    emu.on_lower_backspace({
        let emu2 = emu.as_weak(); let app2 = app.clone();
        move || {
            if let Some(e) = emu2.upgrade() {
                let mut a = app2.borrow_mut();
                a.palette.backspace();
                e.set_palette_entries(make_palette_entries(&a.palette));
                e.set_palette_query(a.palette.query.clone().into());
                e.set_palette_focused(a.palette.focused_index as i32);
            }
        }
    });
    emu.on_lower_submit(key_cb!(ShellAction::Confirm));

    let gp_timer = slint::Timer::default();
    gp_timer.start(slint::TimerMode::Repeated, Duration::from_millis(8), {
        let emu2 = emu.as_weak(); let app2 = app.clone();
        move || {
            while let Ok(event) = gp_rx.try_recv() {
                if let Some(e) = emu2.upgrade() {
                    emu_handle_event(&mut app2.borrow_mut(), event, &e);
                }
            }
        }
    });

    // --- Initial state ------------------------------------------------------
    {
        let mut a = app.borrow_mut();

        emu.set_lower_time_str("14:32".into());
        emu.set_lower_date_str("Sat 28 Mar".into());
        emu.set_lower_battery_pct(87);
        emu.set_lower_wifi_connected(true);
        emu.set_lower_notification_count(3);

        emu.set_time_str("14:32".into());
        emu.set_battery_pct(87);
        emu.set_wifi_connected(true);
        emu.set_workspace_name(a.workspaces.active_name().into());
        emu.set_workspace_index(a.workspaces.active_index as i32);

        let radial_slots = a.config.radial.system.slots.clone();
        match demo_mode {
            Some("radial") => {
                a.radial.open(MenuLayer::System, system_radial_items(&radial_slots));
                emu_apply_radial(&emu, &a.radial);
                emu.set_context(LowerContext::RadialMenu);
            }
            Some("switcher") => {
                emu.set_switcher_visible(true);
                emu.set_context(LowerContext::Idle);
            }
            Some("idle") => {
                emu.set_context(LowerContext::Idle);
            }
            // "palette" or default: open palette so something is visible immediately
            _ => {
                a.palette.open();
                emu_apply_palette(&emu, &a.palette);
                emu.set_context(LowerContext::Keyboard);
            }
        }
    }

    emu.run()?;
    Ok(())
}

fn emu_hide_all_apps(emu: &TorchformEmulator) {
    emu.set_app_settings_visible(false);
    emu.set_app_files_visible(false);
    emu.set_app_camera_visible(false);
    emu.set_app_browser_visible(false);
    emu.set_app_media_visible(false);
    emu.set_app_network_visible(false);
    emu.set_app_keyboard_visible(false);
    emu.set_app_terminal_visible(false);
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
    // Dirs first, then alpha
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

// ---------------------------------------------------------------------------
// Settings model — builds a flat [SettingsEntry] array from TorchformConfig
// ---------------------------------------------------------------------------

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

fn emu_apply_apps(emu: &TorchformEmulator, app: &ShellApp) {
    emu_hide_all_apps(emu);
    match app.active_app {
        Some(ActiveApp::Settings) => {
            emu.set_app_settings_visible(true);
            emu.set_app_settings_focused_row(app.row(ActiveApp::Settings));
            emu.set_app_settings_entries(settings_to_slint(&app.settings_rows));
        }
        Some(ActiveApp::Files) => {
            emu.set_app_files_visible(true);
            emu.set_app_files_focused_row(app.row(ActiveApp::Files));
            emu.set_app_files_path(app.files_path.clone().into());
            emu.set_app_files_entries(fs_read_dir(&app.files_path));
        }
        Some(ActiveApp::Camera) => {
            emu.set_app_camera_visible(true);
            emu.set_app_camera_focused_row(app.row(ActiveApp::Camera));
        }
        Some(ActiveApp::WebBrowser) => {
            emu.set_app_browser_visible(true);
            emu.set_app_browser_focused_row(app.row(ActiveApp::WebBrowser));
        }
        Some(ActiveApp::MediaPlayer) => {
            emu.set_app_media_visible(true);
            emu.set_app_media_focused_row(app.row(ActiveApp::MediaPlayer));
        }
        Some(ActiveApp::Network) => {
            emu.set_app_network_visible(true);
            emu.set_app_network_focused_row(app.row(ActiveApp::Network));
        }
        Some(ActiveApp::Keyboard) => {
            emu.set_app_keyboard_visible(true);
        }
        Some(ActiveApp::Terminal) => {
            emu.set_app_terminal_visible(true);
        }
        None => {}
    }
}

// Emulator-specific event handler
fn emu_handle_event(
    app: &mut ShellApp,
    action: ShellAction,
    emu: &TorchformEmulator,
) {
    match action {
        ShellAction::RadialHold { held: true } => {
            if !app.radial.visible {
                app.radial.open(MenuLayer::System, system_radial_items(&app.config.radial.system.slots));
                app.radial_stick_active = false;
                emu_apply_radial(emu, &app.radial);
                emu.set_context(LowerContext::RadialMenu);
            }
        }
        ShellAction::RadialHold { held: false } => {
            if app.radial.visible {
                if app.radial_stick_active {
                    if let Some(item) = app.radial.focused_item() {
                        info!("Radial stick-select: {}", item.label);
                    }
                }
                app.radial.close();
                app.radial_stick_active = false;
                emu_apply_radial(emu, &app.radial);
                emu.set_context(LowerContext::Idle);
            }
        }
        ShellAction::OpenPalette => {
            if app.palette.visible {
                app.palette.close();
                emu.set_palette_visible(false);
                emu.set_context(LowerContext::Idle);
            } else {
                app.palette.open();
                emu_apply_palette(emu, &app.palette);
                emu.set_context(LowerContext::Keyboard);
            }
        }
        ShellAction::OpenSwitcher => {
            let vis = !emu.get_switcher_visible();
            emu.set_switcher_visible(vis);
        }
        ShellAction::NavUp => {
            audio::play(audio::SoundCue::Nav);
            if app.radial.visible {
                app.radial.navigate(Direction::Up);
                emu.set_radial_focused(app.radial.focused_index as i32);
            } else if app.palette.visible {
                app.palette.move_up();
                emu.set_palette_focused(app.palette.focused_index as i32);
            } else if app.active_app == Some(ActiveApp::Settings) {
                let cur = app.row(ActiveApp::Settings) as usize;
                let next = settings::focus_up(cur, &app.settings_rows);
                app.set_row(ActiveApp::Settings, next as i32);
                emu_apply_apps(emu, app);
            } else if let Some(active) = app.active_app {
                app.nav_up(active);
                emu_apply_apps(emu, app);
            }
        }
        ShellAction::NavDown => {
            audio::play(audio::SoundCue::Nav);
            if app.radial.visible {
                app.radial.navigate(Direction::Down);
                emu.set_radial_focused(app.radial.focused_index as i32);
            } else if app.palette.visible {
                app.palette.move_down();
                emu.set_palette_focused(app.palette.focused_index as i32);
            } else if app.active_app == Some(ActiveApp::Settings) {
                let cur = app.row(ActiveApp::Settings) as usize;
                let next = settings::focus_down(cur, &app.settings_rows);
                app.set_row(ActiveApp::Settings, next as i32);
                emu_apply_apps(emu, app);
            } else if let Some(active) = app.active_app {
                app.nav_down(active);
                emu_apply_apps(emu, app);
            }
        }
        ShellAction::NavLeft => {
            if app.radial.visible {
                app.radial.navigate(Direction::Left);
                emu.set_radial_focused(app.radial.focused_index as i32);
            } else if app.active_app == Some(ActiveApp::Settings) {
                let row = app.row(ActiveApp::Settings) as usize;
                if let Some(entry) = app.settings_rows.get(row) {
                    let key = entry.key.clone();
                    let changed = settings::apply_adjustment(&key, -1, &mut app.config);
                    if changed { let _ = app.config.save(&config::user_config_path()); }
                    app.rebuild_settings();
                    emu.set_app_settings_entries(settings_to_slint(&app.settings_rows));
                }
            }
        }
        ShellAction::NavRight => {
            if app.radial.visible {
                app.radial.navigate(Direction::Right);
                emu.set_radial_focused(app.radial.focused_index as i32);
            } else if app.active_app == Some(ActiveApp::Settings) {
                let row = app.row(ActiveApp::Settings) as usize;
                if let Some(entry) = app.settings_rows.get(row) {
                    let key = entry.key.clone();
                    let changed = settings::apply_adjustment(&key, 1, &mut app.config);
                    if changed { let _ = app.config.save(&config::user_config_path()); }
                    app.rebuild_settings();
                    emu.set_app_settings_entries(settings_to_slint(&app.settings_rows));
                }
            }
        }
        ShellAction::Confirm => {
            audio::play(audio::SoundCue::Confirm);
            if app.radial.visible {
                if let Some(item) = app.radial.focused_item() {
                    info!("Radial activated: {}", item.label);
                }
                app.radial.close();
                emu_apply_radial(emu, &app.radial);
                emu.set_context(LowerContext::Idle);
            } else if app.palette.visible {
                if let Some(id) = app.palette.focused_id().map(|s| s.to_owned()) {
                    let id = id.as_str();
                    info!("Command: {id}");
                    // In emulator mode, apps with built-in stubs always show the stub.
                    // try_launch_external is only used for commands that have NO stub.
                    let stub_shown = match id {
                        "app.settings" | "settings" | "open-settings" => {
                            app.active_app = Some(ActiveApp::Settings);
                            let first = settings::focus_down(0, &app.settings_rows);
                            app.set_row(ActiveApp::Settings, first as i32);
                            true
                        }
                        "app.files" | "file-manager" | "open-files" => {
                            app.active_app = Some(ActiveApp::Files);
                            app.set_row(ActiveApp::Files, 0);
                            app.files_path = "/home".into();
                            true
                        }
                        "app.camera" | "camera" => {
                            app.active_app = Some(ActiveApp::Camera);
                            app.set_row(ActiveApp::Camera, 0);
                            true
                        }
                        "app.browser" | "browser" => {
                            app.active_app = Some(ActiveApp::WebBrowser);
                            app.set_row(ActiveApp::WebBrowser, 0);
                            true
                        }
                        "app.media" | "media-player" => {
                            app.active_app = Some(ActiveApp::MediaPlayer);
                            app.set_row(ActiveApp::MediaPlayer, 0);
                            true
                        }
                        "app.network" | "network" => {
                            app.active_app = Some(ActiveApp::Network);
                            app.set_row(ActiveApp::Network, 0);
                            true
                        }
                        "app.keyboard" | "keyboard" => {
                            app.active_app = Some(ActiveApp::Keyboard);
                            true
                        }
                        "app.terminal" | "terminal" => {
                            app.active_app = Some(ActiveApp::Terminal);
                            app.set_row(ActiveApp::Terminal, 0);
                            true
                        }
                        _ => false,
                    };
                    if !stub_shown {
                        apps::try_launch_external(id, &app.config.apps, &app.config.launch);
                    }
                }
                app.palette.close();
                emu.set_palette_visible(false);
                emu_apply_apps(emu, app);
                emu.set_context(LowerContext::Idle);
            }
        }
        ShellAction::Cancel => {
            audio::play(audio::SoundCue::Cancel);
            if app.radial.visible {
                app.radial.close();
                emu_apply_radial(emu, &app.radial);
                emu.set_context(LowerContext::Idle);
            } else if app.palette.visible {
                app.palette.close();
                emu.set_palette_visible(false);
                emu.set_context(LowerContext::Idle);
            } else if app.active_app.is_some() {
                app.active_app = None;
                emu_apply_apps(emu, app);
                emu.set_context(LowerContext::Idle);
            } else {
                emu.set_switcher_visible(false);
            }
        }
        ShellAction::StickMoved { x, y } => {
            app.stick_x = x;
            app.stick_y = y;
            if app.radial.visible {
                let active = app.radial.update_from_stick(x, y);
                app.radial_stick_active = active;
                emu.set_radial_focused(app.radial.focused_index as i32);
            }
        }
        ShellAction::VoiceResult { text } => {
            if app.palette.visible {
                app.palette.set_query(&text);
                emu_apply_palette(emu, &app.palette);
            }
        }
        ShellAction::WorkspacePrev => {
            app.workspaces.switch_prev();
            emu.set_workspace_name(app.workspaces.active_name().into());
            emu.set_workspace_index(app.workspaces.active_index as i32);
        }
        ShellAction::WorkspaceNext => {
            app.workspaces.switch_next();
            emu.set_workspace_name(app.workspaces.active_name().into());
            emu.set_workspace_index(app.workspaces.active_index as i32);
        }
        ShellAction::LowerTap { x, y } => {
            info!("Lower tap at ({x:.0}, {y:.0})");
        }
        // System actions handled at hardware level; shell logs them if received
        ShellAction::BrightnessUp | ShellAction::BrightnessDown |
        ShellAction::VolumeUp | ShellAction::VolumeDown |
        ShellAction::WifiToggle | ShellAction::BluetoothToggle |
        ShellAction::CellularToggle | ShellAction::VpnToggle |
        ShellAction::SplitToggle | ShellAction::Sleep => {
            info!("System action: {action:?}");
        }
        ShellAction::LowerKeyPress { .. } | ShellAction::LowerBackspace |
        ShellAction::LowerSubmit | ShellAction::PadMoved { .. } => {}
    }
}

fn emu_apply_radial(emu: &TorchformEmulator, state: &RadialMenuState) {
    emu.set_radial_visible(state.visible);
    emu.set_radial_layer(make_radial_layer(state));
    emu.set_radial_focused(state.focused_index as i32);
    emu.set_radial_items(make_radial_items(state));
}

fn emu_apply_palette(emu: &TorchformEmulator, state: &PaletteState) {
    emu.set_palette_visible(state.visible);
    emu.set_palette_query(state.query.clone().into());
    emu.set_palette_focused(state.focused_index as i32);
    emu.set_palette_entries(make_palette_entries(state));
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
    info!("Theme applied: {}", theme.name);
}

fn apply_theme_shell(shell: &ShellOverlay, theme: &config::ResolvedTheme) {
    use config::parse_color as c;
    let t = shell.global::<Tokens>();
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
    info!("Theme applied: {}", theme.name);
}

// ---------------------------------------------------------------------------
// Standalone mode — separate ShellOverlay (upper) + LowerScreen (lower)
// ---------------------------------------------------------------------------

fn run_standalone(demo_mode: Option<&str>) -> Result<()> {
    let shell = ShellOverlay::new()?;
    let lower = LowerScreen::new()?;

    shell.window().set_size(slint::LogicalSize::new(1280.0, 720.0));
    lower.window().set_size(slint::LogicalSize::new(640.0, 480.0));

    let cfg = config::TorchformConfig::load();
    apply_theme_shell(&shell, &cfg.theme.resolve());
    let app = Rc::new(RefCell::new(ShellApp::new(cfg)));

    // --- Gamepad channel ---------------------------------------------------
    let (gp_tx, gp_rx) = mpsc::channel::<ShellAction>();
    spawn_gamepad_thread(gp_tx);

    // Helper for standalone event dispatch
    macro_rules! sa_cb {
        ($action:expr) => {{
            let s = shell.as_weak(); let l = lower.as_weak();
            let a = app.clone();
            move || {
                if let (Some(sh), Some(lo)) = (s.upgrade(), l.upgrade()) {
                    sa_handle_event(&mut a.borrow_mut(), $action, &sh, &lo);
                }
            }
        }};
    }

    // --- Wire keyboard callbacks -------------------------------------------
    shell.on_key_select(sa_cb!(ShellAction::OpenPalette));
    shell.on_key_start (sa_cb!(ShellAction::OpenSwitcher));
    shell.on_key_b     (sa_cb!(ShellAction::Cancel));
    shell.on_key_a     (sa_cb!(ShellAction::Confirm));
    shell.on_key_up    (sa_cb!(ShellAction::NavUp));
    shell.on_key_down  (sa_cb!(ShellAction::NavDown));
    shell.on_key_left  (sa_cb!(ShellAction::NavLeft));
    shell.on_key_right (sa_cb!(ShellAction::NavRight));
    shell.on_key_l2({
        let s = shell.as_weak(); let l = lower.as_weak();
        let a = app.clone();
        move |held| {
            if let (Some(sh), Some(lo)) = (s.upgrade(), l.upgrade()) {
                sa_handle_event(&mut a.borrow_mut(), ShellAction::RadialHold { held }, &sh, &lo);
            }
        }
    });

    // --- Analog stick simulation keys (IJKL) ---------------------------------
    shell.on_key_stick_n(sa_cb!(ShellAction::StickMoved { x:  0.0, y: -0.8 }));
    shell.on_key_stick_s(sa_cb!(ShellAction::StickMoved { x:  0.0, y:  0.8 }));
    shell.on_key_stick_w(sa_cb!(ShellAction::StickMoved { x: -0.8, y:  0.0 }));
    shell.on_key_stick_e(sa_cb!(ShellAction::StickMoved { x:  0.8, y:  0.0 }));
    shell.on_key_stick_release(sa_cb!(ShellAction::StickMoved { x: 0.0, y: 0.0 }));

    // --- Overlay callbacks -------------------------------------------------
    shell.on_radial_dismissed({
        let s = shell.as_weak(); let l = lower.as_weak();
        let a = app.clone();
        move || {
            if let (Some(sh), Some(lo)) = (s.upgrade(), l.upgrade()) {
                sa_handle_event(&mut a.borrow_mut(), ShellAction::Cancel, &sh, &lo);
            }
        }
    });
    shell.on_palette_dismissed({
        let s = shell.as_weak(); let l = lower.as_weak();
        let a = app.clone();
        move || {
            if let (Some(sh), Some(lo)) = (s.upgrade(), l.upgrade()) {
                sa_handle_event(&mut a.borrow_mut(), ShellAction::Cancel, &sh, &lo);
            }
        }
    });
    shell.on_switcher_dismissed({
        let s = shell.as_weak();
        move || { s.upgrade().map(|sh| sh.set_switcher_visible(false)); }
    });
    shell.on_app_settings_setting_activated({
        let s = shell.as_weak(); let a = app.clone();
        move |key| {
            if let Some(sh) = s.upgrade() {
                let mut ap = a.borrow_mut();
                let changed = settings::apply_activation(key.as_str(), &mut ap.config);
                if changed { let _ = ap.config.save(&config::user_config_path()); }
                ap.rebuild_settings();
                sh.set_app_settings_entries(settings_to_slint(&ap.settings_rows));
            }
        }
    });
    shell.on_app_settings_setting_adjusted({
        let s = shell.as_weak(); let a = app.clone();
        move |key, delta| {
            if let Some(sh) = s.upgrade() {
                let mut ap = a.borrow_mut();
                let changed = settings::apply_adjustment(key.as_str(), delta, &mut ap.config);
                if changed { let _ = ap.config.save(&config::user_config_path()); }
                ap.rebuild_settings();
                sh.set_app_settings_entries(settings_to_slint(&ap.settings_rows));
            }
        }
    });
    shell.on_palette_query_changed({
        let s = shell.as_weak(); let a = app.clone();
        move |q| {
            if let Some(sh) = s.upgrade() {
                if let Ok(mut ap) = a.try_borrow_mut() {
                    ap.palette.set_query(&q);
                    sh.set_palette_entries(make_palette_entries(&ap.palette));
                    sh.set_palette_focused(ap.palette.focused_index as i32);
                }
            }
        }
    });

    // --- Lower keyboard ---------------------------------------------------
    lower.on_key_pressed({
        let s = shell.as_weak(); let a = app.clone();
        move |k| {
            if let Some(sh) = s.upgrade() {
                let ch = k.chars().next().unwrap_or(' ');
                let mut ap = a.borrow_mut();
                ap.palette.append_char(ch);
                sh.set_palette_entries(make_palette_entries(&ap.palette));
                sh.set_palette_query(ap.palette.query.clone().into());
                sh.set_palette_focused(ap.palette.focused_index as i32);
            }
        }
    });
    lower.on_backspace({
        let s = shell.as_weak(); let a = app.clone();
        move || {
            if let Some(sh) = s.upgrade() {
                let mut ap = a.borrow_mut();
                ap.palette.backspace();
                sh.set_palette_entries(make_palette_entries(&ap.palette));
                sh.set_palette_query(ap.palette.query.clone().into());
                sh.set_palette_focused(ap.palette.focused_index as i32);
            }
        }
    });
    lower.on_submit({
        let s = shell.as_weak(); let l = lower.as_weak();
        let a = app.clone();
        move || {
            if let (Some(sh), Some(lo)) = (s.upgrade(), l.upgrade()) {
                sa_handle_event(&mut a.borrow_mut(), ShellAction::Confirm, &sh, &lo);
            }
        }
    });

    // --- Close propagation ------------------------------------------------
    shell.window().on_close_requested({
        let lo = lower.as_weak();
        move || {
            lo.upgrade().map(|l| l.hide().ok());
            slint::CloseRequestResponse::HideWindow
        }
    });

    // --- Gamepad timer ----------------------------------------------------
    let gp_timer = slint::Timer::default();
    gp_timer.start(slint::TimerMode::Repeated, Duration::from_millis(8), {
        let s = shell.as_weak(); let l = lower.as_weak();
        let a = app.clone();
        move || {
            while let Ok(event) = gp_rx.try_recv() {
                if let (Some(sh), Some(lo)) = (s.upgrade(), l.upgrade()) {
                    sa_handle_event(&mut a.borrow_mut(), event, &sh, &lo);
                }
            }
        }
    });

    // --- Initial state ----------------------------------------------------
    {
        let mut a = app.borrow_mut();
        lower.set_time_str("14:32".into());
        lower.set_date_str("Sat 28 Mar".into());
        lower.set_battery_pct(87);
        lower.set_wifi_connected(true);
        lower.set_notification_count(3);
        shell.set_time_str("14:32".into());
        shell.set_battery_pct(87);
        shell.set_wifi_connected(true);

        let radial_slots = a.config.radial.system.slots.clone();
        match demo_mode {
            Some("radial") => {
                a.radial.open(MenuLayer::System, system_radial_items(&radial_slots));
                sa_apply_radial(&shell, &a.radial);
                lower.set_context(LowerContext::RadialMenu);
            }
            Some("switcher") => {
                shell.set_switcher_visible(true);
                lower.set_context(LowerContext::Idle);
            }
            Some("idle") => {
                lower.set_context(LowerContext::Idle);
            }
            _ => {
                a.palette.open();
                sa_apply_palette(&shell, &a.palette);
                lower.set_context(LowerContext::Keyboard);
            }
        }
    }

    lower.show()?;
    shell.run()?;
    Ok(())
}

fn sa_hide_all_apps(shell: &ShellOverlay) {
    shell.set_app_settings_visible(false);
    shell.set_app_files_visible(false);
    shell.set_app_camera_visible(false);
    shell.set_app_browser_visible(false);
    shell.set_app_media_visible(false);
    shell.set_app_network_visible(false);
    shell.set_app_keyboard_visible(false);
    shell.set_app_terminal_visible(false);
}

fn sa_apply_apps(shell: &ShellOverlay, app: &ShellApp) {
    sa_hide_all_apps(shell);
    match app.active_app {
        Some(ActiveApp::Files) => {
            shell.set_app_files_visible(true);
            shell.set_app_files_focused_row(app.row(ActiveApp::Files));
            shell.set_app_files_path(app.files_path.clone().into());
            shell.set_app_files_entries(fs_read_dir(&app.files_path));
        }
        Some(ActiveApp::Settings) => {
            shell.set_app_settings_visible(true);
            shell.set_app_settings_focused_row(app.row(ActiveApp::Settings));
            shell.set_app_settings_entries(settings_to_slint(&app.settings_rows));
        }
        Some(ActiveApp::Camera) => {
            shell.set_app_camera_visible(true);
            shell.set_app_camera_focused_row(app.row(ActiveApp::Camera));
        }
        Some(ActiveApp::WebBrowser) => {
            shell.set_app_browser_visible(true);
            shell.set_app_browser_focused_row(app.row(ActiveApp::WebBrowser));
        }
        Some(ActiveApp::MediaPlayer) => {
            shell.set_app_media_visible(true);
            shell.set_app_media_focused_row(app.row(ActiveApp::MediaPlayer));
        }
        Some(ActiveApp::Network) => {
            shell.set_app_network_visible(true);
            shell.set_app_network_focused_row(app.row(ActiveApp::Network));
        }
        Some(ActiveApp::Keyboard) => {
            shell.set_app_keyboard_visible(true);
        }
        Some(ActiveApp::Terminal) => {
            shell.set_app_terminal_visible(true);
        }
        None => {}
    }
}

fn sa_handle_event(
    app: &mut ShellApp,
    action: ShellAction,
    shell: &ShellOverlay,
    lower: &LowerScreen,
) {
    match action {
        ShellAction::RadialHold { held: true } => {
            if !app.radial.visible {
                app.radial.open(MenuLayer::System, system_radial_items(&app.config.radial.system.slots));
                app.radial_stick_active = false;
                sa_apply_radial(shell, &app.radial);
                lower.set_context(LowerContext::RadialMenu);
            }
        }
        ShellAction::RadialHold { held: false } => {
            if app.radial.visible {
                if app.radial_stick_active {
                    if let Some(item) = app.radial.focused_item() {
                        info!("Radial stick-select: {}", item.label);
                    }
                }
                app.radial.close();
                app.radial_stick_active = false;
                sa_apply_radial(shell, &app.radial);
                lower.set_context(LowerContext::Idle);
            }
        }
        ShellAction::OpenPalette => {
            if app.palette.visible {
                app.palette.close();
                shell.set_palette_visible(false);
                lower.set_context(LowerContext::Idle);
            } else {
                app.palette.open();
                sa_apply_palette(shell, &app.palette);
                lower.set_context(LowerContext::Keyboard);
            }
        }
        ShellAction::OpenSwitcher => {
            let vis = !shell.get_switcher_visible();
            shell.set_switcher_visible(vis);
        }
        ShellAction::NavUp => {
            if app.radial.visible {
                app.radial.navigate(Direction::Up);
                shell.set_radial_focused(app.radial.focused_index as i32);
            } else if app.palette.visible {
                app.palette.move_up();
                shell.set_palette_focused(app.palette.focused_index as i32);
            } else if app.active_app == Some(ActiveApp::Settings) {
                let cur = app.row(ActiveApp::Settings) as usize;
                let next = settings::focus_up(cur, &app.settings_rows);
                app.set_row(ActiveApp::Settings, next as i32);
                sa_apply_apps(shell, app);
            } else if let Some(active) = app.active_app {
                app.nav_up(active);
                sa_apply_apps(shell, app);
            }
        }
        ShellAction::NavDown => {
            if app.radial.visible {
                app.radial.navigate(Direction::Down);
                shell.set_radial_focused(app.radial.focused_index as i32);
            } else if app.palette.visible {
                app.palette.move_down();
                shell.set_palette_focused(app.palette.focused_index as i32);
            } else if app.active_app == Some(ActiveApp::Settings) {
                let cur = app.row(ActiveApp::Settings) as usize;
                let next = settings::focus_down(cur, &app.settings_rows);
                app.set_row(ActiveApp::Settings, next as i32);
                sa_apply_apps(shell, app);
            } else if let Some(active) = app.active_app {
                app.nav_down(active);
                sa_apply_apps(shell, app);
            }
        }
        ShellAction::NavLeft => {
            if app.radial.visible {
                app.radial.navigate(Direction::Left);
                shell.set_radial_focused(app.radial.focused_index as i32);
            } else if app.active_app == Some(ActiveApp::Settings) {
                let row = app.row(ActiveApp::Settings) as usize;
                if let Some(entry) = app.settings_rows.get(row) {
                    let key = entry.key.clone();
                    let changed = settings::apply_adjustment(&key, -1, &mut app.config);
                    if changed { let _ = app.config.save(&config::user_config_path()); }
                    app.rebuild_settings();
                    shell.set_app_settings_entries(settings_to_slint(&app.settings_rows));
                }
            }
        }
        ShellAction::NavRight => {
            if app.radial.visible {
                app.radial.navigate(Direction::Right);
                shell.set_radial_focused(app.radial.focused_index as i32);
            } else if app.active_app == Some(ActiveApp::Settings) {
                let row = app.row(ActiveApp::Settings) as usize;
                if let Some(entry) = app.settings_rows.get(row) {
                    let key = entry.key.clone();
                    let changed = settings::apply_adjustment(&key, 1, &mut app.config);
                    if changed { let _ = app.config.save(&config::user_config_path()); }
                    app.rebuild_settings();
                    shell.set_app_settings_entries(settings_to_slint(&app.settings_rows));
                }
            }
        }
        ShellAction::Confirm => {
            if app.radial.visible {
                if let Some(item) = app.radial.focused_item() {
                    info!("Radial activated: {}", item.label);
                }
                app.radial.close();
                sa_apply_radial(shell, &app.radial);
                lower.set_context(LowerContext::Idle);
            } else if app.palette.visible {
                if let Some(id) = app.palette.focused_id().map(|s| s.to_owned()) {
                    let id = id.as_str();
                    info!("Command: {id}");
                    if !apps::try_launch_external(id, &app.config.apps, &app.config.launch) {
                        match id {
                            "app.settings" | "settings" | "open-settings" => {
                                app.active_app = Some(ActiveApp::Settings);
                                let first = settings::focus_down(0, &app.settings_rows);
                                app.set_row(ActiveApp::Settings, first as i32);
                            }
                            "app.files" | "file-manager" | "open-files" => {
                                app.active_app = Some(ActiveApp::Files);
                                app.set_row(ActiveApp::Files, 0);
                                app.files_path = "/home".into();
                            }
                            "app.camera" | "camera" => {
                                app.active_app = Some(ActiveApp::Camera);
                                app.set_row(ActiveApp::Camera, 0);
                            }
                            "app.browser" | "browser" => {
                                app.active_app = Some(ActiveApp::WebBrowser);
                                app.set_row(ActiveApp::WebBrowser, 0);
                            }
                            "app.media" | "media-player" => {
                                app.active_app = Some(ActiveApp::MediaPlayer);
                                app.set_row(ActiveApp::MediaPlayer, 0);
                            }
                            "app.network" | "network" => {
                                app.active_app = Some(ActiveApp::Network);
                                app.set_row(ActiveApp::Network, 0);
                            }
                            "app.keyboard" | "keyboard" => {
                                app.active_app = Some(ActiveApp::Keyboard);
                            }
                            "app.terminal" | "terminal" => {
                                app.active_app = Some(ActiveApp::Terminal);
                                app.set_row(ActiveApp::Terminal, 0);
                            }
                            _ => {}
                        }
                    }
                }
                app.palette.close();
                shell.set_palette_visible(false);
                sa_apply_apps(shell, app);
                lower.set_context(LowerContext::Idle);
            }
        }
        ShellAction::Cancel => {
            if app.radial.visible {
                app.radial.close();
                sa_apply_radial(shell, &app.radial);
                lower.set_context(LowerContext::Idle);
            } else if app.palette.visible {
                app.palette.close();
                shell.set_palette_visible(false);
                lower.set_context(LowerContext::Idle);
            } else if app.active_app.is_some() {
                app.active_app = None;
                sa_apply_apps(shell, app);
                lower.set_context(LowerContext::Idle);
            } else {
                shell.set_switcher_visible(false);
            }
        }
        ShellAction::StickMoved { x, y } => {
            app.stick_x = x;
            app.stick_y = y;
            if app.radial.visible {
                let active = app.radial.update_from_stick(x, y);
                app.radial_stick_active = active;
                shell.set_radial_focused(app.radial.focused_index as i32);
            }
        }
        ShellAction::VoiceResult { text } => {
            if app.palette.visible {
                app.palette.set_query(&text);
                sa_apply_palette(shell, &app.palette);
            }
        }
        ShellAction::WorkspacePrev => { app.workspaces.switch_prev(); }
        ShellAction::WorkspaceNext => { app.workspaces.switch_next(); }
        ShellAction::LowerTap { x, y } => {
            info!("Lower tap at ({x:.0}, {y:.0})");
        }
        ShellAction::BrightnessUp | ShellAction::BrightnessDown |
        ShellAction::VolumeUp | ShellAction::VolumeDown |
        ShellAction::WifiToggle | ShellAction::BluetoothToggle |
        ShellAction::CellularToggle | ShellAction::VpnToggle |
        ShellAction::SplitToggle | ShellAction::Sleep => {
            info!("System action: {action:?}");
        }
        ShellAction::LowerKeyPress { .. } | ShellAction::LowerBackspace |
        ShellAction::LowerSubmit | ShellAction::PadMoved { .. } => {}
    }
}

fn sa_apply_radial(shell: &ShellOverlay, state: &RadialMenuState) {
    shell.set_radial_visible(state.visible);
    shell.set_radial_layer(make_radial_layer(state));
    shell.set_radial_focused(state.focused_index as i32);
    shell.set_radial_items(make_radial_items(state));
}

fn sa_apply_palette(shell: &ShellOverlay, state: &PaletteState) {
    shell.set_palette_visible(state.visible);
    shell.set_palette_query(state.query.clone().into());
    shell.set_palette_focused(state.focused_index as i32);
    shell.set_palette_entries(make_palette_entries(state));
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
