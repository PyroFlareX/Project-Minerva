// =============================================================================
// settings.rs — Torchform Settings schema + model builder
//
// The settings app is driven by a static schema (SettingsDef).  Each entry
// describes a single configurable option: its display metadata, which widget
// to use, where to read/write the value in TorchformConfig, and its
// constraints (min/max/step for sliders, options list for selects).
//
// The Slint UI only sees flat SettingsEntry values (no logic, no schema).
// This file owns all the mutation and serialisation logic.
//
// Key design rules:
//   • Schema is static (`&'static [SettingsDef]`).
//   • Values are always read live from the config — no separate model state.
//   • `make_settings_entries` converts schema + config → Slint SettingsEntry[].
//     It also pre-calculates `scroll_offset` (cumulative pixel offset) for
//     each row so the Slint centred-scroll formula is purely arithmetic.
//   • `apply_activation` handles "A pressed" on a row (toggle/action).
//   • `apply_adjustment` handles left(-1)/right(+1) d-pad on a row.
//     Both mutate the config in-place and return true if a save is needed.
// =============================================================================

use crate::config::TorchformConfig;

// ---------------------------------------------------------------------------
// SettingsDef — describes one option in the settings schema
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy)]
pub enum Widget {
    Slider { min: i32, max: i32, step: i32 },
    Toggle,
    Select { options: &'static [&'static str] },
    Text,
    Action,
}

#[derive(Debug, Clone, Copy)]
pub struct SettingsDef {
    pub key:         &'static str,
    pub widget:      Widget,
    pub icon:        &'static str,
    pub label:       &'static str,
    pub description: &'static str,
}

// ---------------------------------------------------------------------------
// Static settings schema — sections and rows in display order
// ---------------------------------------------------------------------------
//
// A "header" pseudo-row is represented as None in the flat list (see
// SCHEMA_SECTIONS below); we synthesise header SettingsEntry values there.

pub struct Section {
    pub title:    &'static str,
    pub entries:  &'static [SettingsDef],
}

