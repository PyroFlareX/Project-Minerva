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
//   2. Add a match arm here to spawn the process.
//   3. If you want a built-in stub, add an AppFoo component in a new .slint
//      file, embed it in emulator.slint / shell.slint, add an ActiveApp
//      variant in main.rs, and route D-pad / A / B events to it.
// Binary names come from config.toml [apps] — no hardcoded strings here.
// =============================================================================

use crate::config::AppsConfig;

/// Try to launch the external binary mapped to `command_id` in the config.
/// Returns `true` if a process was successfully spawned (real DE path).
/// Returns `false` if the config maps no binary, or the spawn fails
/// (binary not installed) — the caller should show the built-in stub.
pub fn try_launch_external(command_id: &str, cfg: &AppsConfig) -> bool {
    match cfg.binary_for(command_id) {
        Some(binary) => {
            let ok = std::process::Command::new(binary).spawn().is_ok();
            if !ok {
                tracing::debug!("Binary not found for {command_id}: {binary}");
            }
            ok
        }
        None => false,
    }
}
