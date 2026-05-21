// =============================================================================
// torchform-config — Shared configuration and settings schema
//
// Provides:
//   • TorchformConfig — full DE config tree, loaded from TOML
//   • SettingsSchema   — config-file-driven display list (sections + rows)
//   • Settings model builder + mutation helpers
//   • Dotfile discovery scanner
//
// Does NOT depend on Slint.
// =============================================================================

pub mod config;
pub mod settings;
pub mod dotfiles;

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
    DotfileConfig,
    DotfileCacheEntry,
    ChordBind,
    HoldBind,
    KeybindFile,
    expand_tilde,
    user_config_path,
};

pub use settings::{
    WidgetDef,
    RowDef,
    SectionDef,
    SettingsSchema,
    SettingsRowData,
    make_settings_entries,
    make_section_entries,
    apply_activation,
    apply_adjustment,
    focus_up,
    focus_down,
};

pub use dotfiles::{
    DotfileEntry,
    DotfileFormat,
    scan_config_dir,
};
