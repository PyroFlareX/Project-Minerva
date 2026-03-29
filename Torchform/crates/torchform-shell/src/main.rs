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

// All Slint-generated types land here: ShellOverlay, LowerScreen,
// TorchformEmulator, AppSettings, AppFiles, RadialItem, RadialLayer,
// CommandEntry, VoiceState, AppEntry, LowerContext.
slint::include_modules!();

use std::{rc::Rc, cell::RefCell, env, sync::mpsc, time::Duration};
use anyhow::Result;
use tracing::info;

use palette::PaletteState;
use radial::{Direction, MenuLayer, RadialMenuState, system_radial_items};
use workspace::WorkspaceManager;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ActiveApp { Settings, Files }

// ---------------------------------------------------------------------------
// Input events — arrive from torchform-inputd (Unix socket) in production;
// simulated via keyboard shortcuts and gilrs gamepad in development.
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub enum ShellEvent {
    ButtonA,
    ButtonB,
    ButtonStart,
    ButtonSelect,
    L1Pressed,
    R1Pressed,
    L2Held(bool),
    R2Held(bool),
    DpadUp,
    DpadDown,
    DpadLeft,
    DpadRight,
    VoiceResult(String),
    LowerTap { x: f32, y: f32 },
    StickMoved { x: f32, y: f32 },
}

// ---------------------------------------------------------------------------
// Application state (shared across both run modes)
// ---------------------------------------------------------------------------

struct ShellApp {
    config:     config::TorchformConfig,
    radial:     RadialMenuState,
    palette:    PaletteState,
    workspaces: WorkspaceManager,
    stick_x:             f32,
    stick_y:             f32,
    radial_stick_active: bool,
    active_app:          Option<ActiveApp>,
    settings_row:        i32,
    files_row:           i32,
    files_path:          String,
}

impl ShellApp {
    fn new(cfg: config::TorchformConfig) -> Self {
        Self {
            config:              cfg,
            radial:              RadialMenuState::new(),
            palette:             PaletteState::new(),
            workspaces:          WorkspaceManager::new(),
            stick_x:             0.0,
            stick_y:             0.0,
            radial_stick_active: false,
            active_app:          None,
            settings_row:        0,
            files_row:           0,
            files_path:          "/home".into(),
        }
    }
}

// ---------------------------------------------------------------------------
// Gamepad thread — reads HID controllers via gilrs, sends ShellEvents
// ---------------------------------------------------------------------------

fn spawn_gamepad_thread(tx: mpsc::Sender<ShellEvent>) {
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
        // Track both stick axes so we always emit a combined vector.
        let mut stick_x = 0.0f32;
        let mut stick_y = 0.0f32;
        loop {
            while let Some(ev) = gilrs.next_event() {
                use gilrs::{Axis, EventType};
                let shell_ev = match ev.event {
                    EventType::AxisChanged(Axis::LeftStickX, v, _) => {
                        stick_x = v;
                        Some(ShellEvent::StickMoved { x: stick_x, y: stick_y })
                    }
                    EventType::AxisChanged(Axis::LeftStickY, v, _) => {
                        stick_y = v;
                        Some(ShellEvent::StickMoved { x: stick_x, y: stick_y })
                    }
                    other => map_gilrs_event(other),
                };
                if let Some(se) = shell_ev {
                    if tx.send(se).is_err() { return; }
                }
            }
            std::thread::sleep(Duration::from_millis(4)); // 250 Hz poll
        }
    });
}

