// =============================================================================
// torchform-terminal — Torchform terminal launcher
//
// Intended terminal: Alacritty (https://alacritty.org)
// Fallback terminal: Kitty (https://sw.kovidgoyal.net/kitty/)
//
// What this binary does:
//   1. Load TorchformConfig to read the theme colours and apps.terminal binary.
//   2. Write a themed Alacritty (or Kitty) config to a temp/well-known path.
//   3. exec() the terminal binary with --config-file pointing at that config.
//      Because we exec() instead of spawn(), this process is replaced entirely
//      — no zombie, no double process.
//
// Config key: [apps] terminal = "alacritty"   (default)
//             [apps] terminal = "kitty"        (fallback)
//
// The generated Alacritty config mirrors the Torchform Minerva Dark theme so
// the terminal feels native to the DE.  Colors are derived from ThemeColors.
// =============================================================================

use std::os::unix::process::CommandExt;
use anyhow::{bail, Context, Result};
use torchform_config::TorchformConfig;
use tracing::info;

fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("torchform_terminal=info".parse().unwrap()),
        )
        .init();

    let cfg = TorchformConfig::load();
    let theme = cfg.theme.resolve();
    let binary = if cfg.apps.terminal.is_empty() { "alacritty" } else { &cfg.apps.terminal };

    // Determine whether we're launching Alacritty or Kitty (or another binary)
    let binary_stem = std::path::Path::new(binary)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or(binary);

    info!("torchform-terminal: launching {binary}");

    match binary_stem {
        "alacritty" => launch_alacritty(binary, &theme, &cfg),
        "kitty"     => launch_kitty(binary, &theme, &cfg),
        other => {
            // Unknown terminal — just exec() it directly with no extra config.
            // Still sets basic Wayland environment.
            info!("Unknown terminal binary '{other}' — launching without theme config");
            let err = std::process::Command::new(binary)
                .env("WAYLAND_DISPLAY", std::env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "wayland-0".into()))
                .exec();
            bail!("exec {binary} failed: {err}");
        }
    }
}

// ---------------------------------------------------------------------------
// Alacritty
// ---------------------------------------------------------------------------

fn launch_alacritty(
    binary: &str,
    theme: &torchform_config::ResolvedTheme,
    cfg: &TorchformConfig,
) -> Result<()> {
    let config_path = write_alacritty_config(theme, cfg)?;
    info!("Alacritty config written to {}", config_path.display());

    let err = std::process::Command::new(binary)
        .arg("--config-file")
        .arg(&config_path)
        .env("WAYLAND_DISPLAY",
             std::env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "wayland-0".into()))
        .env("WINIT_UNIX_BACKEND", "wayland")
        .exec();
    bail!("exec alacritty failed: {err}");
}

fn write_alacritty_config(
    theme: &torchform_config::ResolvedTheme,
    _cfg: &TorchformConfig,
) -> Result<std::path::PathBuf> {
    let dir = config_dir();
    std::fs::create_dir_all(&dir)?;
    let path = dir.join("alacritty.toml");

    // Build TOML config using the Minerva Dark palette from the loaded theme.
    // Alacritty TOML format (v0.13+).
    let c = &theme.colors;
    let config = format!(r#"# Torchform DE — Alacritty theme config (auto-generated)
# Edit ~/.config/torchform/alacritty-override.toml to add custom overrides.

[window]
padding.x = 8
padding.y = 6
decorations = "None"
opacity = 0.96
blur = false

[font]
normal.family = "JetBrains Mono"
normal.style  = "Regular"
bold.family   = "JetBrains Mono"
bold.style    = "Bold"
italic.family = "JetBrains Mono"
italic.style  = "Italic"
size = 12.0

[cursor]
style.shape   = "Block"
style.blinking = "On"
blink_interval = 750
vi_mode_style.shape = "Underline"

[scrolling]
history = 10000
multiplier = 3

# ---------------------------------------------------------------------------
# Torchform Minerva Dark colour palette
# ---------------------------------------------------------------------------

[colors.primary]
background = "{bg_base}"
foreground = "{fg}"

[colors.cursor]
text   = "{bg_base}"
cursor = "{accent}"

[colors.vi_mode_cursor]
text   = "{bg_base}"
cursor = "{secondary}"

[colors.search.matches]
foreground = "{bg_base}"
background = "{accent}"

[colors.search.focused_match]
foreground = "{bg_base}"
background = "{warning}"

[colors.hints.start]
foreground = "{bg_base}"
background = "{warning}"

[colors.selection]
text       = "{bg_base}"
background = "{primary}"

# ANSI colours — mapped to Minerva palette semantic values
[colors.normal]
black   = "{bg_surface}"
red     = "{error}"
green   = "{success}"
yellow  = "{warning}"
blue    = "{primary}"
magenta = "{secondary}"
cyan    = "{accent}"
white   = "{fg}"

[colors.bright]
black   = "{bg_elevated}"
red     = "{error}"
green   = "{success}"
yellow  = "{warning}"
blue    = "{primary_hover}"
magenta = "{secondary}"
cyan    = "{accent}"
white   = "{fg}"
"#,
        bg_base      = c.bg_base,
        bg_surface   = c.bg_surface,
        bg_elevated  = c.bg_elevated,
        fg           = c.text_primary,
        accent       = c.accent,
        primary      = c.primary,
        primary_hover= c.primary_hover,
        secondary    = c.secondary,
        success      = c.success,
        warning      = c.warning,
        error        = c.error,
    );

    std::fs::write(&path, config)
        .with_context(|| format!("write alacritty config to {}", path.display()))?;

    Ok(path)
}

