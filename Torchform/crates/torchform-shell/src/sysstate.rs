// sysstate.rs — thin wrappers around Linux sysfs + ALSA/PulseAudio calls.
//
// All functions are no-ops (log a warning) when not on Linux or when the
// relevant sysfs path doesn't exist — so the emulator keeps working on
// desktop with no hardware attached.

/// Write brightness to sysfs backlight.
/// Searches for the first available backlight device.
pub fn set_brightness(pct: i32) {
    #[cfg(target_os = "linux")]
    {
        if let Some((max, path)) = find_backlight() {
            let raw = ((pct.clamp(0, 100) as f64 / 100.0) * max as f64).round() as u64;
            if let Err(e) = std::fs::write(&path, raw.to_string()) {
                tracing::warn!("brightness write failed: {e}");
            }
            return;
        }
        tracing::debug!("no backlight device found — brightness not applied");
    }
    #[cfg(not(target_os = "linux"))]
    tracing::debug!("set_brightness({pct}) — non-Linux, skipped");
}

#[cfg(target_os = "linux")]
fn find_backlight() -> Option<(u64, std::path::PathBuf)> {
    let dir = std::path::Path::new("/sys/class/backlight");
    for entry in std::fs::read_dir(dir).ok()?.flatten() {
        let base = entry.path();
        let max_path = base.join("max_brightness");
        let cur_path = base.join("brightness");
        if let Ok(max_str) = std::fs::read_to_string(&max_path) {
            if let Ok(max) = max_str.trim().parse::<u64>() {
                return Some((max, cur_path));
            }
        }
    }
    None
}

/// Adjust the default audio sink volume via pactl.
/// Prefers pactl (PulseAudio/PipeWire); falls back silently on failure.
pub fn set_volume(pct: i32) {
    let pct = pct.clamp(0, 100);
    #[cfg(target_os = "linux")]
    {
        let status = std::process::Command::new("pactl")
            .args(["set-sink-volume", "@DEFAULT_SINK@", &format!("{pct}%")])
            .status();
        match status {
            Ok(s) if s.success() => {}
            Ok(s) => tracing::warn!("pactl exited {s}"),
            Err(e) => tracing::debug!("pactl not available: {e}"),
        }
    }
    #[cfg(not(target_os = "linux"))]
    tracing::debug!("set_volume({pct}) — non-Linux, skipped");
}

/// Read battery percentage from sysfs. Returns None if no battery found.
pub fn read_battery() -> Option<i32> {
    #[cfg(target_os = "linux")]
    {
        let dir = std::path::Path::new("/sys/class/power_supply");
        for entry in std::fs::read_dir(dir).ok()?.flatten() {
            let base = entry.path();
            let type_path = base.join("type");
            let cap_path  = base.join("capacity");
            if let Ok(t) = std::fs::read_to_string(&type_path) {
                if t.trim() == "Battery" {
                    if let Ok(cap) = std::fs::read_to_string(&cap_path) {
                        return cap.trim().parse().ok();
                    }
                }
            }
        }
    }
    None
}

/// Read charging status. Returns true if any supply is "Charging" or "Full".
pub fn read_charging() -> bool {
    #[cfg(target_os = "linux")]
    {
        let dir = std::path::Path::new("/sys/class/power_supply");
        if let Ok(entries) = std::fs::read_dir(dir) {
            for entry in entries.flatten() {
                let status_path = entry.path().join("status");
                if let Ok(s) = std::fs::read_to_string(&status_path) {
                    let s = s.trim();
                    if s == "Charging" || s == "Full" {
                        return true;
                    }
                }
            }
        }
    }
    false
}
