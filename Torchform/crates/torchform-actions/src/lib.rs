// =============================================================================
// torchform-actions — Shared action types and input keybind config
//
// This crate is the single source of truth for:
//
//   1. `ShellAction` — the virtualized, semantic action enum that the shell
//      and all shell-facing components consume.  No raw button names leak
//      past this layer.
//
//   2. `InputMap` — the TOML-configurable mapping from raw input identifiers
//      (button names, chord names) to `ShellAction` values.
//
// The flow is:
//
//   Hardware event (evdev / gilrs)
//       ↓
//   torchform-inputd chord detector
//       ↓  produces RawInput
//   InputMap::resolve(raw) → Option<ShellAction>
//       ↓
//   ShellAction published over Unix socket to torchform-shell
//       ↓
//   Shell reacts to ShellAction (no button name strings anywhere)
//
// Config file location (searched in order):
//   ~/.config/torchform/keybinds.toml
//   /etc/torchform/keybinds.toml
//   ./config/keybinds.toml
//
// If no file is found the built-in defaults are used — the device works
// out of the box without any config.
// =============================================================================

pub mod action;
pub mod input_map;

pub use action::ShellAction;
pub use input_map::{InputMap, RawInput};
