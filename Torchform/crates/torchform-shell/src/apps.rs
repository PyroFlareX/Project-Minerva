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
// =============================================================================

/// Try to launch an external process for the given palette command ID.
/// Returns `true` if a process was successfully spawned (real DE path).
/// Returns `false` if the binary was not found — caller should show the stub.
pub fn try_launch_external(command_id: &str) -> bool {
    match command_id {
        "app.settings" | "settings" | "open-settings" => {
            std::process::Command::new("gnome-control-center").spawn().is_ok()
        }
        "app.files" | "file-manager" | "open-files" => {
            // Thunar is the preferred file manager for the CM5 build.
            // Any Wayland-native file manager works; it connects to
            // $WAYLAND_DISPLAY set by torchform-compositor.
            std::process::Command::new("thunar").spawn().is_ok()
        }
        _ => false,
    }
}
