// =============================================================================
// config.rs (torchform-shell) — re-exports from torchform-config
//
// All config types and the settings schema live in the shared `torchform-config`
// crate so other binaries (torchform-settings, torchform-files, etc.) can use
// them without pulling in Slint.
//
// This file adds only the Slint-specific `parse_color` helper that converts
// hex color strings from TorchformConfig into `slint::Color` values.
// =============================================================================

// Re-export everything from the shared crate under the same module path so
// the rest of torchform-shell doesn't need to change its use paths.
pub use torchform_config::{
    TorchformConfig,
    ResolvedTheme,
    AppsConfig,
    LaunchConfig,
    RadialSlotConfig,
    user_config_path,
};

// ---------------------------------------------------------------------------
// Colour parsing — Slint-specific, stays in this crate
//
// Parses "#rrggbb" and "#rrggbbaa" hex strings into slint::Color.
// Invalid strings fall back to magenta so misconfigured themes are obvious.
// ---------------------------------------------------------------------------

pub fn parse_color(hex: &str) -> slint::Color {
    let s = hex.trim_start_matches('#');
    let fallback = slint::Color::from_rgb_u8(0xff, 0x00, 0xff); // magenta
    match s.len() {
        6 => {
            let r = u8::from_str_radix(&s[0..2], 16).unwrap_or(0xff);
            let g = u8::from_str_radix(&s[2..4], 16).unwrap_or(0x00);
            let b = u8::from_str_radix(&s[4..6], 16).unwrap_or(0xff);
            slint::Color::from_rgb_u8(r, g, b)
        }
        8 => {
            let r = u8::from_str_radix(&s[0..2], 16).unwrap_or(0xff);
            let g = u8::from_str_radix(&s[2..4], 16).unwrap_or(0x00);
            let b = u8::from_str_radix(&s[4..6], 16).unwrap_or(0xff);
            let a = u8::from_str_radix(&s[6..8], 16).unwrap_or(0xff);
            slint::Color::from_argb_u8(a, r, g, b)
        }
        _ => {
            tracing::warn!("Invalid color value: {hex:?}");
            fallback
        }
    }
}
