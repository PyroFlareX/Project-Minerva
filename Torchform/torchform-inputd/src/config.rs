//! TOML configuration: timings, chords, multiclick aliases, and per-device raw
//! code remaps. Pure data + parsing — no evdev dependency, fully unit-testable.

use serde::Deserialize;
use std::collections::BTreeMap;
use std::path::Path;

/// Top-level config. All sections are optional; a fully empty file yields the
/// defaults (every standard button passes straight through, no chords).
#[derive(Debug, Clone, Deserialize, Default)]
#[serde(default, deny_unknown_fields)]
pub struct Config {
    pub timing: Timing,
    /// Chords: several buttons held together within `chord_window_ms`.
    #[serde(rename = "chord")]
    pub chords: Vec<ChordRule>,
    /// Multiclick aliases: N presses of one button within `multiclick_window_ms`.
    #[serde(rename = "multiclick")]
    pub multiclicks: Vec<MulticlickRule>,
    /// Per-device raw-code remaps for non-standard controllers.
    #[serde(rename = "devices")]
    pub devices: Vec<DeviceProfile>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Timing {
    /// All members of a chord must land within this window to count as a chord.
    pub chord_window_ms: u64,
    /// Gap allowed between presses of the same button for multiclick counting.
    pub multiclick_window_ms: u64,
    /// Delay before a held d-pad direction starts auto-repeating.
    pub repeat_delay_ms: u64,
    /// Interval between auto-repeats once repeating has started.
    pub repeat_rate_ms: u64,
}

impl Default for Timing {
    fn default() -> Self {
        Timing {
            chord_window_ms: 40,
            multiclick_window_ms: 250,
            repeat_delay_ms: 350,
            repeat_rate_ms: 90,
        }
    }
}

/// `[[chord]]` — e.g. L1+R1 → "switcher".
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChordRule {
    /// Logical button names that must be pressed together (2+).
    pub buttons: Vec<String>,
    /// Action name emitted on a virtual action slot when the chord fires.
    pub action: String,
}

/// `[[multiclick]]` — e.g. south x2 → "confirm_double".
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MulticlickRule {
    /// Logical button name.
    pub button: String,
    /// Number of presses (2 = double, 3 = triple, …).
    pub count: u32,
    /// Action name emitted on a virtual action slot when the count is reached.
    pub action: String,
}

/// `[[devices]]` — match a controller and remap its raw evdev codes.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DeviceProfile {
    /// Case-insensitive substring of the device name, OR a "vid:pid" hex pair
    /// (e.g. "0810:0001"). Whichever the daemon can match against the device.
    #[serde(rename = "match")]
    pub match_spec: String,
    /// raw evdev key name (e.g. "BTN_TRIGGER") → logical button name ("south").
    /// Codes not listed fall back to the standard evdev→logical mapping.
    #[serde(default)]
    pub remap: BTreeMap<String, String>,
}

impl Config {
    /// Parse from a TOML string.
    pub fn from_toml(s: &str) -> anyhow::Result<Config> {
        Ok(toml::from_str(s)?)
    }

    /// Load from a path, or fall back to defaults if it does not exist.
    pub fn load_or_default(path: &Path) -> anyhow::Result<Config> {
        match std::fs::read_to_string(path) {
            Ok(s) => Config::from_toml(&s),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                log::warn!("config {} not found — using defaults", path.display());
                Ok(Config::default())
            }
            Err(e) => Err(e.into()),
        }
    }

    /// Every distinct action name referenced by a chord or multiclick rule,
    /// sorted for a deterministic slot assignment shared with the plugin.
    pub fn action_names(&self) -> Vec<String> {
        let mut names: Vec<String> = self
            .chords
            .iter()
            .map(|c| c.action.clone())
            .chain(self.multiclicks.iter().map(|m| m.action.clone()))
            .collect();
        names.sort();
        names.dedup();
        names
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_config_is_defaults() {
        let c = Config::from_toml("").unwrap();
        assert_eq!(c.timing.chord_window_ms, 40);
        assert!(c.chords.is_empty());
    }

    #[test]
    fn parses_full_example() {
        let toml = r#"
            [timing]
            chord_window_ms = 50
            multiclick_window_ms = 300

            [[chord]]
            buttons = ["l1", "r1"]
            action = "switcher"

            [[multiclick]]
            button = "south"
            count = 2
            action = "confirm_double"

            [[devices]]
            match = "DragonRise"
            [devices.remap]
            BTN_TRIGGER = "south"
            BTN_THUMB = "east"
        "#;
        let c = Config::from_toml(toml).unwrap();
        assert_eq!(c.timing.chord_window_ms, 50);
        assert_eq!(c.chords.len(), 1);
        assert_eq!(c.chords[0].action, "switcher");
        assert_eq!(c.multiclicks[0].count, 2);
        assert_eq!(c.devices[0].match_spec, "DragonRise");
        assert_eq!(c.devices[0].remap.get("BTN_TRIGGER").unwrap(), "south");
    }

    #[test]
    fn action_names_are_sorted_and_unique() {
        let toml = r#"
            [[chord]]
            buttons = ["l1","r1"]
            action = "switcher"
            [[multiclick]]
            button = "south"
            count = 2
            action = "switcher"
            [[multiclick]]
            button = "east"
            count = 2
            action = "alt_back"
        "#;
        let c = Config::from_toml(toml).unwrap();
        assert_eq!(c.action_names(), vec!["alt_back", "switcher"]);
    }
}
