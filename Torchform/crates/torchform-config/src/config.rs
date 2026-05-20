// =============================================================================
// config.rs — Torchform DE configuration loader
//
// Searches for config.toml in priority order:
//   1. ~/.config/torchform/config.toml  (user — highest priority)
//   2. /etc/torchform/config.toml       (system)
//   3. ./config/torchform.toml          (dev / workspace)
//
// Any missing key uses the built-in Default impl — you never have to
// write a complete config file; partial overrides always work.
// =============================================================================

use std::{collections::HashMap, path::PathBuf};
use serde::{Deserialize, Serialize};
use anyhow::Result;

// ---------------------------------------------------------------------------
// Top-level config
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct TorchformConfig {
    pub general:    GeneralConfig,
    pub theme:      ThemeConfig,
    pub icons:      HashMap<String, String>,
    pub apps:       AppsConfig,
    pub input:      InputConfig,
    pub radial:     RadialConfig,
    pub launch:     LaunchConfig,
}

impl Default for TorchformConfig {
    fn default() -> Self {
        Self {
            general: GeneralConfig::default(),
            theme:   ThemeConfig::default(),
            icons:   HashMap::new(),
            apps:    AppsConfig::default(),
            input:   InputConfig::default(),
            radial:  RadialConfig::default(),
            launch:  LaunchConfig::default(),
        }
    }
}

// ---------------------------------------------------------------------------
// [general]
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(default)]
pub struct GeneralConfig {
    /// Demo overlay to show on launch ("radial" | "palette" | "switcher" |
    /// "idle" | "").
    pub demo_mode:  String,
    /// Root for user data. `~` is expanded.
    pub data_dir:   String,
    /// Display brightness 0–100.
    pub brightness: Option<u8>,
    /// Master volume 0–100.
    pub volume:     Option<u8>,
}

impl Default for GeneralConfig {
    fn default() -> Self {
        Self {
            demo_mode:  String::new(),
            data_dir:   "~/.local/share/torchform".into(),
            brightness: None,
            volume:     None,
        }
    }
}

// ---------------------------------------------------------------------------
// [theme]
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct ThemeConfig {
    pub name:       String,
    /// Optional path to an external .toml theme file. Takes precedence over
    /// inline [theme.colors] / [theme.typography] if present.
    pub theme_file: Option<String>,
    pub colors:     ThemeColors,
    pub typography: ThemeTypography,
}

impl Default for ThemeConfig {
    fn default() -> Self {
        Self {
            name:       "Minerva Dark".into(),
            theme_file: None,
            colors:     ThemeColors::default(),
            typography: ThemeTypography::default(),
        }
    }
}

/// Resolved theme: `ThemeConfig::resolve()` merges an optional external file.
#[derive(Debug, Clone)]
pub struct ResolvedTheme {
    pub name:       String,
    pub colors:     ThemeColors,
    pub typography: ThemeTypography,
}

impl ThemeConfig {
    /// Load the external theme file (if set) and merge it over the inline
    /// values. Falls back to inline values if the file is missing or invalid.
    pub fn resolve(&self) -> ResolvedTheme {
        if let Some(ref path_str) = self.theme_file {
            let path = expand_tilde(path_str);
            match load_theme_file(&path) {
                Ok(file_theme) => {
                    tracing::info!("Loaded theme file: {}", path.display());
                    return ResolvedTheme {
                        name:       file_theme.name.unwrap_or_else(|| self.name.clone()),
                        colors:     file_theme.colors,
                        typography: file_theme.typography,
                    };
                }
                Err(e) => {
                    tracing::warn!("Failed to load theme file {}: {e}", path.display());
                }
            }
        }
        ResolvedTheme {
            name:       self.name.clone(),
            colors:     self.colors.clone(),
            typography: self.typography.clone(),
        }
    }
}

