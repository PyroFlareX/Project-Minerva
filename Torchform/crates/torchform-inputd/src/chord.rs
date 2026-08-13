// =============================================================================
// chord.rs — Chord/hold detection and input event normalisation
//
// Reads raw gamepad events from /dev/input/event* (the input MCU's USB HID
// gamepad interface) and emits high-level Actions.  Also handles:
//
//   • Generic N-button chord detection (simultaneous press within within_ms)
//   • Generic N-button hold detection (all held for hold_ms)
//   • D-pad hat-switch decoding + repeat
//   • L2/R2 analog trigger hold state + SystemChordEntered/Exited (compat)
//
// Chord patterns and hold patterns are loaded from keybinds.toml at startup
// via `ChordDetector::with_patterns()`.  The old hardcoded L2+R2 logic is
// replaced by a built-in default pattern in `ChordDetector::new()`.
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
    RightStickMoved { x: f32, y: f32 },

    // Legacy L2/R2 chord state signals (kept for radial visual state)
    L2HeldChange(bool),
    R2HeldChange(bool),
    SystemChordEntered,
    SystemChordExited,

    // Generic chord/hold events — resolved to ShellActions by ChordMap
    ChordFired { name: String },
    HoldFired  { name: String },

    // D-pad repeat (held → auto-repeat)
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
    LeftPadClick,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DpadDir { Up, Down, Left, Right }

// ---------------------------------------------------------------------------
// Linux evdev input_event
// ---------------------------------------------------------------------------

#[repr(C)]
#[derive(Clone, Copy)]
pub struct InputEventRaw {
    pub sec:   i64,
    pub usec:  i64,
    pub etype: u16,
    pub code:  u16,
    pub value: i32,
}

const EV_KEY:    u16 = 0x01;
const EV_ABS:    u16 = 0x03;
const ABS_HAT0X: u16 = 0x10;
const ABS_HAT0Y: u16 = 0x11;
const ABS_RX:    u16 = 0x03;
const ABS_RY:    u16 = 0x04;
const ABS_Z:     u16 = 0x05;
const ABS_RZ:    u16 = 0x06;

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

/// Canonical name for a Button used in chord/hold pattern matching.
fn button_name(b: Button) -> &'static str {
    match b {
        Button::A          => "button_a",
        Button::B          => "button_b",
        Button::X          => "button_x",
        Button::Y          => "button_y",
        Button::L1         => "l1",
        Button::R1         => "r1",
        Button::L2         => "l2",
        Button::R2         => "r2",
        Button::Start      => "button_start",
        Button::Select     => "button_select",
        Button::DpadUp     => "dpad_up",
        Button::DpadDown   => "dpad_down",
        Button::DpadLeft   => "dpad_left",
        Button::DpadRight  => "dpad_right",
        Button::LeftPadClick => "pad_click",
    }
}

fn canonical_chord_name(buttons: &[Button]) -> String {
    let mut names: Vec<&str> = buttons.iter().map(|b| button_name(*b)).collect();
    names.sort_unstable();
    names.join("+")
}

// ---------------------------------------------------------------------------
// Chord / hold pattern descriptors
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct ChordPattern {
    pub buttons:   Vec<Button>,
    pub within_ms: u64,
    pub name:      String,
}

#[derive(Debug, Clone)]
pub struct HoldPattern {
    pub buttons: Vec<Button>,
    pub hold_ms: u64,
    pub name:    String,
}

// ---------------------------------------------------------------------------
// D-pad repeat state
// ---------------------------------------------------------------------------

struct DpadRepeatState {
    first_press: Instant,
    next_emit:   Option<Instant>,
}

// ---------------------------------------------------------------------------
// ChordDetector
// ---------------------------------------------------------------------------

pub struct ChordDetector {
    held:             HashMap<Button, Instant>,
    l2_analog:        f32,
    r2_analog:        f32,
    analog_thresh:    f32,
    dpad_repeat:      HashMap<DpadDir, DpadRepeatState>,
    pub repeat_delay: Duration,
    pub repeat_rate:  Duration,
    right_stick_x:    f32,
    right_stick_y:    f32,

