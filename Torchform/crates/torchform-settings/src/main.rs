// =============================================================================
// torchform-settings — Standalone Torchform Settings app
//
// This binary runs as a Wayland client on the real DE (launched by
// torchform-shell via torchform-run) and also as a standalone window
// for desktop development (arrow keys navigate, Enter confirms, Esc closes).
//
// Config and settings schema come from the shared `torchform-config` crate.
// =============================================================================

slint::include_modules!();

use std::{cell::RefCell, rc::Rc};
use anyhow::Result;
use torchform_config as cfg;
use tracing::info;

fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("torchform_settings=info".parse().unwrap()),
        )
        .init();

    info!("torchform-settings starting");

    let config_rc = Rc::new(RefCell::new(cfg::TorchformConfig::load()));
    let schema_rc = Rc::new(cfg::SettingsSchema::load());

    let win = SettingsWindow::new()?;

    // Helper: rebuild Slint model from current config
    let refresh = {
        let win2 = win.as_weak();
        let cfg2 = config_rc.clone();
        let schema2 = schema_rc.clone();
        move || {
            if let Some(w) = win2.upgrade() {
                let c = cfg2.borrow();
                let rows = cfg::make_settings_entries(schema2.as_ref(), &c);
                w.set_entries(rows_to_slint(&rows));
            }
        }
    };

    refresh();

    // Prime focused row to first non-header
    let focused = Rc::new(RefCell::new({
        let c = config_rc.borrow();
        let rows = cfg::make_settings_entries(schema_rc.as_ref(), &c);
        cfg::focus_down(0, &rows)
    }));
    win.set_focused_row(*focused.borrow() as i32);

    // --- Callbacks ----------------------------------------------------------

    win.on_setting_activated({
        let win2 = win.as_weak(); let cfg2 = config_rc.clone();
        let schema2 = schema_rc.clone();
        let focused2 = focused.clone();
        move |key| {
            if let Some(w) = win2.upgrade() {
                let mut c = cfg2.borrow_mut();
                let changed = cfg::apply_activation(key.as_str(), &mut c);
                if changed { let _ = c.save(&cfg::user_config_path()); }
                let rows = cfg::make_settings_entries(schema2.as_ref(), &c);
                w.set_entries(rows_to_slint(&rows));
                w.set_focused_row(*focused2.borrow() as i32);
            }
        }
    });

    win.on_setting_adjusted({
        let win2 = win.as_weak(); let cfg2 = config_rc.clone();
        let schema2 = schema_rc.clone();
        let focused2 = focused.clone();
        move |key, delta| {
            if let Some(w) = win2.upgrade() {
                let mut c = cfg2.borrow_mut();
                let changed = cfg::apply_adjustment(key.as_str(), delta, &mut c, schema2.as_ref());
                if changed { let _ = c.save(&cfg::user_config_path()); }
                let rows = cfg::make_settings_entries(schema2.as_ref(), &c);
                w.set_entries(rows_to_slint(&rows));
                w.set_focused_row(*focused2.borrow() as i32);
            }
        }
    });

    win.on_close_requested({
        let win2 = win.as_weak();
        move || { win2.upgrade().map(|w| w.hide().ok()); }
    });

    win.on_action_nav_up({
        let win2 = win.as_weak(); let cfg2 = config_rc.clone();
        let schema2 = schema_rc.clone();
        let focused2 = focused.clone();
        move || {
            if let Some(w) = win2.upgrade() {
                let c = cfg2.borrow();
                let rows = cfg::make_settings_entries(schema2.as_ref(), &c);
                let next = cfg::focus_up(*focused2.borrow(), &rows);
                *focused2.borrow_mut() = next;
                w.set_focused_row(next as i32);
            }
        }
    });

    win.on_action_nav_down({
        let win2 = win.as_weak(); let cfg2 = config_rc.clone();
        let schema2 = schema_rc.clone();
        let focused2 = focused.clone();
        move || {
            if let Some(w) = win2.upgrade() {
                let c = cfg2.borrow();
                let rows = cfg::make_settings_entries(schema2.as_ref(), &c);
                let next = cfg::focus_down(*focused2.borrow(), &rows);
                *focused2.borrow_mut() = next;
                w.set_focused_row(next as i32);
            }
        }
    });

    win.on_action_nav_left({
        let win2 = win.as_weak(); let cfg2 = config_rc.clone();
        let schema2 = schema_rc.clone();
        let focused2 = focused.clone();
        move || {
            let idx = *focused2.borrow();
            let rows = cfg::make_settings_entries(schema2.as_ref(), &cfg2.borrow());
            if let Some(entry) = rows.get(idx) {
                let key = entry.key.clone();
                let changed = cfg::apply_adjustment(&key, -1, &mut cfg2.borrow_mut(), schema2.as_ref());
                if changed { let _ = cfg2.borrow().save(&cfg::user_config_path()); }
                if let Some(w) = win2.upgrade() {
                    w.set_entries(rows_to_slint(&cfg::make_settings_entries(schema2.as_ref(), &cfg2.borrow())));
                    w.set_focused_row(idx as i32);
                }
            }
        }
    });

    win.on_action_nav_right({
        let win2 = win.as_weak(); let cfg2 = config_rc.clone();
        let schema2 = schema_rc.clone();
        let focused2 = focused.clone();
        move || {
            let idx = *focused2.borrow();
            let rows = cfg::make_settings_entries(schema2.as_ref(), &cfg2.borrow());
            if let Some(entry) = rows.get(idx) {
                let key = entry.key.clone();
                let changed = cfg::apply_adjustment(&key, 1, &mut cfg2.borrow_mut(), schema2.as_ref());
                if changed { let _ = cfg2.borrow().save(&cfg::user_config_path()); }
                if let Some(w) = win2.upgrade() {
                    w.set_entries(rows_to_slint(&cfg::make_settings_entries(schema2.as_ref(), &cfg2.borrow())));
                    w.set_focused_row(idx as i32);
                }
            }
        }
    });

    win.on_action_confirm({
        let win2 = win.as_weak(); let cfg2 = config_rc.clone();
        let schema2 = schema_rc.clone();
        let focused2 = focused.clone();
        move || {
            let idx = *focused2.borrow();
            let rows = cfg::make_settings_entries(schema2.as_ref(), &cfg2.borrow());
            if let Some(entry) = rows.get(idx) {
                let key = entry.key.clone();
                let changed = cfg::apply_activation(&key, &mut cfg2.borrow_mut());
                if changed { let _ = cfg2.borrow().save(&cfg::user_config_path()); }
                if let Some(w) = win2.upgrade() {
                    w.set_entries(rows_to_slint(&cfg::make_settings_entries(schema2.as_ref(), &cfg2.borrow())));
                    w.set_focused_row(idx as i32);
                }
            }
        }
    });

    win.on_action_cancel({
        let win2 = win.as_weak();
        move || { win2.upgrade().map(|w| w.hide().ok()); }
    });

    win.run()?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Convert SettingsRowData vec → Slint SettingsEntry model
// ---------------------------------------------------------------------------

fn rows_to_slint(rows: &[cfg::SettingsRowData]) -> slint::ModelRc<SettingsEntry> {
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