fn map_gilrs_event(ev: gilrs::EventType) -> Option<ShellEvent> {
    use gilrs::{Button, EventType};
    match ev {
        EventType::ButtonPressed(btn, _) => match btn {
            Button::South        => Some(ShellEvent::ButtonA),
            Button::East         => Some(ShellEvent::ButtonB),
            Button::Select       => Some(ShellEvent::ButtonSelect),
            Button::Start        => Some(ShellEvent::ButtonStart),
            Button::LeftTrigger  => Some(ShellEvent::L1Pressed),
            Button::RightTrigger => Some(ShellEvent::R1Pressed),
            Button::LeftTrigger2  => Some(ShellEvent::L2Held(true)),
            Button::RightTrigger2 => Some(ShellEvent::R2Held(true)),
            Button::DPadUp    => Some(ShellEvent::DpadUp),
            Button::DPadDown  => Some(ShellEvent::DpadDown),
            Button::DPadLeft  => Some(ShellEvent::DpadLeft),
            Button::DPadRight => Some(ShellEvent::DpadRight),
            _ => None,
        },
        EventType::ButtonReleased(btn, _) => match btn {
            Button::LeftTrigger2  => Some(ShellEvent::L2Held(false)),
            Button::RightTrigger2 => Some(ShellEvent::R2Held(false)),
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

    let (gp_tx, gp_rx) = mpsc::channel::<ShellEvent>();
    spawn_gamepad_thread(gp_tx);

    macro_rules! key_cb {
        ($event:expr) => {{
            let emu2 = emu.as_weak();
            let app2 = app.clone();
            move || {
                if let Some(e) = emu2.upgrade() {
                    emu_handle_event(&mut app2.borrow_mut(), $event, &e);
                }
            }
        }};
    }

    emu.on_key_select(key_cb!(ShellEvent::ButtonSelect));
    emu.on_key_start (key_cb!(ShellEvent::ButtonStart));
    emu.on_key_b     (key_cb!(ShellEvent::ButtonB));
    emu.on_key_a     (key_cb!(ShellEvent::ButtonA));
    emu.on_key_up    (key_cb!(ShellEvent::DpadUp));
    emu.on_key_down  (key_cb!(ShellEvent::DpadDown));
    emu.on_key_left  (key_cb!(ShellEvent::DpadLeft));
    emu.on_key_right (key_cb!(ShellEvent::DpadRight));
    emu.on_key_l2({
        let emu2 = emu.as_weak(); let app2 = app.clone();
        move |held| {
            if let Some(e) = emu2.upgrade() {
                emu_handle_event(&mut app2.borrow_mut(), ShellEvent::L2Held(held), &e);
            }
        }
    });

    emu.on_key_stick_n(key_cb!(ShellEvent::StickMoved { x:  0.0, y: -0.8 }));
    emu.on_key_stick_s(key_cb!(ShellEvent::StickMoved { x:  0.0, y:  0.8 }));
    emu.on_key_stick_w(key_cb!(ShellEvent::StickMoved { x: -0.8, y:  0.0 }));
    emu.on_key_stick_e(key_cb!(ShellEvent::StickMoved { x:  0.8, y:  0.0 }));
    emu.on_key_stick_release(key_cb!(ShellEvent::StickMoved { x: 0.0, y: 0.0 }));

    emu.on_radial_dismissed(key_cb!(ShellEvent::ButtonB));
    emu.on_palette_dismissed(key_cb!(ShellEvent::ButtonB));
    emu.on_app_closed(key_cb!(ShellEvent::ButtonB));
    emu.on_switcher_dismissed({
        let emu2 = emu.as_weak();
        move || { emu2.upgrade().map(|e| e.set_switcher_visible(false)); }
    });
    emu.on_app_files_navigate({
        let emu2 = emu.as_weak(); let app2 = app.clone();
        move |name| {
            if let Some(e) = emu2.upgrade() {
                let mut a = app2.borrow_mut();
                let new_path = format!("{}/{}", a.files_path, name);
                a.files_path = new_path.clone();
                e.set_app_files_path(new_path.into());
                info!("Files navigate → {}", a.files_path);
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
    emu.on_lower_submit(key_cb!(ShellEvent::ButtonA));

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

fn emu_apply_apps(emu: &TorchformEmulator, app: &ShellApp) {
    match app.active_app {
        Some(ActiveApp::Settings) => {
            emu.set_app_settings_visible(true);
            emu.set_app_settings_focused_row(app.settings_row);
            emu.set_app_files_visible(false);
        }
        Some(ActiveApp::Files) => {
            emu.set_app_settings_visible(false);
            emu.set_app_files_visible(true);
            emu.set_app_files_focused_row(app.files_row);
            emu.set_app_files_path(app.files_path.clone().into());
        }
        None => {
            emu.set_app_settings_visible(false);
            emu.set_app_files_visible(false);
        }
    }
}

// Emulator-specific event handler
fn emu_handle_event(
    app: &mut ShellApp,
    event: ShellEvent,
    emu: &TorchformEmulator,
) {
    match event {
        ShellEvent::L2Held(true) | ShellEvent::R2Held(true) => {
            if !app.radial.visible {
                app.radial.open(MenuLayer::System, system_radial_items(&app.config.radial.system.slots));
                app.radial_stick_active = false;
                emu_apply_radial(emu, &app.radial);
                emu.set_context(LowerContext::RadialMenu);
            }
        }
        ShellEvent::L2Held(false) | ShellEvent::R2Held(false) => {
            if app.radial.visible {
                if app.radial_stick_active {
                    if let Some(item) = app.radial.focused_item() {
                        info!("Radial stick-select: {}", item.label);
                    }
                }
                // If stick was not pointing, dismiss without action.
                app.radial.close();
                app.radial_stick_active = false;
                emu_apply_radial(emu, &app.radial);
                emu.set_context(LowerContext::Idle);
            }
        }
        ShellEvent::ButtonSelect => {
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
        ShellEvent::ButtonStart => {
            let vis = !emu.get_switcher_visible();
            emu.set_switcher_visible(vis);
        }
        ShellEvent::DpadUp => {
            if app.radial.visible {
                app.radial.navigate(Direction::Up);
                emu.set_radial_focused(app.radial.focused_index as i32);
            } else if app.palette.visible {
                app.palette.move_up();
                emu.set_palette_focused(app.palette.focused_index as i32);
            } else if app.active_app.is_some() {
                match app.active_app {
                    Some(ActiveApp::Settings) => {
                        app.settings_row = (app.settings_row - 1).max(0);
                        emu.set_app_settings_focused_row(app.settings_row);
                    }
                    Some(ActiveApp::Files) => {
                        app.files_row = (app.files_row - 1).max(0);
                        emu.set_app_files_focused_row(app.files_row);
                    }
                    None => {}
                }
            }
        }
        ShellEvent::DpadDown => {
            if app.radial.visible {
                app.radial.navigate(Direction::Down);
                emu.set_radial_focused(app.radial.focused_index as i32);
            } else if app.palette.visible {
                app.palette.move_down();
                emu.set_palette_focused(app.palette.focused_index as i32);
            } else if app.active_app.is_some() {
                match app.active_app {
                    Some(ActiveApp::Settings) => {
                        app.settings_row += 1;
                        emu.set_app_settings_focused_row(app.settings_row);
                    }
                    Some(ActiveApp::Files) => {
                        app.files_row += 1;
                        emu.set_app_files_focused_row(app.files_row);
                    }
                    None => {}
                }
            }
        }
        ShellEvent::DpadLeft => {
            if app.radial.visible {
                app.radial.navigate(Direction::Left);
                emu.set_radial_focused(app.radial.focused_index as i32);
            }
        }
        ShellEvent::DpadRight => {
            if app.radial.visible {
                app.radial.navigate(Direction::Right);
                emu.set_radial_focused(app.radial.focused_index as i32);
            }
        }
        ShellEvent::ButtonA => {
            if app.radial.visible {
                if let Some(item) = app.radial.focused_item() {
                    info!("Radial activated: {}", item.label);
                }
                app.radial.close();
                emu_apply_radial(emu, &app.radial);
                emu.set_context(LowerContext::Idle);
            } else if app.palette.visible {
                if let Some(id) = app.palette.focused_id() {
                    info!("Command: {id}");
                    if !apps::try_launch_external(id, &app.config.apps) {
                        match id {
                            "app.settings" | "settings" | "open-settings" => {
                                app.active_app = Some(ActiveApp::Settings);
                                app.settings_row = 0;
                            }
                            "app.files" | "file-manager" | "open-files" => {
                                app.active_app = Some(ActiveApp::Files);
                                app.files_row = 0;
                                app.files_path = "/home".into();
                            }
                            _ => {}
                        }
                    }
                }
                app.palette.close();
                emu.set_palette_visible(false);
                emu_apply_apps(emu, app);
                emu.set_context(LowerContext::Idle);
            }
        }
        ShellEvent::ButtonB => {
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
        ShellEvent::StickMoved { x, y } => {
            app.stick_x = x;
            app.stick_y = y;
            if app.radial.visible {
                let active = app.radial.update_from_stick(x, y);
                app.radial_stick_active = active;
                emu.set_radial_focused(app.radial.focused_index as i32);
            }
        }
        ShellEvent::VoiceResult(text) => {
            if app.palette.visible {
                app.palette.set_query(&text);
                emu_apply_palette(emu, &app.palette);
            }
        }
        ShellEvent::L1Pressed | ShellEvent::R1Pressed => {
            app.workspaces.active_mut().cycle_focus();
        }
        ShellEvent::LowerTap { x, y } => {
            info!("Lower tap at ({x:.0}, {y:.0})");
        }
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
    let (gp_tx, gp_rx) = mpsc::channel::<ShellEvent>();
    spawn_gamepad_thread(gp_tx);

    // Helper for standalone event dispatch
    macro_rules! sa_cb {
        ($event:expr) => {{
            let s = shell.as_weak(); let l = lower.as_weak();
            let a = app.clone();
            move || {
                if let (Some(sh), Some(lo)) = (s.upgrade(), l.upgrade()) {
                    sa_handle_event(&mut a.borrow_mut(), $event, &sh, &lo);
                }
            }
        }};
    }

    // --- Wire keyboard callbacks -------------------------------------------
    shell.on_key_select(sa_cb!(ShellEvent::ButtonSelect));
    shell.on_key_start (sa_cb!(ShellEvent::ButtonStart));
    shell.on_key_b     (sa_cb!(ShellEvent::ButtonB));
    shell.on_key_a     (sa_cb!(ShellEvent::ButtonA));
    shell.on_key_up    (sa_cb!(ShellEvent::DpadUp));
    shell.on_key_down  (sa_cb!(ShellEvent::DpadDown));
    shell.on_key_left  (sa_cb!(ShellEvent::DpadLeft));
    shell.on_key_right (sa_cb!(ShellEvent::DpadRight));
    shell.on_key_l2({
        let s = shell.as_weak(); let l = lower.as_weak();
        let a = app.clone();
        move |held| {
            if let (Some(sh), Some(lo)) = (s.upgrade(), l.upgrade()) {
                sa_handle_event(&mut a.borrow_mut(), ShellEvent::L2Held(held), &sh, &lo);
            }
        }
    });

    // --- Analog stick simulation keys (IJKL) ---------------------------------
    shell.on_key_stick_n(sa_cb!(ShellEvent::StickMoved { x:  0.0, y: -0.8 }));
    shell.on_key_stick_s(sa_cb!(ShellEvent::StickMoved { x:  0.0, y:  0.8 }));
    shell.on_key_stick_w(sa_cb!(ShellEvent::StickMoved { x: -0.8, y:  0.0 }));
    shell.on_key_stick_e(sa_cb!(ShellEvent::StickMoved { x:  0.8, y:  0.0 }));
    shell.on_key_stick_release(sa_cb!(ShellEvent::StickMoved { x: 0.0, y: 0.0 }));

    // --- Overlay callbacks -------------------------------------------------
    shell.on_radial_dismissed({
        let s = shell.as_weak(); let l = lower.as_weak();
        let a = app.clone();
        move || {
            if let (Some(sh), Some(lo)) = (s.upgrade(), l.upgrade()) {
                sa_handle_event(&mut a.borrow_mut(), ShellEvent::ButtonB, &sh, &lo);
            }
        }
    });
    shell.on_palette_dismissed({
        let s = shell.as_weak(); let l = lower.as_weak();
        let a = app.clone();
        move || {
            if let (Some(sh), Some(lo)) = (s.upgrade(), l.upgrade()) {
                sa_handle_event(&mut a.borrow_mut(), ShellEvent::ButtonB, &sh, &lo);
            }
        }
    });
    shell.on_switcher_dismissed({
        let s = shell.as_weak();
        move || { s.upgrade().map(|sh| sh.set_switcher_visible(false)); }
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
                sa_handle_event(&mut a.borrow_mut(), ShellEvent::ButtonA, &sh, &lo);
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

fn sa_apply_apps(shell: &ShellOverlay, app: &ShellApp) {
    match app.active_app {
        Some(ActiveApp::Settings) => {
            shell.set_app_settings_visible(true);
            shell.set_app_settings_focused_row(app.settings_row);
            shell.set_app_files_visible(false);
        }
        Some(ActiveApp::Files) => {
            shell.set_app_settings_visible(false);
            shell.set_app_files_visible(true);
            shell.set_app_files_focused_row(app.files_row);
            shell.set_app_files_path(app.files_path.clone().into());
        }
        None => {
            shell.set_app_settings_visible(false);
            shell.set_app_files_visible(false);
        }
    }
}

fn sa_handle_event(
    app: &mut ShellApp,
    event: ShellEvent,
    shell: &ShellOverlay,
    lower: &LowerScreen,
) {
    match event {
        ShellEvent::L2Held(true) | ShellEvent::R2Held(true) => {
            if !app.radial.visible {
                app.radial.open(MenuLayer::System, system_radial_items(&app.config.radial.system.slots));
                app.radial_stick_active = false;
                sa_apply_radial(shell, &app.radial);
                lower.set_context(LowerContext::RadialMenu);
            }
        }
        ShellEvent::L2Held(false) | ShellEvent::R2Held(false) => {
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
        ShellEvent::ButtonSelect => {
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
        ShellEvent::ButtonStart => {
            let vis = !shell.get_switcher_visible();
            shell.set_switcher_visible(vis);
        }
        ShellEvent::DpadUp => {
            if app.radial.visible {
                app.radial.navigate(Direction::Up);
                shell.set_radial_focused(app.radial.focused_index as i32);
            } else if app.palette.visible {
                app.palette.move_up();
                shell.set_palette_focused(app.palette.focused_index as i32);
            } else if app.active_app.is_some() {
                match app.active_app {
                    Some(ActiveApp::Settings) => {
                        app.settings_row = (app.settings_row - 1).max(0);
                        shell.set_app_settings_focused_row(app.settings_row);
                    }
                    Some(ActiveApp::Files) => {
                        app.files_row = (app.files_row - 1).max(0);
                        shell.set_app_files_focused_row(app.files_row);
                    }
                    None => {}
                }
            }
        }
        ShellEvent::DpadDown => {
            if app.radial.visible {
                app.radial.navigate(Direction::Down);
                shell.set_radial_focused(app.radial.focused_index as i32);
            } else if app.palette.visible {
                app.palette.move_down();
                shell.set_palette_focused(app.palette.focused_index as i32);
            } else if app.active_app.is_some() {
                match app.active_app {
                    Some(ActiveApp::Settings) => {
                        app.settings_row += 1;
                        shell.set_app_settings_focused_row(app.settings_row);
                    }
                    Some(ActiveApp::Files) => {
                        app.files_row += 1;
                        shell.set_app_files_focused_row(app.files_row);
                    }
                    None => {}
                }
            }
        }
        ShellEvent::DpadLeft => {
            if app.radial.visible {
                app.radial.navigate(Direction::Left);
                shell.set_radial_focused(app.radial.focused_index as i32);
            }
        }
        ShellEvent::DpadRight => {
            if app.radial.visible {
                app.radial.navigate(Direction::Right);
                shell.set_radial_focused(app.radial.focused_index as i32);
            }
        }
        ShellEvent::ButtonA => {
            if app.radial.visible {
                if let Some(item) = app.radial.focused_item() {
                    info!("Radial activated: {}", item.label);
                }
                app.radial.close();
                sa_apply_radial(shell, &app.radial);
                lower.set_context(LowerContext::Idle);
            } else if app.palette.visible {
                if let Some(id) = app.palette.focused_id() {
                    info!("Command: {id}");
                    if !apps::try_launch_external(id, &app.config.apps) {
                        match id {
                            "app.settings" | "settings" | "open-settings" => {
                                app.active_app = Some(ActiveApp::Settings);
                                app.settings_row = 0;
                            }
                            "app.files" | "file-manager" | "open-files" => {
                                app.active_app = Some(ActiveApp::Files);
                                app.files_row = 0;
                                app.files_path = "/home".into();
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
        ShellEvent::ButtonB => {
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
        ShellEvent::StickMoved { x, y } => {
            app.stick_x = x;
            app.stick_y = y;
            if app.radial.visible {
                let active = app.radial.update_from_stick(x, y);
                app.radial_stick_active = active;
                shell.set_radial_focused(app.radial.focused_index as i32);
            }
        }
        ShellEvent::VoiceResult(text) => {
            if app.palette.visible {
                app.palette.set_query(&text);
                sa_apply_palette(shell, &app.palette);
            }
        }
        ShellEvent::L1Pressed | ShellEvent::R1Pressed => {
            app.workspaces.active_mut().cycle_focus();
        }
        ShellEvent::LowerTap { x, y } => {
            info!("Lower tap at ({x:.0}, {y:.0})");
        }
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
