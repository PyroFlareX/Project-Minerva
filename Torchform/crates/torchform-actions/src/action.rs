// =============================================================================
// action.rs — ShellAction: the virtualized semantic action enum
//
// Every interaction the shell ever needs to respond to is expressed as a
// ShellAction variant.  Raw button names, chord states, and evdev codes are
// entirely absent from this type.
//
// Naming rules:
//   • Directional navigation: Nav{Up,Down,Left,Right}
//   • Confirm / cancel semantics: Confirm, Cancel
//   • Named overlays: OpenPalette, OpenSwitcher, RadialOpen, RadialClose
//   • Continuous inputs carry their current value: StickMoved, RadialStick
//   • System actions: WorkspacePrev, WorkspaceNext, SplitToggle, Sleep
//   • Lower-screen specific: LowerTap, LowerKeyPress, LowerBackspace, LowerSubmit
// =============================================================================

use serde::{Deserialize, Serialize};

/// A semantic shell action, fully decoupled from physical inputs.
///
/// Variants that carry bool (`RadialHold`, `L1`, `R1`) use `true` for
/// "pressed / active" and `false` for "released / inactive".
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case")]
pub enum ShellAction {
    // -----------------------------------------------------------------
    // Navigation — direction inside any focused list / grid / menu
    // -----------------------------------------------------------------
    NavUp,
    NavDown,
    NavLeft,
    NavRight,

    // -----------------------------------------------------------------
    // Confirm / cancel — confirm the focused item, cancel / back out
    // -----------------------------------------------------------------
    Confirm,
    Cancel,

    // -----------------------------------------------------------------
    // Overlay triggers
    // -----------------------------------------------------------------
    /// Toggle the command palette open/closed.
    OpenPalette,
    /// Toggle the app switcher overlay.
    OpenSwitcher,

    // -----------------------------------------------------------------
    // Radial menu
    // `RadialHold(true)` = trigger held (open menu)
    // `RadialHold(false)` = trigger released (commit selection / close)
    // -----------------------------------------------------------------
    RadialHold { held: bool },

    // -----------------------------------------------------------------
    // Analog stick — normalized [-1.0, 1.0] on each axis.
    // Used to steer the radial menu and future analog-sensitive widgets.
    // -----------------------------------------------------------------
    StickMoved { x: f32, y: f32 },

    // -----------------------------------------------------------------
    // Left-pad / trackpad moved (Cirque GlidePoint).
    // Coordinates are normalized [-1.0, 1.0].
    // -----------------------------------------------------------------
    PadMoved { x: f32, y: f32 },

    // -----------------------------------------------------------------
    // Workspace cycling (L1 / R1 on hardware)
    // -----------------------------------------------------------------
    WorkspacePrev,
    WorkspaceNext,

    // -----------------------------------------------------------------
    // System / power
    // -----------------------------------------------------------------
    BrightnessUp,
    BrightnessDown,
    VolumeUp,
    VolumeDown,
    WifiToggle,
    BluetoothToggle,
    CellularToggle,
    VpnToggle,
    SplitToggle,
    Sleep,

    // -----------------------------------------------------------------
    // Lower screen input (virtual keyboard / touchscreen taps)
    // -----------------------------------------------------------------
    /// A key was pressed on the virtual keyboard (single UTF-8 grapheme).
    LowerKeyPress { key: String },
    /// Backspace on the virtual keyboard.
    LowerBackspace,
    /// Submit / enter on the virtual keyboard.
    LowerSubmit,
    /// Touch tap on the lower touchscreen.
    LowerTap { x: f32, y: f32 },

    // -----------------------------------------------------------------
    // Voice / text injection from an external voice-recognition process
    // -----------------------------------------------------------------
    VoiceResult { text: String },
}
