// =============================================================================
// settings.rs — Torchform Settings schema loader + model builder
//
// The settings display list is loaded from `settings-schema.toml` (searched
// in the same priority order as config.toml).  If no file is found the crate
// falls back to a minimal built-in default so the UI never breaks.
//
// Key types:
//   SettingsSchema   — the parsed schema (Vec<SectionDef>)
//   SectionDef       — one section header + its rows
//   RowDef           — one display row (icon, label, description, widget)
//   WidgetDef        — widget type with its parameters
//   SettingsRowData  — flat struct sent to the Slint ListView
//
// The Slint UI only sees flat SettingsRowData values (no logic, no schema).
// This file owns all read/mutation/serialisation logic.
//
// Key functions:
//   SettingsSchema::load()      — searches paths, parses TOML
//   make_settings_entries()     — schema + config → Vec<SettingsRowData>
//   apply_activation()          — "A pressed" on a row
//   apply_adjustment()          — left(-1) / right(+1) d-pad on a row
//   focus_up() / focus_down()   — skip header rows
// =============================================================================

use std::path::PathBuf;
use serde::Deserialize;

use crate::config::TorchformConfig;

// ---------------------------------------------------------------------------
// Schema types (owned Strings — loaded from TOML, not &'static)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub enum WidgetDef {
    Slider { min: i32, max: i32, step: i32 },
    Toggle,
    Select { options: Vec<String> },
    Text,
    Action,
}

#[derive(Debug, Clone)]
pub struct RowDef {
    pub key:    String,
    pub label:  String,
    pub icon:   String,
    pub desc:   String,
    pub widget: WidgetDef,
}

#[derive(Debug, Clone)]
pub struct SectionDef {
    pub id:    String,
    pub title: String,
    pub rows:  Vec<RowDef>,
}

#[derive(Debug, Clone)]
pub struct SettingsSchema {
    pub sections: Vec<SectionDef>,
}

// ---------------------------------------------------------------------------
// TOML deserialization helpers (raw shapes from file)
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
struct RawSection {
    id:    String,
    title: String,
    #[serde(default)]
    rows:  Vec<RawRow>,
}

#[derive(Debug, Deserialize)]
struct RawRow {
    key:    String,
    label:  String,
    #[serde(default)]
    icon:   String,
    #[serde(default)]
    desc:   String,
    widget: String,
    #[serde(default)]
    min:    i32,
    #[serde(default = "default_max")]
    max:    i32,
    #[serde(default = "default_step")]
    step:   i32,
    #[serde(default)]
    options: Vec<String>,
}

fn default_max()  -> i32 { 100 }
fn default_step() -> i32 { 1 }

#[derive(Debug, Deserialize)]
struct RawSchemaFile {
    #[serde(default)]
    section: Vec<RawSection>,
}

// ---------------------------------------------------------------------------
// Loading
// ---------------------------------------------------------------------------

impl SettingsSchema {
    /// Load from the first `settings-schema.toml` found in standard paths.
    /// Falls back to a minimal built-in schema if no file is found.
    pub fn load() -> Self {
        for path in schema_search_paths() {
            if path.exists() {
                match Self::load_from(&path) {
                    Ok(schema) => {
                        return schema;
                    }
                    Err(e) => {
                        eprintln!("[torchform-config] settings-schema parse error at {}: {e}", path.display());
                    }
                }
            }
        }
        eprintln!("[torchform-config] no settings-schema.toml found — using minimal built-in");
        Self::minimal()
    }

    fn load_from(path: &PathBuf) -> anyhow::Result<Self> {
        let text = std::fs::read_to_string(path)?;
        let raw: RawSchemaFile = toml::from_str(&text)?;

        let sections = raw.section.into_iter().map(|s| SectionDef {
            id:    s.id,
            title: s.title,
            rows:  s.rows.into_iter().map(row_from_raw).collect(),
        }).collect();

        Ok(Self { sections })
    }