// Internal struct for deserialising standalone theme files.
#[derive(Debug, Clone, Deserialize, Default)]
struct ThemeFile {
    name:       Option<String>,
    #[serde(default)] colors:     ThemeColors,
    #[serde(default)] typography: ThemeTypography,
}

fn load_theme_file(path: &PathBuf) -> Result<ThemeFile> {
    let text = std::fs::read_to_string(path)?;
    Ok(toml::from_str(&text)?)
}

// ---------------------------------------------------------------------------
// Theme colours
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct ThemeColors {
    pub bg_base:        String,
    pub bg_surface:     String,
    pub bg_elevated:    String,
    pub bg_overlay:     String,

    pub accent:         String,
    pub accent_dim:     String,
    pub accent_glow:    String,

    pub primary:        String,
    pub primary_hover:  String,
    pub secondary:      String,

    pub success:        String,
    pub warning:        String,
    pub error:          String,

    pub text_primary:   String,
    pub text_secondary: String,
    pub text_disabled:  String,
    pub text_on_accent: String,
    pub text_on_primary: String,

    pub border:         String,
    pub border_focused: String,
    pub border_subtle:  String,

    pub lower_bg:       String,
    pub lower_surface:  String,
    pub lower_accent:   String,
}

impl Default for ThemeColors {
    fn default() -> Self {
        Self {
            bg_base:         "#0d0f14".into(),
            bg_surface:      "#161a22".into(),
            bg_elevated:     "#1e2330".into(),
            bg_overlay:      "#0d0f14cc".into(),
            accent:          "#00d4ff".into(),
            accent_dim:      "#0099bb".into(),
            accent_glow:     "#00d4ff44".into(),
            primary:         "#5b9cf6".into(),
            primary_hover:   "#7ab3ff".into(),
            secondary:       "#8a6fdb".into(),
            success:         "#3dd68c".into(),
            warning:         "#f7b731".into(),
            error:           "#f74040".into(),
            text_primary:    "#e8eaf0".into(),
            text_secondary:  "#8c92a4".into(),
            text_disabled:   "#4a5068".into(),
            text_on_accent:  "#000000".into(),
            text_on_primary: "#ffffff".into(),
            border:          "#2a2f3d".into(),
            border_focused:  "#00d4ff".into(),
            border_subtle:   "#1d2230".into(),
            lower_bg:        "#0a0c11".into(),
            lower_surface:   "#12151c".into(),
            lower_accent:    "#00d4ff".into(),
        }
    }
}

// ---------------------------------------------------------------------------
// Theme typography
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct ThemeTypography {
    pub font_sans:    String,
    pub font_mono:    String,
    pub font_display: String,
}

impl Default for ThemeTypography {
    fn default() -> Self {
        Self {
            font_sans:    "Inter, DejaVu Sans, sans-serif".into(),
            font_mono:    "JetBrains Mono, DejaVu Sans Mono, monospace".into(),
            font_display: "Barlow Condensed, Inter, DejaVu Sans, sans-serif".into(),
        }
    }
}

// ---------------------------------------------------------------------------
// [apps]
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct AppsConfig {
    /// Binary to spawn for "app.settings". Empty = stub only.
    pub settings: String,
    /// Binary to spawn for "app.files". Empty = stub only.
    pub files:    String,
    /// Binary to spawn for "app.editor". Empty = stub only.
    pub editor:   String,
    /// Binary to spawn for "app.browser". Empty = stub only.
    pub browser:  String,
    /// Binary to spawn for "app.network". Empty = stub only.
    pub network:  String,
    /// Binary to spawn for "app.gpio". Empty = stub only.
    pub gpio:     String,
    /// Binary to spawn for "app.camera". Empty = stub only.
    pub camera:   String,
    /// Binary to spawn for "app.media". Empty = stub only.
    pub media:    String,
    /// Binary to spawn for "app.keyboard". Empty = always stub (native).
    pub keyboard: String,
    /// Binary to spawn for "app.terminal" (e.g. "foot", "alacritty").
    pub terminal: String,
}

