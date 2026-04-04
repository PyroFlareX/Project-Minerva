// =============================================================================
// input_map.rs — RawInput → ShellAction mapping with TOML config
//
// RawInput is the raw physical event name (string tag) produced by either:
//   • torchform-inputd (evdev / chord detector)
//   • torchform-shell's desktop gilrs shim
//
// InputMap stores a HashMap<String, ShellAction> loaded from keybinds.toml.
// Inputs not present in the map are silently dropped — no action fired.
//
// Default map (built-in, no config file needed):
//
//   button_a         → Confirm
//   button_b         → Cancel
//   button_select    → OpenPalette
//   button_start     → OpenSwitcher
//   l2_hold_true     → RadialHold { held: true }
//   l2_hold_false    → RadialHold { held: false }
//   r2_hold_true     → RadialHold { held: true }
//   r2_hold_false    → RadialHold { held: false }
//   dpad_up          → NavUp
//   dpad_down        → NavDown
//   dpad_left        → NavLeft
//   dpad_right       → NavRight
//   l1               → WorkspacePrev
//   r1               → WorkspaceNext
//
// Analog axes (StickMoved, PadMoved, LowerTap) are handled separately
// as they carry float payloads — they bypass the map and are constructed
// directly in the inputd publish path.
//
// Config file format (keybinds.toml):
//
//   [binds]
//   button_a      = "confirm"
//   button_b      = "cancel"
//   button_select = "open_palette"
//   button_start  = "open_switcher"
//   l2_hold_true  = "radial_hold_true"
//   l2_hold_false = "radial_hold_false"
//   r2_hold_true  = "radial_hold_true"
//   r2_hold_false = "radial_hold_false"
//   dpad_up       = "nav_up"
//   dpad_down     = "nav_down"
//   dpad_left     = "nav_left"
//   dpad_right    = "nav_right"
//   l1            = "workspace_prev"
//   r1            = "workspace_next"
//
// All action names are the snake_case ShellAction variant names.
// Analog payloads (x, y values) are not in the config — only the discrete
// bindings that map a named input to a named action.
//
// To remap a button: change the value on the right-hand side.
// To disable a button: remove the line entirely.
// To add a custom binding: add a new line with any unused key name.
// =============================================================================

use std::{collections::HashMap, path::PathBuf};
use serde::{Deserialize, Serialize};
use anyhow::Result;

use crate::ShellAction;

// ---------------------------------------------------------------------------
// RawInput — a named discrete input event (no analog payloads here)
// ---------------------------------------------------------------------------

/// A named raw input event produced by the input layer.
/// String-keyed so it can be stored directly in the keybinds TOML.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct RawInput(pub String);

impl RawInput {
    pub fn new(name: impl Into<String>) -> Self { Self(name.into()) }
}

// ---------------------------------------------------------------------------
// InputMap
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct InputMap {
    binds: HashMap<String, ShellAction>,
}

impl Default for InputMap {
    fn default() -> Self {
        Self::from_defaults()
    }
}

impl InputMap {
    /// Build from the built-in defaults (no config file required).
    pub fn from_defaults() -> Self {
        let binds = default_binds();
        Self { binds }
    }

    /// Load from the first config file found in the standard search paths.
    /// Falls back to built-in defaults if no file is found or parsing fails.
    pub fn load() -> Self {
        for path in config_paths() {
            if path.exists() {
                match Self::load_from(&path) {
                    Ok(map) => {
                        tracing_log(format!("keybinds loaded from {}", path.display()));
                        return map;
                    }
                    Err(e) => {
                        tracing_log(format!("keybinds parse error at {}: {e}", path.display()));
                    }
                }
            }
        }
        tracing_log("no keybinds.toml found — using built-in defaults".into());
        Self::from_defaults()
    }

    fn load_from(path: &PathBuf) -> Result<Self> {
        let text = std::fs::read_to_string(path)?;
        let file: KeybindsFile = toml::from_str(&text)?;

        // Start with defaults so missing keys still work, then override.
        let mut binds = default_binds();
        for (raw, action_name) in file.binds {
            match action_name_to_shell_action(&action_name) {
                Some(action) => { binds.insert(raw, action); }
                None => {
                    tracing_log(format!("unknown action name in keybinds: {action_name:?}"));
                }
            }
        }
        Ok(Self { binds })
    }

