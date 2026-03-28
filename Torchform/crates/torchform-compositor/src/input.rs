// =============================================================================
// input.rs — Input routing and chord detection
//
// Torchform's input grammar (CONTEXT.md §7.4):
//
//   Left pad (Cirque)  → cursor / navigation (via torchform-inputd uinput)
//   D-pad              → spatial focus movement between UI elements
//   A                  → confirm / select
//   B                  → back / cancel
//   L2 held            → app radial layer 1
//   R2 held            → app radial layer 2
//   L2 + R2            → global system radial menu
//   Select             → command palette
//   Start              → app switcher
//   L1 / R1            → tile switching
// =============================================================================

use std::collections::HashSet;

/// High-level input actions emitted by the compositor toward the shell.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InputAction {
    None,
    OpenRadialApp1,
    OpenRadialApp2,
    OpenRadialSystem,
    CloseRadial,
    OpenCommandPalette,
    OpenAppSwitcher,
    Confirm,
    Back,
    FocusLeft,
    FocusRight,
    FocusUp,
    FocusDown,
    SwitchTileLeft,
    SwitchTileRight,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum MinervaButton {
    L1, R1,
    L2, R2,
    A, B, X, Y,
    Start, Select,
    DpadUp, DpadDown, DpadLeft, DpadRight,
}

// ---------------------------------------------------------------------------
// Chord tracker
// ---------------------------------------------------------------------------

#[derive(Debug, Default)]
pub struct ChordTracker {
    held: HashSet<MinervaButton>,
}

impl ChordTracker {
    pub fn press(&mut self, btn: MinervaButton) -> InputAction {
        self.held.insert(btn.clone());
        self.evaluate_press(&btn)
    }

    pub fn release(&mut self, btn: MinervaButton) -> InputAction {
        let was_chord = self.is_system_radial_chord();
        self.held.remove(&btn);
        match btn {
            MinervaButton::L2 | MinervaButton::R2 if was_chord => InputAction::CloseRadial,
            MinervaButton::L2 if !self.held.contains(&MinervaButton::R2) => InputAction::CloseRadial,
            MinervaButton::R2 if !self.held.contains(&MinervaButton::L2) => InputAction::CloseRadial,
            _ => InputAction::None,
        }
    }

    fn is_system_radial_chord(&self) -> bool {
        self.held.contains(&MinervaButton::L2) && self.held.contains(&MinervaButton::R2)
    }

    fn evaluate_press(&self, btn: &MinervaButton) -> InputAction {
        match btn {
            MinervaButton::L2 if self.held.contains(&MinervaButton::R2) => InputAction::OpenRadialSystem,
            MinervaButton::R2 if self.held.contains(&MinervaButton::L2) => InputAction::OpenRadialSystem,
            MinervaButton::L2    => InputAction::OpenRadialApp1,
            MinervaButton::R2    => InputAction::OpenRadialApp2,
            MinervaButton::Select => InputAction::OpenCommandPalette,
            MinervaButton::Start  => InputAction::OpenAppSwitcher,
            MinervaButton::A      => InputAction::Confirm,
            MinervaButton::B      => InputAction::Back,
            MinervaButton::DpadLeft  => InputAction::FocusLeft,
            MinervaButton::DpadRight => InputAction::FocusRight,
            MinervaButton::DpadUp    => InputAction::FocusUp,
            MinervaButton::DpadDown  => InputAction::FocusDown,
            MinervaButton::L1 => InputAction::SwitchTileLeft,
            MinervaButton::R1 => InputAction::SwitchTileRight,
            _ => InputAction::None,
        }
    }
}

// ---------------------------------------------------------------------------
// Map Linux evdev BTN_* key codes to MinervaButton
// ---------------------------------------------------------------------------

pub fn evdev_to_button(code: u32) -> Option<MinervaButton> {
    match code {
        0x130 => Some(MinervaButton::A),
        0x131 => Some(MinervaButton::B),
        0x133 => Some(MinervaButton::X),
        0x134 => Some(MinervaButton::Y),
        0x136 => Some(MinervaButton::L1),
        0x137 => Some(MinervaButton::R1),
        0x138 => Some(MinervaButton::L2),
        0x139 => Some(MinervaButton::R2),
        0x13a => Some(MinervaButton::Select),
        0x13b => Some(MinervaButton::Start),
        0x220 => Some(MinervaButton::DpadUp),
        0x221 => Some(MinervaButton::DpadDown),
        0x222 => Some(MinervaButton::DpadLeft),
        0x223 => Some(MinervaButton::DpadRight),
        _ => None,
    }
}