    // Generic pattern tables
    chord_patterns: Vec<ChordPattern>,
    hold_patterns:  Vec<HoldPattern>,
    hold_deadlines: HashMap<String, Instant>,

    // Track which chords already fired (reset when any button releases)
    chord_fired: std::collections::HashSet<String>,
}

impl ChordDetector {
    pub fn new() -> Self {
        let mut det = Self {
            held:           HashMap::new(),
            l2_analog:      0.0,
            r2_analog:      0.0,
            analog_thresh:  0.25,
            dpad_repeat:    HashMap::new(),
            repeat_delay:   Duration::from_millis(400),
            repeat_rate:    Duration::from_millis(80),
            right_stick_x:  0.0,
            right_stick_y:  0.0,
            chord_patterns: Vec::new(),
            hold_patterns:  Vec::new(),
            hold_deadlines: HashMap::new(),
            chord_fired:    std::collections::HashSet::new(),
        };

        // Built-in L2+R2 chord (backward compat with SystemChordEntered)
        det.chord_patterns.push(ChordPattern {
            buttons:   vec![Button::L2, Button::R2],
            within_ms: 80,
            name:      "l2+r2".into(),
        });

        det
    }

    /// Load chord and hold patterns from external config.
    /// This ADDS to the built-in patterns (doesn't replace them).
    // Retained for the pending keybind pattern loader.
    #[allow(dead_code)]
    pub fn with_patterns(mut self, chords: Vec<ChordPattern>, holds: Vec<HoldPattern>) -> Self {
        for c in chords {
            if !self.chord_patterns.iter().any(|p| p.name == c.name) {
                self.chord_patterns.push(c);
            }
        }
        self.hold_patterns = holds;
        self
    }

    fn l2_held(&self) -> bool {
        self.held.contains_key(&Button::L2) || self.l2_analog >= self.analog_thresh
    }

    fn r2_held(&self) -> bool {
        self.held.contains_key(&Button::R2) || self.r2_analog >= self.analog_thresh
    }

    fn was_system_chord(&self) -> bool {
        self.l2_held() && self.r2_held()
    }

    // -----------------------------------------------------------------------
    // Generic chord check — called on every button press
    // -----------------------------------------------------------------------

    fn check_chords(&mut self, just_pressed: Button, out: &mut Vec<Action>) {
        let now = Instant::now();

        for pattern in &self.chord_patterns {
            if self.chord_fired.contains(&pattern.name) {
                continue;
            }
            if !pattern.buttons.contains(&just_pressed) {
                continue;
            }
            // All other buttons in the pattern must currently be held
            let all_held = pattern.buttons.iter()
                .filter(|&&b| b != just_pressed)
                .all(|b| self.held.contains_key(b));
            if !all_held {
                continue;
            }
            // All press times (including just_pressed) must be within within_ms
            let threshold = Duration::from_millis(pattern.within_ms);
            // just_pressed was just inserted so its time is ~now
            let in_window = pattern.buttons.iter()
                .filter(|&&b| b != just_pressed)
                .all(|b| {
                    if let Some(&t) = self.held.get(b) {
                        now.duration_since(t) <= threshold
                    } else {
                        false
                    }
                });
            if in_window {
                self.chord_fired.insert(pattern.name.clone());
                out.push(Action::ChordFired { name: pattern.name.clone() });
            }
        }
    }

    // -----------------------------------------------------------------------
    // Generic hold check — called on every button press
    // -----------------------------------------------------------------------

    fn check_holds(&mut self, just_pressed: Button) {
        for pattern in &self.hold_patterns {
            if !pattern.buttons.contains(&just_pressed) {
                continue;
            }
            let all_held = pattern.buttons.iter().all(|b| self.held.contains_key(b));
            if all_held {
                let deadline = Instant::now() + Duration::from_millis(pattern.hold_ms);
                self.hold_deadlines.insert(pattern.name.clone(), deadline);
            }
        }
    }