    fn minimal() -> Self {
        Self {
            sections: vec![
                SectionDef {
                    id:    "display".into(),
                    title: "DISPLAY".into(),
                    rows:  vec![
                        RowDef { key: "display.brightness".into(), label: "Brightness".into(), icon: "🔆".into(), desc: "Screen backlight level (0–100 %)".into(), widget: WidgetDef::Slider { min: 0, max: 100, step: 5 } },
                        RowDef { key: "display.night_mode".into(),  label: "Night Mode".into(),  icon: "🌙".into(), desc: "Reduce blue light".into(), widget: WidgetDef::Toggle },
                    ],
                },
                SectionDef {
                    id:    "audio".into(),
                    title: "AUDIO".into(),
                    rows:  vec![
                        RowDef { key: "audio.volume".into(), label: "Volume".into(), icon: "🔊".into(), desc: "Master output volume (0–100 %)".into(), widget: WidgetDef::Slider { min: 0, max: 100, step: 5 } },
                    ],
                },
                SectionDef {
                    id:    "about".into(),
                    title: "ABOUT".into(),
                    rows:  vec![
                        RowDef { key: "system.firmware".into(), label: "OS Version".into(), icon: "ℹ".into(), desc: "Torchform OS build identifier".into(), widget: WidgetDef::Text },
                        RowDef { key: "system.hostname".into(), label: "Hostname".into(),   icon: "💻".into(), desc: "Device network name".into(),           widget: WidgetDef::Text },
                    ],
                },
            ],
        }
    }
}

fn row_from_raw(r: RawRow) -> RowDef {
    let widget = match r.widget.as_str() {
        "slider" => WidgetDef::Slider { min: r.min, max: r.max, step: r.step },
        "toggle" => WidgetDef::Toggle,
        "select" => WidgetDef::Select { options: r.options },
        "action" => WidgetDef::Action,
        _        => WidgetDef::Text,
    };
    RowDef { key: r.key, label: r.label, icon: r.icon, desc: r.desc, widget }
}

fn schema_search_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();
    if let Some(home) = std::env::var_os("HOME") {
        paths.push(PathBuf::from(home).join(".config/torchform/settings-schema.toml"));
    }
    paths.push(PathBuf::from("/etc/torchform/settings-schema.toml"));
    paths.push(PathBuf::from("config/settings-schema.toml"));
    paths
}

// ---------------------------------------------------------------------------
// Slint struct mirror — must match exactly what app_settings.slint exports
// ---------------------------------------------------------------------------

/// Flat row sent to the Slint ListView.
#[derive(Debug, Clone)]
pub struct SettingsRowData {
    pub widget:        String,
    pub icon:          String,
    pub label:         String,
    pub description:   String,
    pub value:         String,
    pub value_index:   i32,
    pub min:           i32,
    pub max:           i32,
    pub step:          i32,
    pub pct:           f32,
    pub key:           String,
    pub scroll_offset: i32,
}

// ---------------------------------------------------------------------------
// Build the flat Slint model from schema + config
// ---------------------------------------------------------------------------

