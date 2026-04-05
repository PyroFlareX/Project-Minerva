// =============================================================================
// chord.rs — Chord detection and input event normalisation
//
// Reads raw gamepad events from /dev/input/event* (the input MCU's USB HID
// gamepad interface) and emits high-level InputActions. Also handles:
//   - L2/R2 chord detection (both held → system radial)
//   - D-pad hat-switch decoding (ABS_HAT0X / ABS_HAT0Y → directional events)
//   - Repeat suppression for held directional inputs
// =============================================================================

use std::{
    collections::HashMap,
    time::{Duration, Instant},
};

// ---------------------------------------------------------------------------
// High-level input actions emitted by the chord detector
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq)]
pub enum Action {
    // Buttons — edge-triggered
    ButtonPressed(Button),
    ButtonReleased(Button),

    // Analog axes (normalised -1.0..1.0)
    LeftPadMoved { x: f32, y: f32 },   // Cirque trackpad
    RightStickMoved { x: f32, y: f32 },

    // Chords — emitted on state transition
    L2HeldChange(bool),          // true = held, false = released
    R2HeldChange(bool),
    SystemChordEntered,          // L2 + R2 both now held
    SystemChordExited,           // One of L2/R2 released

    // D-pad repeats (held → auto-repeat at 200 ms / 80 ms)
    DpadRepeat(DpadDir),
}

#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Button {
    A, B, X, Y,
    L1, R1,
    L2, R2,
    Start,
    Select,
    DpadUp, DpadDown, DpadLeft, DpadRight,
    LeftPadClick,   // Cirque physical click (if supported)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DpadDir { Up, Down, Left, Right }

// ---------------------------------------------------------------------------
// Linux evdev input_event
// ---------------------------------------------------------------------------

/// Raw layout of a Linux `input_event` struct.
/// Exposed publicly so `main.rs` can cast its read buffer without a second copy.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct InputEventRaw {
    pub sec:   i64,
    pub usec:  i64,
    pub etype: u16,
    pub code:  u16,
    pub value: i32,
}

// EV_ types
const EV_KEY: u16 = 0x01;
const EV_ABS: u16 = 0x03;

// ABS codes for hat switch
const ABS_HAT0X: u16 = 0x10;
const ABS_HAT0Y: u16 = 0x11;

// ABS codes for right stick (TLV493D via MCU)
const ABS_RX: u16 = 0x03;
const ABS_RY: u16 = 0x04;

// ABS codes for L2/R2 analog triggers
const ABS_Z:  u16 = 0x05;
const ABS_RZ: u16 = 0x06;

// BTN codes matching the MCU's HID descriptor
fn btn_code(code: u16) -> Option<Button> {
    match code {
        0x130 => Some(Button::A),
        0x131 => Some(Button::B),
        0x133 => Some(Button::X),
        0x134 => Some(Button::Y),
        0x136 => Some(Button::L1),
        0x137 => Some(Button::R1),
        0x138 => Some(Button::L2),
        0x139 => Some(Button::R2),
        0x13a => Some(Button::Select),
        0x13b => Some(Button::Start),
        0x220 => Some(Button::DpadUp),
        0x221 => Some(Button::DpadDown),
        0x222 => Some(Button::DpadLeft),
        0x223 => Some(Button::DpadRight),
        _ => None,
    }
}

// ---------------------------------------------------------------------------
// ChordDetector
// ---------------------------------------------------------------------------

/// Per-direction repeat state: tracks first press and the next scheduled emit.
struct DpadRepeatState {
    first_press: Instant,
    /// When to next emit; None until the initial delay has elapsed.
    next_emit:   Option<Instant>,
}

pub struct ChordDetector {
    held:          HashMap<Button, Instant>,
    l2_analog:     f32,
    r2_analog:     f32,
    /// Threshold above which analog L2/R2 count as "held"
    analog_thresh: f32,
    /// Per-direction D-pad repeat state
    dpad_repeat:   HashMap<DpadDir, DpadRepeatState>,
    repeat_delay:  Duration,
    repeat_rate:   Duration,
    /// Last known right-stick axes (stored so partial axis updates retain the other component)
    right_stick_x: f32,
    right_stick_y: f32,
}