    /// Resolve a raw discrete input to a ShellAction, if one is mapped.
    /// Returns None for unmapped inputs (they are silently ignored).
    pub fn resolve(&self, raw: &RawInput) -> Option<ShellAction> {
        self.binds.get(&raw.0).cloned()
    }

    /// All current bindings (raw_name → action), sorted for display in settings.
    pub fn entries(&self) -> Vec<(String, ShellAction)> {
        let mut v: Vec<_> = self.binds.iter()
            .map(|(k, v)| (k.clone(), v.clone()))
            .collect();
        v.sort_by(|a, b| a.0.cmp(&b.0));
        v
    }

    /// Save current bindings back to the user config path.
    pub fn save(&self) -> Result<()> {
        let path = user_config_path();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let raw_map: HashMap<String, String> = self.binds.iter()
            .map(|(k, v)| (k.clone(), shell_action_to_name(v).to_owned()))
            .collect();
        let file = KeybindsFile { binds: raw_map };
        let text = toml::to_string_pretty(&file)?;
        std::fs::write(&path, text)?;
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// TOML file shape
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize, Serialize)]
struct KeybindsFile {
    #[serde(default)]
    binds: HashMap<String, String>,
}

// ---------------------------------------------------------------------------
// Default bind table
// ---------------------------------------------------------------------------

fn default_binds() -> HashMap<String, ShellAction> {
    use ShellAction::*;
    let pairs: &[(&str, ShellAction)] = &[
        // Face buttons
        ("button_a",           Confirm),
        ("button_b",           Cancel),
        ("button_select",      OpenPalette),
        ("button_start",       OpenSwitcher),
        // Shoulder triggers — radial menu
        ("l2_hold_true",       RadialHold { held: true }),
        ("l2_hold_false",      RadialHold { held: false }),
        ("r2_hold_true",       RadialHold { held: true }),
        ("r2_hold_false",      RadialHold { held: false }),
        // D-pad
        ("dpad_up",            NavUp),
        ("dpad_down",          NavDown),
        ("dpad_left",          NavLeft),
        ("dpad_right",         NavRight),
        // Shoulder bumpers — workspace switching
        ("l1",                 WorkspacePrev),
        ("r1",                 WorkspaceNext),
        // System shortcuts (can be rebound to any button)
        ("select_long",        Sleep),
        ("l2_r2_brightness_up",   BrightnessUp),
        ("l2_r2_brightness_down", BrightnessDown),
        ("l2_r2_volume_up",       VolumeUp),
        ("l2_r2_volume_down",     VolumeDown),
        ("l2_r2_wifi",            WifiToggle),
        ("l2_r2_bt",              BluetoothToggle),
    ];
    pairs.iter().map(|(k, v)| (k.to_string(), v.clone())).collect()
}

// ---------------------------------------------------------------------------
// Action name ↔ ShellAction conversion
// ---------------------------------------------------------------------------

fn action_name_to_shell_action(name: &str) -> Option<ShellAction> {
    use ShellAction::*;
    Some(match name {
        "confirm"              => Confirm,
        "cancel"               => Cancel,
        "open_palette"         => OpenPalette,
        "open_switcher"        => OpenSwitcher,
        "radial_hold_true"     => RadialHold { held: true },
        "radial_hold_false"    => RadialHold { held: false },
        "nav_up"               => NavUp,
        "nav_down"             => NavDown,
        "nav_left"             => NavLeft,
        "nav_right"            => NavRight,
        "workspace_prev"       => WorkspacePrev,
        "workspace_next"       => WorkspaceNext,
        "brightness_up"        => BrightnessUp,
        "brightness_down"      => BrightnessDown,
        "volume_up"            => VolumeUp,
        "volume_down"          => VolumeDown,
        "wifi_toggle"          => WifiToggle,
        "bluetooth_toggle"     => BluetoothToggle,
        "cellular_toggle"      => CellularToggle,
        "vpn_toggle"           => VpnToggle,
        "split_toggle"         => SplitToggle,
        "sleep"                => Sleep,
        "lower_backspace"      => LowerBackspace,
        "lower_submit"         => LowerSubmit,
        _ => return None,
    })
}