pub fn make_settings_entries(schema: &SettingsSchema, cfg: &TorchformConfig) -> Vec<SettingsRowData> {
    const HEADER_H: i32 = 32;
    const ROW_H:    i32 = 60;

    let mut rows: Vec<SettingsRowData> = Vec::new();
    let mut offset: i32 = 0;

    for section in &schema.sections {
        rows.push(SettingsRowData {
            widget:        "header".into(),
            icon:          "".into(),
            label:         section.title.clone(),
            description:   "".into(),
            value:         "".into(),
            value_index:   0,
            min:           0,
            max:           0,
            step:          0,
            pct:           0.0,
            key:           "".into(),
            scroll_offset: offset,
        });
        offset += HEADER_H;

        for def in &section.rows {
            let value = read_value(&def.key, cfg);

            let (widget_str, min, max, step, pct, value_index) = match &def.widget {
                WidgetDef::Slider { min, max, step } => {
                    let v = read_int(&def.key, cfg).clamp(*min, *max);
                    let p = if max > min {
                        (v - min) as f32 / (max - min) as f32
                    } else { 0.0 };
                    ("slider".into(), *min, *max, *step, p, 0)
                }
                WidgetDef::Toggle => {
                    ("toggle".into(), 0, 1, 1, 0.0, 0)
                }
                WidgetDef::Select { options } => {
                    let idx = select_index(options, &value);
                    ("select".into(), 0, (options.len() as i32).saturating_sub(1), 1, 0.0, idx)
                }
                WidgetDef::Text   => ("text".into(),   0, 0, 0, 0.0, 0),
                WidgetDef::Action => ("action".into(), 0, 0, 0, 0.0, 0),
            };

            rows.push(SettingsRowData {
                widget:        widget_str,
                icon:          def.icon.clone(),
                label:         def.label.clone(),
                description:   def.desc.clone(),
                value,
                value_index,
                min,
                max,
                step,
                pct,
                key:           def.key.clone(),
                scroll_offset: offset,
            });
            offset += ROW_H;
        }

        // Dynamic dotfile rows appended after the sysapps section
        if section.id == "sysapps" {
            for entry in &cfg.dotfiles.detected {
                let label = std::path::Path::new(&entry.path)
                    .file_name()
                    .and_then(|n| n.to_str())
                    .unwrap_or(&entry.path)
                    .to_owned();
                let size_kb = if entry.size_bytes >= 1024 {
                    format!("{} KB", entry.size_bytes / 1024)
                } else {
                    format!("{} B", entry.size_bytes)
                };
                rows.push(SettingsRowData {
                    widget:        "text".into(),
                    icon:          "📄".into(),
                    label,
                    description:   format!("{} · {}", entry.format, size_kb),
                    value:         entry.path.clone(),
                    value_index:   0,
                    min:           0,
                    max:           0,
                    step:          0,
                    pct:           0.0,
                    key:           format!("sysapps.file.{}", entry.path),
                    scroll_offset: offset,
                });
                offset += ROW_H;
            }
        }
    }

    rows
}

/// Build flat rows for a single section by id.
/// Used by the two-pane settings layout so the right pane shows only the
/// rows for the active section, with scroll-offsets starting at 0.
pub fn make_section_entries(
    schema: &SettingsSchema,
    cfg: &TorchformConfig,
    section_id: &str,
) -> Vec<SettingsRowData> {
    const ROW_H: i32 = 58;

    let section = match schema.sections.iter().find(|s| s.id == section_id) {
        Some(s) => s,
        None    => return Vec::new(),
    };

    let mut rows: Vec<SettingsRowData> = Vec::new();
    let mut offset: i32 = 0;

    for def in &section.rows {
        let value = read_value(&def.key, cfg);

        let (widget_str, min, max, step, pct, value_index) = match &def.widget {
            WidgetDef::Slider { min, max, step } => {
                let v = read_int(&def.key, cfg).clamp(*min, *max);
                let p = if max > min { (v - min) as f32 / (max - min) as f32 } else { 0.0 };
                ("slider".into(), *min, *max, *step, p, 0)
            }
            WidgetDef::Toggle  => ("toggle".into(), 0, 1, 1, 0.0, 0),
            WidgetDef::Select { options } => {
                let idx = select_index(options, &value);
                ("select".into(), 0, (options.len() as i32).saturating_sub(1), 1, 0.0, idx)
            }
            WidgetDef::Text    => ("text".into(),   0, 0, 0, 0.0, 0),
            WidgetDef::Action  => ("action".into(), 0, 0, 0, 0.0, 0),
        };

        rows.push(SettingsRowData {
            widget:        widget_str,
            icon:          def.icon.clone(),
            label:         def.label.clone(),
            description:   def.desc.clone(),
            value,
            value_index,
            min, max, step, pct,
            key:           def.key.clone(),
            scroll_offset: offset,
        });
        offset += ROW_H;
    }

    // Dynamic dotfile rows for sysapps section
    if section_id == "sysapps" {
        for entry in &cfg.dotfiles.detected {
            let label = std::path::Path::new(&entry.path)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or(&entry.path)
                .to_owned();
            let size_kb = if entry.size_bytes >= 1024 {
                format!("{} KB", entry.size_bytes / 1024)
            } else {
                format!("{} B", entry.size_bytes)
            };
            rows.push(SettingsRowData {
                widget:        "text".into(),
                icon:          "📄".into(),
                label,
                description:   format!("{} · {}", entry.format, size_kb),
                value:         entry.path.clone(),
                value_index:   0,
                min: 0, max: 0, step: 0, pct: 0.0,
                key:           format!("sysapps.file.{}", entry.path),
                scroll_offset: offset,
            });
            offset += ROW_H;
        }
    }

    rows
}

