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
use apps::AppManager;

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
}

// ---------------------------------------------------------------------------
// Application state (shared across both run modes)
// ---------------------------------------------------------------------------

struct ShellApp {
    radial:     RadialMenuState,
    palette:    PaletteState,
    workspaces: WorkspaceManager,
}

impl ShellApp {
    fn new() -> Self {
        Self {
            radial:     RadialMenuState::new(),
            palette:    PaletteState::new(),
            workspaces: WorkspaceManager::new(),
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
        loop {
            while let Some(ev) = gilrs.next_event() {
                let shell_ev = map_gilrs_event(ev.event);
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
    let emu = TorchformEmulator::new()?;

    let app     = Rc::new(RefCell::new(ShellApp::new()));
    let app_mgr = Rc::new(RefCell::new(AppManager::new()));

    // --- Gamepad channel (background thread → Slint Timer) -----------------
    let (gp_tx, gp_rx) = mpsc::channel::<ShellEvent>();
    spawn_gamepad_thread(gp_tx);

    // --- Macro: dispatch a ShellEvent from a key callback ------------------
    macro_rules! key_cb {
        ($event:expr) => {{
            let emu2    = emu.as_weak();
            let app2    = app.clone();
            let mgr2    = app_mgr.clone();
            move || {
                if let Some(e) = emu2.upgrade() {
                    emu_handle_event(&mut app2.borrow_mut(), $event,
                                     &e, &mut mgr2.borrow_mut());
                }
            }
        }};
    }

    // --- Wire keyboard callbacks -------------------------------------------
    emu.on_key_select(key_cb!(ShellEvent::ButtonSelect));
    emu.on_key_start (key_cb!(ShellEvent::ButtonStart));
    emu.on_key_b     (key_cb!(ShellEvent::ButtonB));
    emu.on_key_a     (key_cb!(ShellEvent::ButtonA));
    emu.on_key_up    (key_cb!(ShellEvent::DpadUp));
    emu.on_key_down  (key_cb!(ShellEvent::DpadDown));
    emu.on_key_left  (key_cb!(ShellEvent::DpadLeft));
    emu.on_key_right (key_cb!(ShellEvent::DpadRight));
    // Tab has a bool param (pressed/released)
    emu.on_key_l2({
        let emu2 = emu.as_weak();
        let app2 = app.clone();
        let mgr2 = app_mgr.clone();
        move |held| {
            if let Some(e) = emu2.upgrade() {
                emu_handle_event(&mut app2.borrow_mut(), ShellEvent::L2Held(held),
                                 &e, &mut mgr2.borrow_mut());
            }
        }
    });

    // --- Wire overlay dismiss callbacks ------------------------------------
    emu.on_radial_dismissed({
        let emu2 = emu.as_weak(); let app2 = app.clone(); let mgr2 = app_mgr.clone();
        move || {
            if let Some(e) = emu2.upgrade() {
                emu_handle_event(&mut app2.borrow_mut(), ShellEvent::ButtonB,
                                 &e, &mut mgr2.borrow_mut());
            }
        }
    });
    emu.on_palette_dismissed({
        let emu2 = emu.as_weak(); let app2 = app.clone(); let mgr2 = app_mgr.clone();
        move || {
            if let Some(e) = emu2.upgrade() {
                emu_handle_event(&mut app2.borrow_mut(), ShellEvent::ButtonB,
                                 &e, &mut mgr2.borrow_mut());
            }
        }
    });
    emu.on_switcher_dismissed({
        let emu2 = emu.as_weak();
        move || { emu2.upgrade().map(|e| e.set_switcher_visible(false)); }
    });

    // --- Palette query changed (virtual keyboard + voice) ------------------
    emu.on_palette_query_changed({
        let emu2 = emu.as_weak();
        let app2 = app.clone();
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

    // --- Lower keyboard callbacks ------------------------------------------
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
    emu.on_lower_submit({
        let emu2 = emu.as_weak(); let app2 = app.clone(); let mgr2 = app_mgr.clone();
        move || {
            if let Some(e) = emu2.upgrade() {
                emu_handle_event(&mut app2.borrow_mut(), ShellEvent::ButtonA,
                                 &e, &mut mgr2.borrow_mut());
            }
        }
    });

    // --- Gamepad polling timer (8 ms = ~125 Hz) ----------------------------
    let gp_timer = slint::Timer::default();
    gp_timer.start(slint::TimerMode::Repeated, Duration::from_millis(8), {
        let emu2 = emu.as_weak();
        let app2 = app.clone();
        let mgr2 = app_mgr.clone();
        move || {
            while let Ok(event) = gp_rx.try_recv() {
                if let Some(e) = emu2.upgrade() {
                    emu_handle_event(&mut app2.borrow_mut(), event,
                                     &e, &mut mgr2.borrow_mut());
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

        match demo_mode {
            Some("radial") => {
                a.radial.open(MenuLayer::System, system_radial_items());
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

// Emulator-specific event handler
fn emu_handle_event(
    app: &mut ShellApp,
    event: ShellEvent,
    emu: &TorchformEmulator,
    app_mgr: &mut AppManager,
) {
    match event {
        ShellEvent::L2Held(true) | ShellEvent::R2Held(true) => {
            if !app.radial.visible {
                app.radial.open(MenuLayer::System, system_radial_items());
                emu_apply_radial(emu, &app.radial);
                emu.set_context(LowerContext::RadialMenu);
            }
        }
        ShellEvent::L2Held(false) | ShellEvent::R2Held(false) => {
            app.radial.close();
            emu_apply_radial(emu, &app.radial);
            emu.set_context(LowerContext::Idle);
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
            }
        }
        ShellEvent::DpadDown => {
            if app.radial.visible {
                app.radial.navigate(Direction::Down);
                emu.set_radial_focused(app.radial.focused_index as i32);
            } else if app.palette.visible {
                app.palette.move_down();
                emu.set_palette_focused(app.palette.focused_index as i32);
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
                    // Try launching an app window from the command
                    if let Err(e) = app_mgr.launch(&id) {
                        tracing::warn!("App launch failed: {e}");
                    }
                }
                app.palette.close();
                emu.set_palette_visible(false);
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
            } else {
                emu.set_switcher_visible(false);
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
// Standalone mode — separate ShellOverlay (upper) + LowerScreen (lower)
// ---------------------------------------------------------------------------

fn run_standalone(demo_mode: Option<&str>) -> Result<()> {
    let shell = ShellOverlay::new()?;
    let lower = LowerScreen::new()?;

    shell.window().set_size(slint::LogicalSize::new(1280.0, 720.0));
    lower.window().set_size(slint::LogicalSize::new(640.0, 480.0));

    let app     = Rc::new(RefCell::new(ShellApp::new()));
    let app_mgr = Rc::new(RefCell::new(AppManager::new()));

    // --- Gamepad channel ---------------------------------------------------
    let (gp_tx, gp_rx) = mpsc::channel::<ShellEvent>();
    spawn_gamepad_thread(gp_tx);

    // Helper for standalone event dispatch
    macro_rules! sa_cb {
        ($event:expr) => {{
            let s = shell.as_weak(); let l = lower.as_weak();
            let a = app.clone(); let m = app_mgr.clone();
            move || {
                if let (Some(sh), Some(lo)) = (s.upgrade(), l.upgrade()) {
                    sa_handle_event(&mut a.borrow_mut(), $event,
                                    &sh, &lo, &mut m.borrow_mut());
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
        let a = app.clone(); let m = app_mgr.clone();
        move |held| {
            if let (Some(sh), Some(lo)) = (s.upgrade(), l.upgrade()) {
                sa_handle_event(&mut a.borrow_mut(), ShellEvent::L2Held(held),
                                &sh, &lo, &mut m.borrow_mut());
            }
        }
    });

    // --- Overlay callbacks -------------------------------------------------
    shell.on_radial_dismissed({
        let s = shell.as_weak(); let l = lower.as_weak();
        let a = app.clone(); let m = app_mgr.clone();
        move || {
            if let (Some(sh), Some(lo)) = (s.upgrade(), l.upgrade()) {
                sa_handle_event(&mut a.borrow_mut(), ShellEvent::ButtonB,
                                &sh, &lo, &mut m.borrow_mut());
            }
        }
    });
    shell.on_palette_dismissed({
        let s = shell.as_weak(); let l = lower.as_weak();
        let a = app.clone(); let m = app_mgr.clone();
        move || {
            if let (Some(sh), Some(lo)) = (s.upgrade(), l.upgrade()) {
                sa_handle_event(&mut a.borrow_mut(), ShellEvent::ButtonB,
                                &sh, &lo, &mut m.borrow_mut());
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
        let a = app.clone(); let m = app_mgr.clone();
        move || {
            if let (Some(sh), Some(lo)) = (s.upgrade(), l.upgrade()) {
                sa_handle_event(&mut a.borrow_mut(), ShellEvent::ButtonA,
                                &sh, &lo, &mut m.borrow_mut());
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
        let a = app.clone(); let m = app_mgr.clone();
        move || {
            while let Ok(event) = gp_rx.try_recv() {
                if let (Some(sh), Some(lo)) = (s.upgrade(), l.upgrade()) {
                    sa_handle_event(&mut a.borrow_mut(), event,
                                    &sh, &lo, &mut m.borrow_mut());
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

        match demo_mode {
            Some("radial") => {
                a.radial.open(MenuLayer::System, system_radial_items());
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

fn sa_handle_event(
    app: &mut ShellApp,
    event: ShellEvent,
    shell: &ShellOverlay,
    lower: &LowerScreen,
    app_mgr: &mut AppManager,
) {
    match event {
        ShellEvent::L2Held(true) | ShellEvent::R2Held(true) => {
            if !app.radial.visible {
                app.radial.open(MenuLayer::System, system_radial_items());
                sa_apply_radial(shell, &app.radial);
                lower.set_context(LowerContext::RadialMenu);
            }
        }
        ShellEvent::L2Held(false) | ShellEvent::R2Held(false) => {
            app.radial.close();
            sa_apply_radial(shell, &app.radial);
            lower.set_context(LowerContext::Idle);
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
            }
        }
        ShellEvent::DpadDown => {
            if app.radial.visible {
                app.radial.navigate(Direction::Down);
                shell.set_radial_focused(app.radial.focused_index as i32);
            } else if app.palette.visible {
                app.palette.move_down();
                shell.set_palette_focused(app.palette.focused_index as i32);
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
                    if let Err(e) = app_mgr.launch(&id) {
                        tracing::warn!("App launch failed: {e}");
                    }
                }
                app.palette.close();
                shell.set_palette_visible(false);
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
            } else {
                shell.set_switcher_visible(false);
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