impl ChordDetector {
    pub fn new() -> Self {
        Self {
            held:          HashMap::new(),
            l2_analog:     0.0,
            r2_analog:     0.0,
            analog_thresh: 0.25,
            dpad_repeat:   HashMap::new(),
            repeat_delay:  Duration::from_millis(400),
            repeat_rate:   Duration::from_millis(80),
            right_stick_x: 0.0,
            right_stick_y: 0.0,
        }
    }

    fn l2_held(&self) -> bool {
        self.held.contains_key(&Button::L2) || self.l2_analog >= self.analog_thresh
    }

    fn r2_held(&self) -> bool {
        self.held.contains_key(&Button::R2) || self.r2_analog >= self.analog_thresh
    }

    fn was_system_chord(&self) -> bool {
        // Before the current event, were both held?
        self.l2_held() && self.r2_held()
    }

    /// Process one raw evdev event and return any emitted actions.
    pub fn process(&mut self, ev: &InputEventRaw) -> Vec<Action> {
        let mut out = Vec::new();

        match ev.etype {
            EV_KEY => {
                if let Some(btn) = btn_code(ev.code) {
                    if ev.value == 1 {
                        // Press
                        let was_chord = self.was_system_chord();
                        self.held.insert(btn.clone(), Instant::now());

                        match btn {
                            Button::L2 => {
                                out.push(Action::L2HeldChange(true));
                                if self.r2_held() && !was_chord {
                                    out.push(Action::SystemChordEntered);
                                }
                            }
                            Button::R2 => {
                                out.push(Action::R2HeldChange(true));
                                if self.l2_held() && !was_chord {
                                    out.push(Action::SystemChordEntered);
                                }
                            }
                            Button::DpadUp    => { self.dpad_repeat.insert(DpadDir::Up,    DpadRepeatState { first_press: Instant::now(), next_emit: None }); }
                            Button::DpadDown  => { self.dpad_repeat.insert(DpadDir::Down,  DpadRepeatState { first_press: Instant::now(), next_emit: None }); }
                            Button::DpadLeft  => { self.dpad_repeat.insert(DpadDir::Left,  DpadRepeatState { first_press: Instant::now(), next_emit: None }); }
                            Button::DpadRight => { self.dpad_repeat.insert(DpadDir::Right, DpadRepeatState { first_press: Instant::now(), next_emit: None }); }
                            _ => {}
                        }

                        out.push(Action::ButtonPressed(btn));
                    } else if ev.value == 0 {
                        // Release
                        let was_chord = self.was_system_chord();
                        self.held.remove(&btn);

                        match btn {
                            Button::L2 => {
                                if was_chord { out.push(Action::SystemChordExited); }
                                out.push(Action::L2HeldChange(false));
                            }
                            Button::R2 => {
                                if was_chord { out.push(Action::SystemChordExited); }
                                out.push(Action::R2HeldChange(false));
                            }
                            Button::DpadUp    => { self.dpad_repeat.remove(&DpadDir::Up); }
                            Button::DpadDown  => { self.dpad_repeat.remove(&DpadDir::Down); }
                            Button::DpadLeft  => { self.dpad_repeat.remove(&DpadDir::Left); }
                            Button::DpadRight => { self.dpad_repeat.remove(&DpadDir::Right); }
                            _ => {}
                        }

                        out.push(Action::ButtonReleased(btn));
                    }
                }
            }

            EV_ABS => {
                match ev.code {
                    // Hat switch → D-pad
                    ABS_HAT0X => match ev.value {
                        -1 => {
                            self.held.insert(Button::DpadLeft, Instant::now());
                            self.dpad_repeat.insert(DpadDir::Left, DpadRepeatState { first_press: Instant::now(), next_emit: None });
                            out.push(Action::ButtonPressed(Button::DpadLeft));
                        }
                        1 => {
                            self.held.insert(Button::DpadRight, Instant::now());
                            self.dpad_repeat.insert(DpadDir::Right, DpadRepeatState { first_press: Instant::now(), next_emit: None });
                            out.push(Action::ButtonPressed(Button::DpadRight));
                        }
                        0 => {
                            self.held.remove(&Button::DpadLeft);
                            self.held.remove(&Button::DpadRight);
                            self.dpad_repeat.remove(&DpadDir::Left);
                            self.dpad_repeat.remove(&DpadDir::Right);
                            out.push(Action::ButtonReleased(Button::DpadLeft));
                            out.push(Action::ButtonReleased(Button::DpadRight));
                        }
                        _ => {}
                    },
                    ABS_HAT0Y => match ev.value {
                        -1 => {
                            self.held.insert(Button::DpadUp, Instant::now());
                            self.dpad_repeat.insert(DpadDir::Up, DpadRepeatState { first_press: Instant::now(), next_emit: None });
                            out.push(Action::ButtonPressed(Button::DpadUp));
                        }
                        1 => {
                            self.held.insert(Button::DpadDown, Instant::now());
                            self.dpad_repeat.insert(DpadDir::Down, DpadRepeatState { first_press: Instant::now(), next_emit: None });
                            out.push(Action::ButtonPressed(Button::DpadDown));
                        }
                        0 => {
                            self.held.remove(&Button::DpadUp);
                            self.held.remove(&Button::DpadDown);
                            self.dpad_repeat.remove(&DpadDir::Up);
                            self.dpad_repeat.remove(&DpadDir::Down);
                            out.push(Action::ButtonReleased(Button::DpadUp));
                            out.push(Action::ButtonReleased(Button::DpadDown));
                        }
                        _ => {}
                    },

                    // Right stick (TLV493D via MCU) — accumulate both axes before emitting
                    ABS_RX => {
                        self.right_stick_x = ev.value as f32 / 32767.0;
                        out.push(Action::RightStickMoved { x: self.right_stick_x, y: self.right_stick_y });
                    }
                    ABS_RY => {
                        self.right_stick_y = ev.value as f32 / 32767.0;
                        out.push(Action::RightStickMoved { x: self.right_stick_x, y: self.right_stick_y });
                    }

                    // L2/R2 analog triggers — also check for system chord entry/exit
                    ABS_Z => {
                        let prev_l2 = self.l2_held();
                        let was_chord = prev_l2 && self.r2_held();
                        self.l2_analog = ev.value as f32 / 255.0;
                        let now_l2 = self.l2_held();
                        if now_l2 != prev_l2 {
                            out.push(Action::L2HeldChange(now_l2));
                            if now_l2 && self.r2_held() && !was_chord {
                                out.push(Action::SystemChordEntered);
                            } else if !now_l2 && was_chord {
                                out.push(Action::SystemChordExited);
                            }
                        }
                    }
                    ABS_RZ => {
                        let prev_r2 = self.r2_held();
                        let was_chord = self.l2_held() && prev_r2;
                        self.r2_analog = ev.value as f32 / 255.0;
                        let now_r2 = self.r2_held();
                        if now_r2 != prev_r2 {
                            out.push(Action::R2HeldChange(now_r2));
                            if now_r2 && self.l2_held() && !was_chord {
                                out.push(Action::SystemChordEntered);
                            } else if !now_r2 && was_chord {
                                out.push(Action::SystemChordExited);
                            }
                        }
                    }

                    _ => {}
                }
            }

            _ => {}
        }

        out
    }