// ---------------------------------------------------------------------------
// Read a live value out of TorchformConfig for a given key
// ---------------------------------------------------------------------------

fn read_value(key: &str, cfg: &TorchformConfig) -> String {
    match key {
        "display.brightness"    => cfg.general.brightness.unwrap_or(80).to_string(),
        "display.night_mode"    => "false".into(),
        "display.refresh_rate"  => "60 Hz".into(),
        "display.orientation"   => "Landscape".into(),

        "audio.volume"          => cfg.general.volume.unwrap_or(65).to_string(),
        "audio.mic_gain"        => "75".into(),
        "audio.output"          => "Built-in Speaker".into(),
        "audio.sound_fx"        => "true".into(),

        "input.haptic"          => "true".into(),
        "input.stick_deadzone"  => "10".into(),
        "input.stick_curve"     => "Quadratic".into(),
        "input.trigger_mode"    => "Analog".into(),

        "power.sleep_timeout"   => "2 min".into(),
        "power.charging_mode"   => "Fast (up to 45 W)".into(),
        "power.battery_saver"   => "false".into(),
        "power.cpu_governor"    => "Balanced".into(),
        "power.usb_charge_only" => "false".into(),

        "datetime.date"         => current_date(),
        "datetime.time"         => current_time(),
        "datetime.timezone"     => system_timezone(),
        "datetime.24h"          => "false".into(),
        "datetime.auto_set"     => "true".into(),

        "storage.emmc"          => "— GB / — GB".into(),
        "storage.usb"           => "— not mounted —".into(),
        "storage.cache"         => "—".into(),
        "storage.tmp"           => "—".into(),

        "network.wifi"          => "true".into(),
        "network.wifi_ssid"     => "— not connected —".into(),
        "network.dns"           => "—".into(),
        "network.wifi_auto"     => "true".into(),
        "network.bluetooth"     => "false".into(),
        "network.bt_device"     => "— none —".into(),
        "network.bt_auto"       => "true".into(),
        "network.bt_visible"    => "false".into(),
        "network.vpn"           => "false".into(),
        "network.vpn_provider"  => "—".into(),
        "network.vpn_server"    => "—".into(),
        "network.vpn_kill"      => "false".into(),
        "network.cellular"      => "false".into(),
        "network.roaming"       => "false".into(),
        "network.apn"           => "—".into(),
        "network.data_usage"    => "—".into(),

        "netmon.download"       => "—".into(),
        "netmon.upload"         => "—".into(),
        "netmon.latency"        => "—".into(),
        "netmon.total_today"    => "—".into(),
        "netmon.per_app"        => "false".into(),

        "security.screen_lock"  => "false".into(),
        "security.lock_timeout" => "1 min".into(),
        "security.firewall"     => "false".into(),
        "security.telemetry"    => "false".into(),

        "perms.camera"          => "—".into(),
        "perms.microphone"      => "—".into(),
        "perms.location"        => "—".into(),
        "perms.contacts"        => "—".into(),
        "perms.notifications"   => "—".into(),

        "fw.enabled"            => "false".into(),
        "fw.rule1"              => "—".into(),
        "fw.rule2"              => "—".into(),
        "fw.rule3"              => "—".into(),
        "fw.dns_leak"           => "false".into(),

        "apps.terminal"         => cfg.apps.terminal.clone(),
        "apps.browser"          => cfg.apps.browser.clone(),
        "apps.editor"           => cfg.apps.editor.clone(),
        "apps.media"            => cfg.apps.media.clone(),

        // Keybinds — display current binding string (informational)
        "keybinds.confirm"              => "button_a".into(),
        "keybinds.cancel"               => "button_b (panels only)".into(),
        "keybinds.go_home"              => "button_select".into(),
        "keybinds.open_switcher"        => "button_start".into(),
        "keybinds.open_palette"         => "button_x".into(),
        "keybinds.open_notifications"   => "l1".into(),
        "keybinds.open_quick_settings"  => "r1".into(),
        "keybinds.workspace_next"       => "l1 + x (chord)".into(),
        "keybinds.open_quick_menu"      => "l1 + r1 held 3 s".into(),
        "keybinds.lock"                 => "select_long".into(),

        "system.firmware"       => "torchform-0.1.0".into(),
        "system.kernel"         => kernel_version(),
        "system.hardware"       => "Raspberry Pi CM5".into(),
        "system.ram"            => ram_total(),
        "system.display_info"   => "1920×1080 + 640×480 DSI".into(),
        "system.modem"          => "—".into(),
        "system.hostname"       => hostname(),
        "system.storage"        => storage_summary(),
        "system.reset_defaults" => "Reset…".into(),

        "sysapps.scan"          => "Press A to scan".into(),

        _ => "—".into(),
    }
}