    fn cancel_holds_for(&mut self, released: Button) {
        self.hold_patterns.iter()
            .filter(|p| p.buttons.contains(&released))
            .map(|p| p.name.clone())
            .collect::<Vec<_>>()
            .into_iter()
            .for_each(|name| { self.hold_deadlines.remove(&name); });
    }

    // -----------------------------------------------------------------------
    // Main process
    // -----------------------------------------------------------------------

    pub fn process(&mut self, ev: &InputEventRaw) -> Vec<Action> {
        let mut out = Vec::new();

        match ev.etype {
            EV_KEY => {
                if let Some(btn) = btn_code(ev.code) {
                    if ev.value == 1 {
                        let was_chord = self.was_system_chord();
                        self.held.insert(btn, Instant::now());

                        // D-pad repeat state
                        match btn {
                            Button::DpadUp    => { self.dpad_repeat.insert(DpadDir::Up,    DpadRepeatState { first_press: Instant::now(), next_emit: None }); }
                            Button::DpadDown  => { self.dpad_repeat.insert(DpadDir::Down,  DpadRepeatState { first_press: Instant::now(), next_emit: None }); }
                            Button::DpadLeft  => { self.dpad_repeat.insert(DpadDir::Left,  DpadRepeatState { first_press: Instant::now(), next_emit: None }); }
                            Button::DpadRight => { self.dpad_repeat.insert(DpadDir::Right, DpadRepeatState { first_press: Instant::now(), next_emit: None }); }
                            _ => {}
                        }

                        // Legacy L2/R2 chord signals
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
                            _ => {}
                        }

                        // Generic chord + hold check
                        self.check_chords(btn, &mut out);
                        self.check_holds(btn);

                        out.push(Action::ButtonPressed(btn));
                    } else if ev.value == 0 {
                        let was_chord = self.was_system_chord();
                        self.held.remove(&btn);
                        self.chord_fired.remove(&canonical_chord_name(
                            self.chord_patterns.iter()
                                .find(|p| p.buttons.contains(&btn))
                                .map(|p| p.buttons.as_slice())
                                .unwrap_or(&[])
                        ));
                        // Remove all fired-chord marks that included this button
                        let to_remove: Vec<String> = self.chord_patterns.iter()
                            .filter(|p| p.buttons.contains(&btn))
                            .map(|p| p.name.clone())
                            .collect();
                        for name in to_remove { self.chord_fired.remove(&name); }

                        // Legacy L2/R2
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

                        self.cancel_holds_for(btn);
                        out.push(Action::ButtonReleased(btn));
                    }
                }
            }

            EV_ABS => {
                match ev.code {
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

                    ABS_RX => {
                        self.right_stick_x = ev.value as f32 / 32767.0;
                        out.push(Action::RightStickMoved { x: self.right_stick_x, y: self.right_stick_y });
                    }
                    ABS_RY => {
                        self.right_stick_y = ev.value as f32 / 32767.0;
                        out.push(Action::RightStickMoved { x: self.right_stick_x, y: self.right_stick_y });
                    }

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

    /// Call periodically to emit D-pad repeat actions and hold-fire events.
    pub fn tick_repeats(&mut self) -> Vec<Action> {
        let now = Instant::now();
        let mut out = Vec::new();

        let repeat_delay = self.repeat_delay;
        let repeat_rate  = self.repeat_rate;

        for (dir, state) in &mut self.dpad_repeat {
            if state.next_emit.is_none() {
                let deadline = state.first_press + repeat_delay;
                if now >= deadline {
                    state.next_emit = Some(deadline);
                }
            }
            if let Some(ref mut next) = state.next_emit {
                if now >= *next {
                    out.push(Action::DpadRepeat(*dir));
                    *next += repeat_rate;
                }
            }
        }

        // Check hold deadlines
        let fired: Vec<String> = self.hold_deadlines.iter()
            .filter(|(_, &deadline)| now >= deadline)
            .map(|(name, _)| name.clone())
            .collect();
        for name in fired {
            self.hold_deadlines.remove(&name);
            out.push(Action::HoldFired { name });
        }

        out
    }
}

// ---------------------------------------------------------------------------
// Builder helpers for loading patterns from keybinds.toml
// ---------------------------------------------------------------------------

/// Parse a button name string (as used in keybinds.toml) to a `Button`.
// Retained for the pending keybind pattern loader.
#[allow(dead_code)]
pub fn button_from_name(name: &str) -> Option<Button> {
    match name {
        "button_a"     => Some(Button::A),
        "button_b"     => Some(Button::B),
        "button_x"     => Some(Button::X),
        "button_y"     => Some(Button::Y),
        "l1"           => Some(Button::L1),
        "r1"           => Some(Button::R1),
        "l2"           => Some(Button::L2),
        "r2"           => Some(Button::R2),
        "button_start" => Some(Button::Start),
        "button_select"=> Some(Button::Select),
        "dpad_up"      => Some(Button::DpadUp),
        "dpad_down"    => Some(Button::DpadDown),
        "dpad_left"    => Some(Button::DpadLeft),
        "dpad_right"   => Some(Button::DpadRight),
        _              => None,
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

    const BTN_A:  u16 = 0x130;
    const BTN_L1: u16 = 0x136;
    const BTN_R1: u16 = 0x137;
    const BTN_L2: u16 = 0x138;
    const BTN_R2: u16 = 0x139;

    #[test]
    fn button_press_and_release() {
        let mut cd = ChordDetector::new();
        let actions = cd.process(&key_ev(BTN_A, 1));
        assert!(actions.contains(&Action::ButtonPressed(Button::A)));
        let actions = cd.process(&key_ev(BTN_A, 0));
        assert!(actions.contains(&Action::ButtonReleased(Button::A)));
    }

    #[test]
    fn unknown_button_produces_no_actions() {
        let mut cd = ChordDetector::new();
        assert!(cd.process(&key_ev(0xFFFF, 1)).is_empty());
    }

    #[test]
    fn dpad_hat_x_decodes_to_left_right() {
        let mut cd = ChordDetector::new();
        let a = cd.process(&abs_ev(ABS_HAT0X, -1));
        assert!(a.contains(&Action::ButtonPressed(Button::DpadLeft)));
        let a = cd.process(&abs_ev(ABS_HAT0X, 0));
        assert!(a.contains(&Action::ButtonReleased(Button::DpadLeft)));
        let a = cd.process(&abs_ev(ABS_HAT0X, 1));
        assert!(a.contains(&Action::ButtonPressed(Button::DpadRight)));
    }

    #[test]
    fn l2_r2_digital_chord_enter_and_exit() {
        let mut cd = ChordDetector::new();
        let a = cd.process(&key_ev(BTN_L2, 1));
        assert!(a.contains(&Action::L2HeldChange(true)));
        assert!(!a.contains(&Action::SystemChordEntered));
        let a = cd.process(&key_ev(BTN_R2, 1));
        assert!(a.contains(&Action::SystemChordEntered));
        let a = cd.process(&key_ev(BTN_L2, 0));
        assert!(a.contains(&Action::SystemChordExited));
        let a = cd.process(&key_ev(BTN_R2, 0));
        assert!(!a.contains(&Action::SystemChordExited));
    }

    #[test]
    fn l2_r2_chord_fires_chord_action() {
        let mut cd = ChordDetector::new();
        cd.process(&key_ev(BTN_L2, 1));
        let actions = cd.process(&key_ev(BTN_R2, 1));
        assert!(actions.iter().any(|a| matches!(a, Action::ChordFired { name } if name == "l2+r2")));
    }

    #[test]
    fn custom_chord_fires_on_simultaneous_press() {
        let mut cd = ChordDetector::new().with_patterns(
            vec![ChordPattern {
                buttons:   vec![Button::L1, Button::X],
                within_ms: 80,
                name:      "l1+button_x".into(),
            }],
            vec![],
        );
        cd.process(&key_ev(BTN_L1, 1));
        // X button code is 0x133
        let actions = cd.process(&key_ev(0x133, 1));
        assert!(actions.iter().any(|a| matches!(a, Action::ChordFired { name } if name == "l1+button_x")),
            "expected ChordFired l1+button_x in {:?}", actions);
    }

    #[test]
    fn hold_fires_after_deadline_in_tick() {
        let mut cd = ChordDetector::new().with_patterns(
            vec![],
            vec![HoldPattern {
                buttons: vec![Button::L1, Button::R1],
                hold_ms: 0,  // fire immediately for test
                name:    "l1+r1".into(),
            }],
        );
        cd.process(&key_ev(BTN_L1, 1));
        cd.process(&key_ev(BTN_R1, 1));
        let ticks = cd.tick_repeats();
        assert!(ticks.iter().any(|a| matches!(a, Action::HoldFired { name } if name == "l1+r1")));
    }

    #[test]
    fn hold_cancelled_on_release() {
        let mut cd = ChordDetector::new().with_patterns(
            vec![],
            vec![HoldPattern {
                buttons: vec![Button::L1, Button::R1],
                hold_ms: 9999,
                name:    "l1+r1".into(),
            }],
        );
        cd.process(&key_ev(BTN_L1, 1));
        cd.process(&key_ev(BTN_R1, 1));
        cd.process(&key_ev(BTN_L1, 0)); // cancel by releasing
        let ticks = cd.tick_repeats();
        assert!(!ticks.iter().any(|a| matches!(a, Action::HoldFired { .. })));
    }

    #[test]
    fn analog_l2_crosses_threshold_emits_held_change() {
        let mut cd = ChordDetector::new();
        assert!(cd.process(&abs_ev(ABS_Z, 50)).is_empty());
        let a = cd.process(&abs_ev(ABS_Z, 76));
        assert!(a.contains(&Action::L2HeldChange(true)));
        let a = cd.process(&abs_ev(ABS_Z, 10));
        assert!(a.contains(&Action::L2HeldChange(false)));
    }

    #[test]
    fn right_stick_retains_other_axis() {
        let mut cd = ChordDetector::new();
        let a = cd.process(&abs_ev(ABS_RX, 32767));
        assert!(a.iter().any(|a| matches!(a, Action::RightStickMoved { x, y } if *x > 0.9 && *y == 0.0)));
        let a = cd.process(&abs_ev(ABS_RY, 16384));
        assert!(a.iter().any(|a| matches!(a, Action::RightStickMoved { x, y } if *x > 0.9 && *y > 0.4)));
    }

    #[test]
    fn tick_repeats_empty_when_no_dpad_held() {
        let mut cd = ChordDetector::new();
        assert!(cd.tick_repeats().is_empty());
    }

    #[test]
    fn tick_repeats_does_not_fire_before_delay() {
        let mut cd = ChordDetector::new();
        cd.repeat_delay = Duration::from_secs(9999);
        cd.process(&abs_ev(ABS_HAT0Y, -1));
        assert!(cd.tick_repeats().is_empty());
    }

    #[test]
    fn tick_repeats_fires_after_delay_and_stops_when_released() {
        let mut cd = ChordDetector::new();
        cd.repeat_delay = Duration::ZERO;
        cd.repeat_rate  = Duration::ZERO;
        cd.process(&abs_ev(ABS_HAT0Y, -1));
        assert!(cd.tick_repeats().contains(&Action::DpadRepeat(DpadDir::Up)));
        cd.process(&abs_ev(ABS_HAT0Y, 0));
        assert!(cd.tick_repeats().is_empty());
    }
}
