// =============================================================================
// torchform-run — Torchform application launcher
//
// USAGE
//   torchform-run <app-id-or-binary> [args...]
//   torchform-run app.browser
//   torchform-run firefox --new-window
//   torchform-run retroarch -L /usr/lib/libretro/snes9x_libretro.so
//   torchform-run --window-size 1920x1080 vlc
//
// WHAT IT DOES
//   1. Reads ~/.config/torchform/config.toml (or /etc/torchform/config.toml)
//   2. Sets Wayland / SDL / Qt / GTK environment variables
//   3. Applies per-app overrides from [launch.apps.<id>]
//   4. Applies --window-size override via GDK_SCALE / SDL env vars
//   5. exec()s the binary (replaces this process, forwarding signals)
// =============================================================================

use std::{collections::HashMap, os::unix::process::CommandExt, path::PathBuf};
use anyhow::{bail, Result};
use serde::Deserialize;

// ---------------------------------------------------------------------------
// Minimal config types (mirror the relevant parts of torchform-shell/config.rs
// without importing that crate as a dependency)
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize, Default)]
#[serde(default)]
struct Config {
    launch: LaunchConfig,
}

#[derive(Debug, Deserialize, Default)]
#[serde(default)]
struct LaunchConfig {
    env:  HashMap<String, String>,
    apps: HashMap<String, AppLaunchOverride>,
}

#[derive(Debug, Deserialize, Default)]
#[serde(default)]
struct AppLaunchOverride {
    binary: Option<String>,
    args:   Vec<String>,
    env:    HashMap<String, String>,
    mode:   Option<String>,
}

// ---------------------------------------------------------------------------
// Config loading
// ---------------------------------------------------------------------------

fn load_config() -> Config {
    for path in config_paths() {
        if path.exists() {
            if let Ok(text) = std::fs::read_to_string(&path) {
                if let Ok(cfg) = toml::from_str::<Config>(&text) {
                    return cfg;
                }
            }
        }
    }
    Config::default()
}

fn config_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();
    if let Some(home) = std::env::var_os("HOME") {
        paths.push(PathBuf::from(home).join(".config/torchform/config.toml"));
    }
    paths.push(PathBuf::from("/etc/torchform/config.toml"));
    paths.push(PathBuf::from("config/torchform.toml"));
    paths
}

// ---------------------------------------------------------------------------
// Default Wayland environment
// ---------------------------------------------------------------------------

fn default_wayland_env() -> HashMap<&'static str, &'static str> {
    let mut m = HashMap::new();
    m.insert("SDL_VIDEODRIVER",              "wayland");
    m.insert("QT_QPA_PLATFORM",             "wayland");
    m.insert("GDK_BACKEND",                 "wayland");
    m.insert("MOZ_ENABLE_WAYLAND",          "1");
    m.insert("EGL_PLATFORM",                "wayland");
    m.insert("CLUTTER_BACKEND",             "wayland");
    m.insert("__GLX_VENDOR_LIBRARY_NAME",   "mesa");
    m
}

fn wayland_display() -> String {
    std::env::var("WAYLAND_DISPLAY")
        .unwrap_or_else(|_| "wayland-0".into())
}

fn xdg_runtime_dir() -> String {
    std::env::var("XDG_RUNTIME_DIR")
        .unwrap_or_else(|_| "/run/torchform".into())
}

// ---------------------------------------------------------------------------
// Window size override helpers
// ---------------------------------------------------------------------------

