// =============================================================================
// settings.rs (torchform-shell) — re-exports from torchform-config
//
// The full settings schema, model builder, and mutation logic live in the
// shared `torchform-config` crate.  This file just re-exports them so
// `main.rs` can continue to write `settings::make_settings_entries` etc.
// without path changes.
// =============================================================================

pub use torchform_config::{
    Widget,
    SettingsDef,
    Section,
    SCHEMA,
    SettingsRowData,
    make_settings_entries,
    apply_activation,
    apply_adjustment,
    focus_up,
    focus_down,
};
