//! Normalized logical buttons and axes — the device-independent vocabulary the
//! rest of the daemon speaks. Per-device profiles (see `config`) translate raw
//! evdev codes into these; the virtual pad (see `virtpad`) translates these back
//! into a single standard evdev layout that apps and the Quickshell.Gamepad
//! plugin consume.

use std::str::FromStr;

/// A logical (controller-independent) button.
///
/// Names follow the modern evdev gamepad convention (SOUTH/EAST/WEST/NORTH for
/// the face cluster) rather than vendor labels, so a binding written once works
/// across an Xbox pad, the DragonRise, etc. The shell layer assigns meaning
/// (South = confirm, East = back, …).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum LogicalButton {
    South,  // bottom face  (Xbox A / SNES B)
    East,   // right face   (Xbox B / SNES A)
    West,   // left face    (Xbox X / SNES Y)
    North,  // top face     (Xbox Y / SNES X)
    L1,
    R1,
    L2,     // digital click of the trigger (analog value still passes as an axis)
    R2,
    Select,
    Start,
    Mode,   // guide / home
    ThumbL,
    ThumbR,
    DpadUp,
    DpadDown,
    DpadLeft,
    DpadRight,
}

impl LogicalButton {
    pub const ALL: [LogicalButton; 17] = [
        LogicalButton::South, LogicalButton::East, LogicalButton::West, LogicalButton::North,
        LogicalButton::L1, LogicalButton::R1, LogicalButton::L2, LogicalButton::R2,
        LogicalButton::Select, LogicalButton::Start, LogicalButton::Mode,
        LogicalButton::ThumbL, LogicalButton::ThumbR,
        LogicalButton::DpadUp, LogicalButton::DpadDown, LogicalButton::DpadLeft, LogicalButton::DpadRight,
    ];

    /// Stable lowercase name used in the TOML config and the action manifest.
    pub fn as_str(self) -> &'static str {
        match self {
            LogicalButton::South => "south",
            LogicalButton::East => "east",
            LogicalButton::West => "west",
            LogicalButton::North => "north",
            LogicalButton::L1 => "l1",
            LogicalButton::R1 => "r1",
            LogicalButton::L2 => "l2",
            LogicalButton::R2 => "r2",
            LogicalButton::Select => "select",
            LogicalButton::Start => "start",
            LogicalButton::Mode => "mode",
            LogicalButton::ThumbL => "thumbl",
            LogicalButton::ThumbR => "thumbr",
            LogicalButton::DpadUp => "dpad_up",
            LogicalButton::DpadDown => "dpad_down",
            LogicalButton::DpadLeft => "dpad_left",
            LogicalButton::DpadRight => "dpad_right",
        }
    }

    /// True for the four d-pad directions. (Used by the shell's nav auto-repeat,
    /// kept here as part of the shared vocabulary.)
    #[allow(dead_code)]
    pub fn is_dpad(self) -> bool {
        matches!(
            self,
            LogicalButton::DpadUp | LogicalButton::DpadDown
                | LogicalButton::DpadLeft | LogicalButton::DpadRight
        )
    }
}

impl FromStr for LogicalButton {
    type Err = String;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        for b in LogicalButton::ALL {
            if b.as_str().eq_ignore_ascii_case(s) {
                return Ok(b);
            }
        }
        Err(format!("unknown logical button '{s}'"))
    }
}

/// A logical analog axis. Sticks and triggers are passed through unchanged; the
/// engine does not interpret them (the shell reads them directly off the virtual
/// pad). D-pad-as-hat (ABS_HAT0X/Y) is converted to DpadLeft/Right/Up/Down
/// buttons in the device layer so chords/repeat can act on it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum LogicalAxis {
    LeftX,
    LeftY,
    RightX,
    RightY,
    L2Analog,
    R2Analog,
}

impl LogicalAxis {
    #[allow(dead_code)] // part of the vocabulary; used for logging/manifest
    pub fn as_str(self) -> &'static str {
        match self {
            LogicalAxis::LeftX => "left_x",
            LogicalAxis::LeftY => "left_y",
            LogicalAxis::RightX => "right_x",
            LogicalAxis::RightY => "right_y",
            LogicalAxis::L2Analog => "l2_analog",
            LogicalAxis::R2Analog => "r2_analog",
        }
    }
}

impl FromStr for LogicalAxis {
    type Err = String;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Ok(match s.to_ascii_lowercase().as_str() {
            "left_x" => LogicalAxis::LeftX,
            "left_y" => LogicalAxis::LeftY,
            "right_x" => LogicalAxis::RightX,
            "right_y" => LogicalAxis::RightY,
            "l2_analog" => LogicalAxis::L2Analog,
            "r2_analog" => LogicalAxis::R2Analog,
            other => return Err(format!("unknown logical axis '{other}'")),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn button_roundtrip() {
        for b in LogicalButton::ALL {
            assert_eq!(LogicalButton::from_str(b.as_str()).unwrap(), b);
        }
    }

    #[test]
    fn button_parse_is_case_insensitive() {
        assert_eq!(LogicalButton::from_str("SOUTH").unwrap(), LogicalButton::South);
        assert_eq!(LogicalButton::from_str("Dpad_Up").unwrap(), LogicalButton::DpadUp);
    }
}