impl Default for AppsConfig {
    fn default() -> Self {
        Self {
            settings: "gnome-control-center".into(),
            files:    "thunar".into(),
            editor:   "micro".into(),
            browser:  "firefox".into(),
            network:  "nm-connection-editor".into(),
            gpio:     String::new(),
            camera:   String::new(),
            media:    "vlc".into(),
            keyboard: String::new(),
            terminal: "foot".into(),
        }
    }
}

impl AppsConfig {
    /// Returns the binary name for the given palette command ID, or `None` if
    /// the command has no external binary (stub-only) or is unknown.
    pub fn binary_for(&self, command_id: &str) -> Option<&str> {
        let s = match command_id {
            "app.settings" | "settings" | "open-settings" => &self.settings,
            "app.files"    | "file-manager" | "open-files" => &self.files,
            "app.editor"   | "editor"                      => &self.editor,
            "app.browser"  | "browser"                     => &self.browser,
            "app.network"  | "network"                     => &self.network,
            "app.gpio"     | "gpio"                        => &self.gpio,
            "app.camera"   | "camera"                      => &self.camera,
            "app.media"    | "media-player"                => &self.media,
            "app.keyboard" | "keyboard"                    => &self.keyboard,
            "app.terminal" | "terminal"                    => &self.terminal,
            _                                               => return None,
        };
        if s.is_empty() { None } else { Some(s.as_str()) }
    }
}

// ---------------------------------------------------------------------------
// [launch]
// ---------------------------------------------------------------------------

/// Global launch configuration: environment variables injected into every
/// spawned process, and per-app overrides.
#[derive(Debug, Clone, Deserialize, Serialize, Default)]
#[serde(default)]
pub struct LaunchConfig {
    /// Environment variables applied to every spawned app process.
    pub env: HashMap<String, String>,
    /// Per-app overrides keyed by app-id (e.g. "app.browser") or binary name.
    pub apps: HashMap<String, AppLaunchOverride>,
}

/// Per-app launch override — all fields are optional.
#[derive(Debug, Clone, Deserialize, Default, Serialize)]
#[serde(default)]
pub struct AppLaunchOverride {
    /// Override the binary to launch (instead of the [apps] config value).
    pub binary: Option<String>,
    /// Extra arguments to pass.
    pub args:   Vec<String>,
    /// Extra environment variables for this app only (merged over global env).
    pub env:    HashMap<String, String>,
    /// Launch mode hint: "wayland" | "sdl" | "gl" | "retroarch" | "kiosk"
    pub mode:   Option<String>,
}

// ---------------------------------------------------------------------------
// [input]
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct InputConfig {
    pub palette:   String,
    pub switcher:  String,
    pub confirm:   String,
    pub back:      String,
    pub radial_l1: String,
    pub radial_l2: String,
}

impl Default for InputConfig {
    fn default() -> Self {
        Self {
            palette:   "select".into(),
            switcher:  "start".into(),
            confirm:   "a".into(),
            back:      "b".into(),
            radial_l1: "l2".into(),
            radial_l2: "r2".into(),
        }
    }
}

// ---------------------------------------------------------------------------
// [radial]
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize, Serialize, Default)]
#[serde(default)]
pub struct RadialConfig {
    pub system: RadialLayerConfig,
}

#[derive(Debug, Clone, Deserialize, Serialize, Default)]
#[serde(default)]
pub struct RadialLayerConfig {
    pub slots: Vec<RadialSlotConfig>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(default)]
pub struct RadialSlotConfig {
    pub label:   String,
    pub icon:    String,
    pub action:  String,
    pub nested:  bool,
    pub enabled: bool,
}

impl Default for RadialSlotConfig {
    fn default() -> Self {
        Self {
            label:   String::new(),
            icon:    String::new(),
            action:  String::new(),
            nested:  false,
            enabled: true,
        }
    }
}