pub static SCHEMA: &[Section] = &[
    Section {
        title: "DISPLAY",
        entries: &[
            SettingsDef {
                key:         "display.brightness",
                widget:      Widget::Slider { min: 0, max: 100, step: 5 },
                icon:        "🔆",
                label:       "Brightness",
                description: "Screen backlight level (0–100 %)",
            },
            SettingsDef {
                key:         "display.night_mode",
                widget:      Widget::Toggle,
                icon:        "🌙",
                label:       "Night Mode",
                description: "Reduce blue light for low-light environments",
            },
            SettingsDef {
                key:         "display.resolution",
                widget:      Widget::Select {
                    options: &["1920×1080", "1280×720", "960×540"],
                },
                icon:        "📐",
                label:       "Resolution",
                description: "Output resolution of the upper display",
            },
            SettingsDef {
                key:         "display.refresh_rate",
                widget:      Widget::Select {
                    options: &["60 Hz", "90 Hz", "120 Hz"],
                },
                icon:        "⚡",
                label:       "Refresh Rate",
                description: "Upper display refresh rate",
            },
            SettingsDef {
                key:         "display.orientation",
                widget:      Widget::Select {
                    options: &["Landscape", "Portrait", "Landscape (flipped)"],
                },
                icon:        "↔",
                label:       "Orientation",
                description: "Display rotation",
            },
        ],
    },
    Section {
        title: "AUDIO",
        entries: &[
            SettingsDef {
                key:         "audio.volume",
                widget:      Widget::Slider { min: 0, max: 100, step: 5 },
                icon:        "🔊",
                label:       "Volume",
                description: "Master output volume (0–100 %)",
            },
            SettingsDef {
                key:         "audio.mic_gain",
                widget:      Widget::Slider { min: 0, max: 100, step: 5 },
                icon:        "🎙",
                label:       "Mic Gain",
                description: "Microphone input gain (0–100 %)",
            },
            SettingsDef {
                key:         "audio.output",
                widget:      Widget::Select {
                    options: &["Built-in Speaker", "Headphones", "Bluetooth", "HDMI"],
                },
                icon:        "🎧",
                label:       "Output Device",
                description: "Where audio is routed",
            },
            SettingsDef {
                key:         "audio.sound_fx",
                widget:      Widget::Toggle,
                icon:        "🎵",
                label:       "UI Sound Effects",
                description: "Play navigation and confirmation sounds",
            },
        ],
    },
    Section {
        title: "CONNECTIVITY",
        entries: &[
            SettingsDef {
                key:         "network.wifi",
                widget:      Widget::Toggle,
                icon:        "📶",
                label:       "Wi-Fi",
                description: "Enable or disable the wireless radio",
            },
            SettingsDef {
                key:         "network.wifi_ssid",
                widget:      Widget::Text,
                icon:        "🌐",
                label:       "Network",
                description: "Currently connected SSID",
            },
            SettingsDef {
                key:         "network.bluetooth",
                widget:      Widget::Toggle,
                icon:        "🔵",
                label:       "Bluetooth",
                description: "Enable or disable Bluetooth",
            },
            SettingsDef {
                key:         "network.cellular",
                widget:      Widget::Toggle,
                icon:        "📡",
                label:       "Cellular Data",
                description: "Enable or disable mobile data (LTE/5G)",
            },
            SettingsDef {
                key:         "network.vpn",
                widget:      Widget::Toggle,
                icon:        "🛡",
                label:       "VPN",
                description: "Connect to the configured VPN tunnel",
            },
            SettingsDef {
                key:         "network.hotspot",
                widget:      Widget::Toggle,
                icon:        "📳",
                label:       "Hotspot",
                description: "Share cellular connection over Wi-Fi",
            },
        ],
    },
    Section {
        title: "INPUT",
        entries: &[
            SettingsDef {
                key:         "input.haptic",
                widget:      Widget::Toggle,
                icon:        "📳",
                label:       "Haptic Feedback",
                description: "Vibrate motor on button press",
            },
            SettingsDef {
                key:         "input.stick_deadzone",
                widget:      Widget::Slider { min: 0, max: 40, step: 2 },
                icon:        "🕹",
                label:       "Stick Deadzone",
                description: "Analog stick dead-zone radius (0–40 %)",
            },
            SettingsDef {
                key:         "input.stick_curve",
                widget:      Widget::Select {
                    options: &["Linear", "Quadratic", "Cubic"],
                },
                icon:        "📈",
                label:       "Stick Curve",
                description: "Analog input response curve",
            },
            SettingsDef {
                key:         "input.trigger_mode",
                widget:      Widget::Select {
                    options: &["Analog", "Digital"],
                },
                icon:        "🎮",
                label:       "Trigger Mode",
                description: "L2/R2 treated as analog or binary",
            },
        ],
    },
    Section {
        title: "POWER",
        entries: &[
            SettingsDef {
                key:         "power.sleep_timeout",
                widget:      Widget::Select {
                    options: &["30 s", "1 min", "2 min", "5 min", "Never"],
                },
                icon:        "⏱",
                label:       "Sleep Timeout",
                description: "Auto-sleep delay when idle",
            },
            SettingsDef {
                key:         "power.charging_mode",
                widget:      Widget::Select {
                    options: &["Fast (up to 45 W)", "Standard (15 W)", "Trickle (5 W)"],
                },
                icon:        "⚡",
                label:       "Charging Mode",
                description: "USB-C charge rate limiter",
            },
            SettingsDef {
                key:         "power.battery_saver",
                widget:      Widget::Toggle,
                icon:        "🔋",
                label:       "Battery Saver",
                description: "Reduce performance to extend battery life",
            },
        ],
    },
    Section {
        title: "PRIVACY & SECURITY",
        entries: &[
            SettingsDef {
                key:         "security.screen_lock",
                widget:      Widget::Toggle,
                icon:        "🔒",
                label:       "Screen Lock",
                description: "Require PIN / pattern to unlock",
            },
            SettingsDef {
                key:         "security.lock_timeout",
                widget:      Widget::Select {
                    options: &["Immediately", "30 s", "1 min", "5 min"],
                },
                icon:        "⏲",
                label:       "Lock After",
                description: "Auto-lock delay after sleep",
            },
            SettingsDef {
                key:         "security.telemetry",
                widget:      Widget::Toggle,
                icon:        "📊",
                label:       "Usage Analytics",
                description: "Send anonymised crash reports",
            },
        ],
    },
    Section {
        title: "APPS",
        entries: &[
            SettingsDef {
                key:         "apps.terminal",
                widget:      Widget::Text,
                icon:        "⬛",
                label:       "Terminal Emulator",
                description: "Binary launched by app.terminal",
            },
            SettingsDef {
                key:         "apps.browser",
                widget:      Widget::Text,
                icon:        "🌐",
                label:       "Web Browser",
                description: "Binary launched by app.browser",
            },
            SettingsDef {
                key:         "apps.editor",
                widget:      Widget::Text,
                icon:        "✏",
                label:       "Text Editor",
                description: "Binary launched by app.editor",
            },
            SettingsDef {
                key:         "apps.media",
                widget:      Widget::Text,
                icon:        "🎵",
                label:       "Media Player",
                description: "Binary launched by app.media",
            },
        ],
    },
    Section {
        title: "SYSTEM",
        entries: &[
            SettingsDef {
                key:         "system.hostname",
                widget:      Widget::Text,
                icon:        "💻",
                label:       "Hostname",
                description: "Device network name",
            },
            SettingsDef {
                key:         "system.firmware",
                widget:      Widget::Text,
                icon:        "ℹ",
                label:       "Firmware Version",
                description: "Torchform OS build identifier",
            },
            SettingsDef {
                key:         "system.storage",
                widget:      Widget::Text,
                icon:        "💾",
                label:       "Storage",
                description: "NVMe usage summary",
            },
            SettingsDef {
                key:         "system.reset_defaults",
                widget:      Widget::Action,
                icon:        "🔄",
                label:       "Reset to Defaults",
                description: "Restore all settings to factory values",
            },
        ],
    },
];

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
// Read a live value out of TorchformConfig for a given key
// ---------------------------------------------------------------------------