fn read_int(key: &str, cfg: &TorchformConfig) -> i32 {
    let s = read_value(key, cfg);
    s.parse().unwrap_or(0)
}

fn select_index(options: &[String], value: &str) -> i32 {
    options.iter().position(|o| o == value).unwrap_or(0) as i32
}

// ---------------------------------------------------------------------------
// System info helpers
// ---------------------------------------------------------------------------

fn hostname() -> String {
    std::fs::read_to_string("/etc/hostname")
        .map(|s| s.trim().to_owned())
        .unwrap_or_else(|_| "torchform".into())
}

fn storage_summary() -> String {
    "— GB / — GB".into()
}

fn kernel_version() -> String {
    std::fs::read_to_string("/proc/version")
        .ok()
        .and_then(|s| s.split_whitespace().nth(2).map(|v| v.to_owned()))
        .unwrap_or_else(|| "—".into())
}

fn ram_total() -> String {
    std::fs::read_to_string("/proc/meminfo").ok()
        .and_then(|s| {
            s.lines()
             .find(|l| l.starts_with("MemTotal:"))
             .and_then(|l| l.split_whitespace().nth(1))
             .and_then(|kb| kb.parse::<u64>().ok())
             .map(|kb| format!("{} MB", kb / 1024))
        })
        .unwrap_or_else(|| "—".into())
}

fn current_date() -> String {
    // Basic date from system time — no chrono dep needed
    use std::time::{SystemTime, UNIX_EPOCH};
    let secs = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs();
    let days_since_epoch = secs / 86400;
    // Use a rough heuristic; we just need something readable in the UI stub
    let year = 1970 + days_since_epoch / 365;
    format!("{}", year)
}

fn current_time() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let secs = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs();
    let h = (secs % 86400) / 3600;
    let m = (secs % 3600) / 60;
    format!("{:02}:{:02}", h, m)
}

fn system_timezone() -> String {
    std::fs::read_to_string("/etc/timezone")
        .map(|s| s.trim().to_owned())
        .unwrap_or_else(|_| "UTC".into())
}

