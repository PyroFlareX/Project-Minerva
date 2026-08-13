// =============================================================================
// apps.rs — External application launching
//
// On the real DE (CM5 with Wayland compositor) apps are spawned here and
// inherit WAYLAND_DISPLAY so they connect to the compositor automatically.
//
// In the emulator / Docker the binary won't be found, so spawn() returns Err
// and the caller shows the built-in stub panel instead.
//
// To add a new app:
//   1. Add a PaletteEntry in palette.rs::default_commands() with a new id.
//   2. Add a match arm in AppsConfig::binary_for() in config.rs.
//   3. If you want a built-in stub, add an AppFoo component in a new .slint
//      file, embed it in emulator.slint / shell.slint, add an ActiveApp
//      variant in main.rs, and route D-pad / A / B events to it.
// Binary names come from config.toml [apps] — no hardcoded strings here.
// =============================================================================

use crate::config::{AppsConfig, LaunchConfig};

/// Try to launch the external binary mapped to `command_id` in the config.
///
/// Env vars from `launch_cfg.env` are applied globally to the process.
/// Per-app overrides in `launch_cfg.apps` can change the binary, add args,
/// or set additional env vars.
///
/// Returns the PID if a process was successfully spawned (real DE path).
/// Returns `None` if the config maps no binary, the binary is not installed,
/// or spawn fails — the caller should show the built-in stub.
pub fn try_launch_external(
    command_id: &str,
    apps_cfg: &AppsConfig,
    launch_cfg: &LaunchConfig,
) -> Option<u32> {
    // Resolve binary: per-app override takes precedence over [apps] config.
    let override_entry = launch_cfg.apps.get(command_id);
    let binary = match override_entry.and_then(|o| o.binary.as_deref()) {
        Some(b) => b.to_owned(),
        None => match apps_cfg.binary_for(command_id) {
            Some(b) => b.to_owned(),
            None => {
                tracing::debug!("No binary configured for {command_id} — showing stub");
                return None;
            }
        },
    };

    let mut cmd = std::process::Command::new(&binary);

    // Apply global env vars from [launch.env]
    for (k, v) in &launch_cfg.env {
        cmd.env(k, v);
    }

    // Apply per-app env and args if an override exists
    if let Some(ov) = override_entry {
        for (k, v) in &ov.env {
            cmd.env(k, v);
        }
        if !ov.args.is_empty() {
            cmd.args(&ov.args);
        }
    }

    match cmd.spawn() {
        Ok(child) => {
            tracing::info!("Launched {command_id} → {binary} (pid {})", child.id());
            Some(child.id())
        }
        Err(e) => {
            tracing::debug!("Spawn failed for {command_id} ({binary}): {e} — showing stub");
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{AppsConfig, LaunchConfig};
    use torchform_config::AppLaunchOverride;

    fn empty_launch() -> LaunchConfig {
        LaunchConfig::default()
    }

    #[test]
    fn returns_false_for_unknown_command() {
        let apps = AppsConfig::default();
        let launch = empty_launch();
        assert!(try_launch_external("app.unknown", &apps, &launch).is_none());
    }

    #[test]
    fn returns_false_for_empty_binary() {
        let apps = AppsConfig { camera: String::new(), ..AppsConfig::default() };
        let launch = empty_launch();
        assert!(try_launch_external("app.camera", &apps, &launch).is_none());
    }

    #[test]
    fn returns_false_when_binary_not_found() {
        let apps = AppsConfig {
            settings: "this-binary-definitely-does-not-exist-xyz".into(),
            ..AppsConfig::default()
        };
        let launch = empty_launch();
        assert!(try_launch_external("app.settings", &apps, &launch).is_none());
    }

    #[test]
    fn override_binary_is_used() {
        let apps = AppsConfig::default();
        let mut launch = empty_launch();
        launch.apps.insert("app.browser".into(), AppLaunchOverride {
            binary: Some("non-existent-override-browser".into()),
            ..Default::default()
        });
        assert!(try_launch_external("app.browser", &apps, &launch).is_none());
    }

    #[test]
    fn global_env_does_not_panic() {
        let apps = AppsConfig { gpio: String::new(), ..AppsConfig::default() };
        let mut launch = empty_launch();
        launch.env.insert("TEST_VAR".into(), "1".into());
        assert!(try_launch_external("app.gpio", &apps, &launch).is_none());
    }
}