// ---------------------------------------------------------------------------
// Loading
// ---------------------------------------------------------------------------

impl TorchformConfig {
    /// Load config by searching standard paths. Never fails — returns defaults
    /// if no file is found or if parsing fails.
    pub fn load() -> Self {
        for path in config_search_paths() {
            if path.exists() {
                match Self::load_from(&path) {
                    Ok(cfg) => {
                        tracing::info!("Loaded config: {}", path.display());
                        return cfg;
                    }
                    Err(e) => tracing::warn!("Config error at {}: {e}", path.display()),
                }
            }
        }
        tracing::info!("No config file found — using built-in defaults");
        Self::default()
    }

    fn load_from(path: &PathBuf) -> Result<Self> {
        let text = std::fs::read_to_string(path)?;
        Ok(toml::from_str(&text)?)
    }

    /// Serialise the current config back to TOML and write it to `path`.
    /// Creates parent directories if needed.
    pub fn save(&self, path: &PathBuf) -> Result<()> {
        // We serialise only the fields that are safe to round-trip. We build
        // a minimal serde-compatible wrapper rather than deriving Serialize on
        // the full struct (which would pull in slint types).
        use std::io::Write;
        let text = toml::to_string_pretty(&SaveableConfig::from(self))?;
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let mut f = std::fs::File::create(path)?;
        f.write_all(text.as_bytes())?;
        tracing::info!("Config saved to {}", path.display());
        Ok(())
    }
}

/// A Serialize-able subset of TorchformConfig for writing back to disk.
/// Only includes fields the user would edit (not theme colors inline).
#[derive(Serialize)]
struct SaveableConfig<'a> {
    general: &'a GeneralConfig,
    apps:    SaveableApps<'a>,
    launch:  &'a LaunchConfig,
    radial:  &'a RadialConfig,
}

#[derive(Serialize)]
struct SaveableApps<'a> {
    settings: &'a str,
    files:    &'a str,
    editor:   &'a str,
    browser:  &'a str,
    network:  &'a str,
    gpio:     &'a str,
    camera:   &'a str,
    media:    &'a str,
    keyboard: &'a str,
    terminal: &'a str,
}

impl<'a> From<&'a TorchformConfig> for SaveableConfig<'a> {
    fn from(c: &'a TorchformConfig) -> Self {
        SaveableConfig {
            general: &c.general,
            apps:    SaveableApps {
                settings: &c.apps.settings,
                files:    &c.apps.files,
                editor:   &c.apps.editor,
                browser:  &c.apps.browser,
                network:  &c.apps.network,
                gpio:     &c.apps.gpio,
                camera:   &c.apps.camera,
                media:    &c.apps.media,
                keyboard: &c.apps.keyboard,
                terminal: &c.apps.terminal,
            },
            launch:  &c.launch,
            radial:  &c.radial,
        }
    }
}

/// Returns the canonical user config path for saving.
pub fn user_config_path() -> PathBuf {
    if let Some(home) = std::env::var_os("HOME") {
        PathBuf::from(home).join(".config/torchform/config.toml")
    } else {
        PathBuf::from("config/torchform.toml")
    }
}

fn config_search_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();
    if let Some(home) = std::env::var_os("HOME") {
        paths.push(PathBuf::from(home).join(".config/torchform/config.toml"));
    }
    paths.push(PathBuf::from("/etc/torchform/config.toml"));
    paths.push(PathBuf::from("config/torchform.toml"));
    paths
}


// ---------------------------------------------------------------------------
// Tilde expansion helper
// ---------------------------------------------------------------------------

pub fn expand_tilde(path: &str) -> PathBuf {
    if let Some(rest) = path.strip_prefix("~/") {
        if let Some(home) = std::env::var_os("HOME") {
            return PathBuf::from(home).join(rest);
        }
    }
    PathBuf::from(path)
}