// ---------------------------------------------------------------------------
// Mutation helpers — called by main.rs from d-pad / A-button events
// ---------------------------------------------------------------------------

/// Called when the user presses A (confirm) on a settings row.
/// Returns true if the config was modified (and should be saved).
pub fn apply_activation(key: &str, cfg: &mut TorchformConfig) -> bool {
    match key {
        // Toggles
        "display.night_mode"
        | "audio.sound_fx"
        | "input.haptic"
        | "power.battery_saver"
        | "power.usb_charge_only"
        | "datetime.24h"
        | "datetime.auto_set"
        | "network.wifi"
        | "network.wifi_auto"
        | "network.bluetooth"
        | "network.bt_auto"
        | "network.bt_visible"
        | "network.vpn"
        | "network.vpn_kill"
        | "network.cellular"
        | "network.roaming"
        | "netmon.per_app"
        | "security.screen_lock"
        | "security.firewall"
        | "security.telemetry"
        | "fw.enabled"
        | "fw.dns_leak" => apply_toggle(key, cfg),

        "system.reset_defaults" => {
            reset_to_defaults(cfg);
            true
        }
        _ => false,
    }
}

/// Called when the user presses left (delta=-1) or right (delta=+1) on a row.
/// Returns true if the config was modified.
pub fn apply_adjustment(key: &str, delta: i32, cfg: &mut TorchformConfig, schema: &SettingsSchema) -> bool {
    let def = schema.sections.iter()
        .flat_map(|s| s.rows.iter())
        .find(|d| d.key == key);

    let Some(def) = def else { return false };

    match &def.widget {
        WidgetDef::Slider { min, max, step } => {
            let cur = read_int(key, cfg);
            let next = (cur + delta * step).clamp(*min, *max);
            write_int(key, next, cfg)
        }
        WidgetDef::Toggle => apply_toggle(key, cfg),
        WidgetDef::Select { options } => {
            let cur_val = read_value(key, cfg);
            let cur_idx = select_index(options, &cur_val);
            let next_idx = (cur_idx + delta).clamp(0, (options.len() as i32).saturating_sub(1));
            write_string(key, &options[next_idx as usize], cfg)
        }
        WidgetDef::Text | WidgetDef::Action => false,
    }
}

// ---------------------------------------------------------------------------
// Write helpers — commit new values back to TorchformConfig
// ---------------------------------------------------------------------------

fn apply_toggle(_key: &str, _cfg: &mut TorchformConfig) -> bool {
    // Toggle fields not yet backed by TorchformConfig fields return false;
    // they will be wired to system daemons in a later phase.
    false
}

fn write_int(key: &str, value: i32, cfg: &mut TorchformConfig) -> bool {
    match key {
        "display.brightness" => {
            cfg.general.brightness = Some(value as u8);
            true
        }
        "audio.volume" => {
            cfg.general.volume = Some(value as u8);
            true
        }
        _ => false,
    }
}

fn write_string(_key: &str, _value: &str, _cfg: &mut TorchformConfig) -> bool {
    false
}

fn reset_to_defaults(cfg: &mut TorchformConfig) {
    cfg.general.brightness = Some(80);
    cfg.general.volume      = Some(65);
}

// ---------------------------------------------------------------------------
// Focused-row navigation helpers — skip over header rows
// ---------------------------------------------------------------------------

/// Move focus up, skipping header rows. Returns the new index.
pub fn focus_up(current: usize, rows: &[SettingsRowData]) -> usize {
    let mut idx = current;
    loop {
        if idx == 0 { return current; }
        idx -= 1;
        if rows[idx].widget != "header" {
            return idx;
        }
    }
}

/// Move focus down, skipping header rows. Returns the new index.
pub fn focus_down(current: usize, rows: &[SettingsRowData]) -> usize {
    let mut idx = current;
    loop {
        idx += 1;
        if idx >= rows.len() { return current; }
        if rows[idx].widget != "header" {
            return idx;
        }
    }
}