    /// Call periodically to emit D-pad repeat actions at the configured rate.
    pub fn tick_repeats(&mut self) -> Vec<Action> {
        let now = Instant::now();
        let mut out = Vec::new();

        let repeat_delay = self.repeat_delay;
        let repeat_rate  = self.repeat_rate;

        for (dir, state) in &mut self.dpad_repeat {
            // Arm next_emit after the initial delay has elapsed
            if state.next_emit.is_none() {
                let deadline = state.first_press + repeat_delay;
                if now >= deadline {
                    state.next_emit = Some(deadline);
                }
            }
            // Fire (and advance) if the next scheduled emit has arrived
            if let Some(ref mut next) = state.next_emit {
                if now >= *next {
                    out.push(Action::DpadRepeat(*dir));
                    *next += repeat_rate;
                }
            }
        }

        out
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn key_ev(code: u16, value: i32) -> InputEventRaw {
        InputEventRaw { sec: 0, usec: 0, etype: EV_KEY, code, value }
    }

    fn abs_ev(code: u16, value: i32) -> InputEventRaw {
        InputEventRaw { sec: 0, usec: 0, etype: EV_ABS, code, value }
    }

    // BTN_A = 0x130
    const BTN_A: u16 = 0x130;
    const BTN_B: u16 = 0x131;
    const BTN_L2: u16 = 0x138;
    const BTN_R2: u16 = 0x139;

    #[test]
    fn button_press_and_release() {
        let mut cd = ChordDetector::new();

        let actions = cd.process(&key_ev(BTN_A, 1));
        assert!(actions.contains(&Action::ButtonPressed(Button::A)));
        assert!(!actions.contains(&Action::ButtonReleased(Button::A)));

        let actions = cd.process(&key_ev(BTN_A, 0));
        assert!(actions.contains(&Action::ButtonReleased(Button::A)));
    }

    #[test]
    fn unknown_button_produces_no_actions() {
        let mut cd = ChordDetector::new();
        let actions = cd.process(&key_ev(0xFFFF, 1));
        assert!(actions.is_empty());
    }

    #[test]
    fn dpad_hat_x_decodes_to_left_right() {
        let mut cd = ChordDetector::new();

        let actions = cd.process(&abs_ev(ABS_HAT0X, -1));
        assert!(actions.contains(&Action::ButtonPressed(Button::DpadLeft)));

        let actions = cd.process(&abs_ev(ABS_HAT0X, 0));
        assert!(actions.contains(&Action::ButtonReleased(Button::DpadLeft)));
        assert!(actions.contains(&Action::ButtonReleased(Button::DpadRight)));

        let actions = cd.process(&abs_ev(ABS_HAT0X, 1));
        assert!(actions.contains(&Action::ButtonPressed(Button::DpadRight)));
    }

    #[test]
    fn dpad_hat_y_decodes_to_up_down() {
        let mut cd = ChordDetector::new();

        let actions = cd.process(&abs_ev(ABS_HAT0Y, -1));
        assert!(actions.contains(&Action::ButtonPressed(Button::DpadUp)));

        let actions = cd.process(&abs_ev(ABS_HAT0Y, 1));
        assert!(actions.contains(&Action::ButtonPressed(Button::DpadDown)));

        let actions = cd.process(&abs_ev(ABS_HAT0Y, 0));
        assert!(actions.contains(&Action::ButtonReleased(Button::DpadUp)));
        assert!(actions.contains(&Action::ButtonReleased(Button::DpadDown)));
    }

    #[test]
    fn l2_r2_digital_chord_enter_and_exit() {
        let mut cd = ChordDetector::new();

        // Press L2 — held change, no chord yet
        let actions = cd.process(&key_ev(BTN_L2, 1));
        assert!(actions.contains(&Action::L2HeldChange(true)));
        assert!(!actions.contains(&Action::SystemChordEntered));

        // Press R2 — chord entered
        let actions = cd.process(&key_ev(BTN_R2, 1));
        assert!(actions.contains(&Action::R2HeldChange(true)));
        assert!(actions.contains(&Action::SystemChordEntered));

        // Release L2 — chord exited
        let actions = cd.process(&key_ev(BTN_L2, 0));
        assert!(actions.contains(&Action::SystemChordExited));
        assert!(actions.contains(&Action::L2HeldChange(false)));

        // Release R2 — no second exit
        let actions = cd.process(&key_ev(BTN_R2, 0));
        assert!(!actions.contains(&Action::SystemChordExited));
        assert!(actions.contains(&Action::R2HeldChange(false)));
    }

    #[test]
    fn analog_l2_crosses_threshold_emits_held_change() {
        let mut cd = ChordDetector::new();

        // Below threshold (25% = 63/255)
        let actions = cd.process(&abs_ev(ABS_Z, 50));
        assert!(actions.is_empty());

        // Cross threshold (30% = 76/255)
        let actions = cd.process(&abs_ev(ABS_Z, 76));
        assert!(actions.contains(&Action::L2HeldChange(true)));

        // Back below
        let actions = cd.process(&abs_ev(ABS_Z, 10));
        assert!(actions.contains(&Action::L2HeldChange(false)));
    }

    #[test]
    fn analog_l2_r2_both_cross_threshold_enters_chord() {
        let mut cd = ChordDetector::new();

        // L2 crosses threshold
        cd.process(&abs_ev(ABS_Z, 100));

        // R2 crosses — chord should be entered
        let actions = cd.process(&abs_ev(ABS_RZ, 100));
        assert!(actions.contains(&Action::SystemChordEntered));

        // R2 drops — chord exited
        let actions = cd.process(&abs_ev(ABS_RZ, 0));
        assert!(actions.contains(&Action::SystemChordExited));
    }

    #[test]
    fn right_stick_retains_other_axis() {
        let mut cd = ChordDetector::new();

        // Move X axis to max
        let actions = cd.process(&abs_ev(ABS_RX, 32767));
        assert!(actions.iter().any(|a| matches!(a, Action::RightStickMoved { x, y } if *x > 0.9 && *y == 0.0)));

        // Move Y axis — X should still be 1.0, not reset to 0
        let actions = cd.process(&abs_ev(ABS_RY, 16384));
        assert!(actions.iter().any(|a| matches!(a, Action::RightStickMoved { x, y } if *x > 0.9 && *y > 0.4)));
    }

    #[test]
    fn tick_repeats_empty_when_no_dpad_held() {
        let mut cd = ChordDetector::new();
        assert!(cd.tick_repeats().is_empty());
    }

    #[test]
    fn tick_repeats_does_not_fire_before_delay() {
        let mut cd = ChordDetector::new();
        // Set a very long delay so it won't fire in a test
        cd.repeat_delay = Duration::from_secs(9999);
        cd.process(&abs_ev(ABS_HAT0Y, -1)); // DpadUp held
        assert!(cd.tick_repeats().is_empty());
    }

    #[test]
    fn tick_repeats_fires_after_delay_and_stops_when_released() {
        let mut cd = ChordDetector::new();
        // Make delay=0 so the repeat fires immediately on the next tick
        cd.repeat_delay = Duration::ZERO;
        cd.repeat_rate  = Duration::ZERO;

        cd.process(&abs_ev(ABS_HAT0Y, -1)); // DpadUp held

        let repeats = cd.tick_repeats();
        assert!(repeats.contains(&Action::DpadRepeat(DpadDir::Up)));

        // Release — no more repeats
        cd.process(&abs_ev(ABS_HAT0Y, 0));
        assert!(cd.tick_repeats().is_empty());
    }

    #[test]
    fn dpad_button_code_path_repeat_state_cleared_on_release() {
        let mut cd = ChordDetector::new();
        cd.repeat_delay = Duration::ZERO;
        cd.repeat_rate  = Duration::ZERO;

        cd.process(&key_ev(0x220, 1)); // DpadUp (BTN_DPAD_UP)
        assert!(!cd.tick_repeats().is_empty());

        cd.process(&key_ev(0x220, 0)); // release
        assert!(cd.tick_repeats().is_empty());
    }
}