fn read_value(key: &str, cfg: &TorchformConfig) -> String {
    match key {
        "display.brightness"    => cfg.general.brightness.unwrap_or(80).to_string(),
        "display.night_mode"    => "false".into(),
        "display.resolution"    => "1920×1080".into(),
        "display.refresh_rate"  => "60 Hz".into(),
        "display.orientation"   => "Landscape".into(),

        "audio.volume"          => cfg.general.volume.unwrap_or(65).to_string(),
        "audio.mic_gain"        => "75".into(),
        "audio.output"          => "Built-in Speaker".into(),
        "audio.sound_fx"        => "true".into(),

        "network.wifi"          => "true".into(),
        "network.wifi_ssid"     => "— not connected —".into(),
        "network.bluetooth"     => "false".into(),
        "network.cellular"      => "false".into(),
        "network.vpn"           => "false".into(),
        "network.hotspot"       => "false".into(),

        "input.haptic"          => "true".into(),
        "input.stick_deadzone"  => "10".into(),
        "input.stick_curve"     => "Quadratic".into(),
        "input.trigger_mode"    => "Analog".into(),

        "power.sleep_timeout"   => "2 min".into(),
        "power.charging_mode"   => "Fast (up to 45 W)".into(),
        "power.battery_saver"   => "false".into(),

        "security.screen_lock"  => "false".into(),
        "security.lock_timeout" => "1 min".into(),
        "security.telemetry"    => "false".into(),

        "apps.terminal"         => cfg.apps.terminal.clone(),
        "apps.browser"          => cfg.apps.browser.clone(),
        "apps.editor"           => cfg.apps.editor.clone(),
        "apps.media"            => cfg.apps.media.clone(),

        "system.hostname"       => hostname(),
        "system.firmware"       => "torchform-0.1.0".into(),
        "system.storage"        => storage_summary(),
        "system.reset_defaults" => "Reset…".into(),

        _ => "—".into(),
    }
}

fn hostname() -> String {
    std::fs::read_to_string("/etc/hostname")
        .map(|s| s.trim().to_owned())
        .unwrap_or_else(|_| "torchform".into())
}

fn storage_summary() -> String {
    // Try to get disk usage via statvfs-style read; fall back to placeholder.
    use std::path::Path;
    if Path::new("/").exists() {
        // Very simple: read /proc/mounts and pick the root filesystem size.
        // For the emulator we just return a placeholder.
        "— GB / — GB".into()
    } else {
        "unknown".into()
    }
}

// ---------------------------------------------------------------------------
// Convert a string value back to integer for slider keys
// ---------------------------------------------------------------------------

fn read_int(key: &str, cfg: &TorchformConfig) -> i32 {
    let s = read_value(key, cfg);
    s.parse().unwrap_or(0)
}

// ---------------------------------------------------------------------------
// Find the option index for a Select widget
// ---------------------------------------------------------------------------

fn select_index(options: &[&str], value: &str) -> i32 {
    options.iter().position(|&o| o == value).unwrap_or(0) as i32
}

// ---------------------------------------------------------------------------
// Build the flat Slint model from schema + config
// ---------------------------------------------------------------------------