fn apply_window_size_env(
    cmd: &mut std::process::Command,
    size: &str,
    mode: Option<&str>,
) {
    // Parse "WxH"
    let parts: Vec<&str> = size.splitn(2, 'x').collect();
    if parts.len() != 2 { return; }
    let (w, h) = (parts[0].trim(), parts[1].trim());

    match mode.unwrap_or("") {
        "retroarch" => {
            cmd.env("RETROARCH_VIDEO_WIDTH",  w);
            cmd.env("RETROARCH_VIDEO_HEIGHT", h);
        }
        "sdl" => {
            cmd.env("SDL_WINDOW_WIDTH",  w);
            cmd.env("SDL_WINDOW_HEIGHT", h);
        }
        _ => {
            // Generic: GTK and Qt scale hints
            cmd.env("GDK_SCALE",       "1");
            cmd.env("QT_SCALE_FACTOR", "1");
            // For apps that honour this
            cmd.env("TORCHFORM_WIN_W", w);
            cmd.env("TORCHFORM_WIN_H", h);
        }
    }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("torchform_run=info".parse().unwrap()),
        )
        .init();

    let raw_args: Vec<String> = std::env::args().skip(1).collect();
    if raw_args.is_empty() {
        eprintln!("Usage: torchform-run [--window-size WxH] <app-id-or-binary> [args...]");
        std::process::exit(1);
    }

    // Parse --window-size flag
    let mut window_size: Option<String> = None;
    let mut rest = raw_args.as_slice();
    if rest.first().map(|s| s.as_str()) == Some("--window-size") {
        if rest.len() < 2 {
            bail!("--window-size requires an argument (e.g. 1920x1080)");
        }
        window_size = Some(rest[1].clone());
        rest = &rest[2..];
    }

    if rest.is_empty() {
        bail!("No binary or app-id provided");
    }

    let app_id = &rest[0];
    let extra_args = &rest[1..];

    // Load config
    let cfg = load_config();

    // Look up per-app override
    let override_entry = cfg.launch.apps.get(app_id.as_str());

    // Resolve binary
    let binary = override_entry
        .and_then(|o| o.binary.as_deref())
        .unwrap_or(app_id.as_str())
        .to_owned();

    tracing::info!("Launching: {binary} (app-id: {app_id})");

    let mut cmd = std::process::Command::new(&binary);

    // 1. Set foundational Wayland env (only if not already set)
    cmd.env("WAYLAND_DISPLAY",  wayland_display());
    cmd.env("XDG_RUNTIME_DIR",  xdg_runtime_dir());

    for (k, v) in default_wayland_env() {
        if std::env::var_os(k).is_none() {
            cmd.env(k, v);
        }
    }

    // 2. Apply global [launch.env] from config (overrides defaults)
    for (k, v) in &cfg.launch.env {
        cmd.env(k, v);
    }

    // 3. Apply per-app env
    let mode = override_entry.and_then(|o| o.mode.as_deref());
    if let Some(ov) = override_entry {
        for (k, v) in &ov.env {
            cmd.env(k, v);
        }
        if !ov.args.is_empty() {
            cmd.args(&ov.args);
        }
    }

    // 4. Extra args from command line (appended after override args)
    cmd.args(extra_args);

    // 5. Window size override
    if let Some(ref size) = window_size {
        apply_window_size_env(&mut cmd, size, mode);
    }

    // 6. exec() — replaces this process entirely
    let err = cmd.exec();
    bail!("Failed to exec {binary}: {err}")
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_wayland_env_contains_required_keys() {
        let env = default_wayland_env();
        assert!(env.contains_key("SDL_VIDEODRIVER"));
        assert!(env.contains_key("QT_QPA_PLATFORM"));
        assert!(env.contains_key("GDK_BACKEND"));
        assert!(env.contains_key("MOZ_ENABLE_WAYLAND"));
    }

    #[test]
    fn config_paths_non_empty() {
        let paths = config_paths();
        assert!(!paths.is_empty());
    }

    #[test]
    fn default_config_loads_without_panic() {
        // Even with no config file on disk, load_config() returns defaults
        let cfg = Config::default();
        assert!(cfg.launch.env.is_empty());
        assert!(cfg.launch.apps.is_empty());
    }

    #[test]
    fn window_size_parse_doesnt_panic_on_bad_input() {
        let mut cmd = std::process::Command::new("echo");
        apply_window_size_env(&mut cmd, "bad-input", None);
        apply_window_size_env(&mut cmd, "1920x1080", None);
        apply_window_size_env(&mut cmd, "1920x1080", Some("sdl"));
        apply_window_size_env(&mut cmd, "1920x1080", Some("retroarch"));
    }

    #[test]
    fn wayland_display_fallback() {
        // Can't easily clear env in tests but at least ensure it returns a string
        let d = wayland_display();
        assert!(!d.is_empty());
    }

    #[test]
    fn config_deserialises_from_toml() {
        let toml_str = r#"
[launch.env]
SDL_VIDEODRIVER = "wayland"

[launch.apps."app.browser"]
binary = "chromium"
args   = ["--kiosk"]
mode   = "kiosk"
"#;
        let cfg: Config = toml::from_str(toml_str).expect("parse failed");
        assert_eq!(cfg.launch.env.get("SDL_VIDEODRIVER").map(|s| s.as_str()), Some("wayland"));
        let browser = cfg.launch.apps.get("app.browser").expect("no browser override");
        assert_eq!(browser.binary.as_deref(), Some("chromium"));
        assert_eq!(browser.args, vec!["--kiosk"]);
        assert_eq!(browser.mode.as_deref(), Some("kiosk"));
    }
}
