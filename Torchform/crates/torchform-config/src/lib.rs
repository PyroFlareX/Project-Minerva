// =============================================================================
// torchform-config — Shared configuration and settings schema
//
// Provides:
//   • TorchformConfig — full DE config tree, loaded from TOML
//   • Settings schema (SCHEMA, SettingsDef, Widget) + model builder
//   • Settings mutation helpers (apply_activation, apply_adjustment)
//   • Settings navigation helpers (focus_up, focus_down)
//
// Does NOT depend on Slint.  Binaries that need to build Slint models do
// so themselves by iterating the SettingsRowData vec.
// =============================================================================

pub mod config;
pub mod settings;

pub use config::{
    TorchformConfig,
    GeneralConfig,
    ThemeConfig,
    ThemeColors,
    ThemeTypography,
    ResolvedTheme,
    AppsConfig,
    AppLaunchOverride,
    LaunchConfig,
    InputConfig,
    RadialConfig,
    RadialLayerConfig,
    RadialSlotConfig,
    expand_tilde,
    user_config_path,
};

pub use settings::{
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