pub fn make_settings_entries(cfg: &TorchformConfig) -> Vec<SettingsRowData> {
    const HEADER_H: i32 = 32;
    const ROW_H: i32 = 60;

    let mut rows: Vec<SettingsRowData> = Vec::new();
    let mut offset: i32 = 0;

    for section in SCHEMA {
        // Section header pseudo-row
        rows.push(SettingsRowData {
            widget:        "header".into(),
            icon:          "".into(),
            label:         section.title.into(),
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

        for def in section.entries {
            let value = read_value(def.key, cfg);

            let (widget_str, min, max, step, pct, value_index) = match def.widget {
                Widget::Slider { min, max, step } => {
                    let v = read_int(def.key, cfg).clamp(min, max);
                    let p = if max > min {
                        (v - min) as f32 / (max - min) as f32
                    } else {
                        0.0
                    };
                    ("slider".into(), min, max, step, p, 0)
                }
                Widget::Toggle => {
                    ("toggle".into(), 0, 1, 1, 0.0, 0)
                }
                Widget::Select { options } => {
                    let idx = select_index(options, &value);
                    ("select".into(), 0, (options.len() as i32) - 1, 1, 0.0, idx)
                }
                Widget::Text => {
                    ("text".into(), 0, 0, 0, 0.0, 0)
                }
                Widget::Action => {
                    ("action".into(), 0, 0, 0, 0.0, 0)
                }
            };

            rows.push(SettingsRowData {
                widget:        widget_str,
                icon:          def.icon.into(),
                label:         def.label.into(),
                description:   def.description.into(),
                value,
                value_index,
                min,
                max,
                step,
                pct,
                key:           def.key.into(),
                scroll_offset: offset,
            });
            offset += ROW_H;
        }
    }

    rows
}

// ---------------------------------------------------------------------------
// Mutation helpers — called by main.rs from d-pad / A-button events
// ---------------------------------------------------------------------------

/// Called when the user presses A (confirm) on a settings row.
/// Returns true if the config was modified (and should be saved).
pub fn apply_activation(key: &str, cfg: &mut TorchformConfig) -> bool {
    match key {
        "display.night_mode"
        | "audio.sound_fx"
        | "network.wifi"
        | "network.bluetooth"
        | "network.cellular"
        | "network.vpn"
        | "network.hotspot"
        | "input.haptic"
        | "power.battery_saver"
        | "security.screen_lock"
        | "security.telemetry" => apply_toggle(key, cfg),

        "system.reset_defaults" => {
            reset_to_defaults(cfg);
            true
        }
        _ => false,
    }
}

/// Called when the user presses left (delta=-1) or right (delta=+1) on a row.
/// Returns true if the config was modified.
pub fn apply_adjustment(key: &str, delta: i32, cfg: &mut TorchformConfig) -> bool {
    // Find the SettingsDef for this key
    let def = SCHEMA.iter()
        .flat_map(|s| s.entries.iter())
        .find(|d| d.key == key);

    let Some(def) = def else { return false };

    match def.widget {
        Widget::Slider { min, max, step } => {
            let cur = read_int(key, cfg);
            let next = (cur + delta * step).clamp(min, max);
            write_int(key, next, cfg)
        }
        Widget::Toggle => apply_toggle(key, cfg),
        Widget::Select { options } => {
            let cur_val = read_value(key, cfg);
            let cur_idx = select_index(options, &cur_val);
            let next_idx = (cur_idx + delta).clamp(0, (options.len() as i32) - 1);
            write_string(key, options[next_idx as usize], cfg)
        }
        Widget::Text | Widget::Action => false,
    }
}

// ---------------------------------------------------------------------------
// Write helpers — commit new values back to TorchformConfig
// ---------------------------------------------------------------------------

fn apply_toggle(key: &str, cfg: &mut TorchformConfig) -> bool {
    // For now only the keys that are actually stored in TorchformConfig are
    // persisted; the rest are conceptual (will be wired to daemons later).
    let _ = (key, cfg);
    // All toggles currently just refresh the UI without persisting;
    // return false so we don't trigger a file write for unimplemented fields.
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
    // Select values for display/audio/network will be wired to system calls
    // in a later phase; for now return false (no config file change needed).
    false
}

fn reset_to_defaults(cfg: &mut TorchformConfig) {
    cfg.general.brightness = Some(80);
    cfg.general.volume      = Some(65);
}

// ---------------------------------------------------------------------------
// Focused-row navigation helpers — skip over header rows
// ---------------------------------------------------------------------------

/// Move focus up, skipping header rows.  Returns the new index.
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

/// Move focus down, skipping header rows.  Returns the new index.
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