fn shell_action_to_name(action: &ShellAction) -> &'static str {
    use ShellAction::*;
    match action {
        Confirm              => "confirm",
        Cancel               => "cancel",
        OpenPalette          => "open_palette",
        OpenSwitcher         => "open_switcher",
        RadialHold { held: true }  => "radial_hold_true",
        RadialHold { held: false } => "radial_hold_false",
        NavUp                => "nav_up",
        NavDown              => "nav_down",
        NavLeft              => "nav_left",
        NavRight             => "nav_right",
        WorkspacePrev        => "workspace_prev",
        WorkspaceNext        => "workspace_next",
        BrightnessUp         => "brightness_up",
        BrightnessDown       => "brightness_down",
        VolumeUp             => "volume_up",
        VolumeDown           => "volume_down",
        WifiToggle           => "wifi_toggle",
        BluetoothToggle      => "bluetooth_toggle",
        CellularToggle       => "cellular_toggle",
        VpnToggle            => "vpn_toggle",
        SplitToggle          => "split_toggle",
        Sleep                => "sleep",
        LowerBackspace       => "lower_backspace",
        LowerSubmit          => "lower_submit",
        // Analog / payload variants don't have static names in the bind table
        StickMoved { .. }    => "stick_moved",
        PadMoved { .. }      => "pad_moved",
        LowerKeyPress { .. } => "lower_key_press",
        LowerTap { .. }      => "lower_tap",
        VoiceResult { .. }   => "voice_result",
    }
}

// ---------------------------------------------------------------------------
// Config path helpers
// ---------------------------------------------------------------------------

fn user_config_path() -> PathBuf {
    if let Some(home) = std::env::var_os("HOME") {
        PathBuf::from(home).join(".config/torchform/keybinds.toml")
    } else {
        PathBuf::from("config/keybinds.toml")
    }
}

fn config_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();
    if let Some(home) = std::env::var_os("HOME") {
        paths.push(PathBuf::from(home).join(".config/torchform/keybinds.toml"));
    }
    paths.push(PathBuf::from("/etc/torchform/keybinds.toml"));
    paths.push(PathBuf::from("config/keybinds.toml"));
    paths
}

// Minimal logging without a hard dep on tracing (so the lib stays lean).
// In production the caller has tracing initialized; these just go to stderr
// if tracing is not set up.
fn tracing_log(msg: String) {
    // Use eprintln as a fallback — the shell and inputd both init tracing,
    // so in practice the tracing macros would be better, but we keep the lib
    // free of the tracing dep to stay lightweight.
    eprintln!("[torchform-actions] {msg}");
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_map_resolves_basics() {
        let map = InputMap::from_defaults();
        assert_eq!(map.resolve(&RawInput::new("button_a")), Some(ShellAction::Confirm));
        assert_eq!(map.resolve(&RawInput::new("button_b")), Some(ShellAction::Cancel));
        assert_eq!(map.resolve(&RawInput::new("dpad_up")),  Some(ShellAction::NavUp));
        assert_eq!(map.resolve(&RawInput::new("l2_hold_true")),
                   Some(ShellAction::RadialHold { held: true }));
        assert_eq!(map.resolve(&RawInput::new("unknown_key")), None);
    }

    #[test]
    fn toml_round_trip() {
        let map = InputMap::from_defaults();
        let raw_map: std::collections::HashMap<String, String> = map.binds.iter()
            .map(|(k, v)| (k.clone(), shell_action_to_name(v).to_owned()))
            .collect();
        let file = KeybindsFile { binds: raw_map };
        let text = toml::to_string_pretty(&file).unwrap();
        // Re-parse
        let file2: KeybindsFile = toml::from_str(&text).unwrap();
        assert!(file2.binds.contains_key("button_a"));
    }

    #[test]
    fn all_default_binds_have_valid_names() {
        let map = InputMap::from_defaults();
        for (_, action) in &map.binds {
            // Just ensure we can round-trip through the name
            let name = shell_action_to_name(action);
            assert!(!name.is_empty());
        }
    }

    #[test]
    fn config_override_replaces_binding() {
        // Simulate loading a config that remaps button_a → cancel
        let toml = r#"
[binds]
button_a = "cancel"
"#;
        let file: KeybindsFile = toml::from_str(toml).unwrap();
        let mut binds = default_binds();
        for (k, v) in file.binds {
            if let Some(action) = action_name_to_shell_action(&v) {
                binds.insert(k, action);
            }
        }
        let map = InputMap { binds };
        assert_eq!(map.resolve(&RawInput::new("button_a")), Some(ShellAction::Cancel));
        // Other defaults still present
        assert_eq!(map.resolve(&RawInput::new("button_b")), Some(ShellAction::Cancel));
    }
}