// ---------------------------------------------------------------------------
// Kitty
// ---------------------------------------------------------------------------

fn launch_kitty(
    binary: &str,
    theme: &torchform_config::ResolvedTheme,
    cfg: &TorchformConfig,
) -> Result<()> {
    let config_path = write_kitty_config(theme, cfg)?;
    info!("Kitty config written to {}", config_path.display());

    let err = std::process::Command::new(binary)
        .arg("--config")
        .arg(&config_path)
        .env("WAYLAND_DISPLAY",
             std::env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "wayland-0".into()))
        .exec();
    bail!("exec kitty failed: {err}");
}

fn write_kitty_config(
    theme: &torchform_config::ResolvedTheme,
    _cfg: &TorchformConfig,
) -> Result<std::path::PathBuf> {
    let dir = config_dir();
    std::fs::create_dir_all(&dir)?;
    let path = dir.join("kitty.conf");

    let c = &theme.colors;
    let config = format!(r#"# Torchform DE — Kitty theme config (auto-generated)

font_family      JetBrains Mono Regular
bold_font        JetBrains Mono Bold
italic_font      JetBrains Mono Italic
bold_italic_font JetBrains Mono Bold Italic
font_size        12.0

cursor_shape     block
cursor_blink_interval 0.75

scrollback_lines 10000

# Remove window decorations (Wayland — let the compositor handle chrome)
hide_window_decorations yes
background_opacity 0.96

# ---------------------------------------------------------------------------
# Torchform Minerva Dark palette
# ---------------------------------------------------------------------------

foreground {fg}
background {bg_base}
cursor     {accent}
cursor_text_color {bg_base}

selection_foreground {bg_base}
selection_background {primary}

# ANSI colours
color0  {bg_surface}
color1  {error}
color2  {success}
color3  {warning}
color4  {primary}
color5  {secondary}
color6  {accent}
color7  {fg}
color8  {bg_elevated}
color9  {error}
color10 {success}
color11 {warning}
color12 {primary_hover}
color13 {secondary}
color14 {accent}
color15 {fg}
"#,
        bg_base      = c.bg_base,
        bg_surface   = c.bg_surface,
        bg_elevated  = c.bg_elevated,
        fg           = c.text_primary,
        accent       = c.accent,
        primary      = c.primary,
        primary_hover= c.primary_hover,
        secondary    = c.secondary,
        success      = c.success,
        warning      = c.warning,
        error        = c.error,
    );

    std::fs::write(&path, config)
        .with_context(|| format!("write kitty config to {}", path.display()))?;

    Ok(path)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn config_dir() -> std::path::PathBuf {
    if let Some(home) = std::env::var_os("HOME") {
        std::path::PathBuf::from(home).join(".config/torchform/terminal")
    } else {
        std::path::PathBuf::from("/tmp/torchform")
    }
}
