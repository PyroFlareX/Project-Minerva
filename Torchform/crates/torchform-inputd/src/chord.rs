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

use anyhow::{Context, Result};
use tracing::{debug, info};

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

const EVENT_SIZE: usize = std::mem::size_of::<InputEventRaw>();

// EV_ types
const EV_KEY: u16 = 0x01;
const EV_ABS: u16 = 0x03;
const EV_SYN: u16 = 0x00;

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

pub struct ChordDetector {
    held:          HashMap<Button, Instant>,
    l2_analog:     f32,
    r2_analog:     f32,
    /// Threshold above which analog L2/R2 count as "held"
    analog_thresh: f32,
    /// Repeat timings for D-pad
    dpad_repeat:   HashMap<DpadDir, Instant>,
    repeat_delay:  Duration,
    repeat_rate:   Duration,
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
                            Button::DpadUp    => { self.dpad_repeat.insert(DpadDir::Up,    Instant::now()); }
                            Button::DpadDown  => { self.dpad_repeat.insert(DpadDir::Down,  Instant::now()); }
                            Button::DpadLeft  => { self.dpad_repeat.insert(DpadDir::Left,  Instant::now()); }
                            Button::DpadRight => { self.dpad_repeat.insert(DpadDir::Right, Instant::now()); }
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
                            self.dpad_repeat.insert(DpadDir::Left, Instant::now());
                            out.push(Action::ButtonPressed(Button::DpadLeft));
                        }
                        1 => {
                            self.held.insert(Button::DpadRight, Instant::now());
                            self.dpad_repeat.insert(DpadDir::Right, Instant::now());
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
                            self.dpad_repeat.insert(DpadDir::Up, Instant::now());
                            out.push(Action::ButtonPressed(Button::DpadUp));
                        }
                        1 => {
                            self.held.insert(Button::DpadDown, Instant::now());
                            self.dpad_repeat.insert(DpadDir::Down, Instant::now());
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

                    // Right stick (TLV493D via MCU)
                    ABS_RX | ABS_RY => {
                        let norm = ev.value as f32 / 32767.0;
                        if ev.code == ABS_RX {
                            out.push(Action::RightStickMoved { x: norm, y: 0.0 });
                        } else {
                            out.push(Action::RightStickMoved { x: 0.0, y: norm });
                        }
                    }

                    // L2/R2 analog triggers
                    ABS_Z => {
                        let prev = self.l2_held();
                        self.l2_analog = ev.value as f32 / 255.0;
                        if self.l2_held() != prev {
                            out.push(Action::L2HeldChange(self.l2_held()));
                        }
                    }
                    ABS_RZ => {
                        let prev = self.r2_held();
                        self.r2_analog = ev.value as f32 / 255.0;
                        if self.r2_held() != prev {
                            out.push(Action::R2HeldChange(self.r2_held()));
                        }
                    }

                    _ => {}
                }
            }

            _ => {}
        }

        out
    }

    /// Call periodically to emit D-pad repeat actions.
    pub fn tick_repeats(&mut self) -> Vec<Action> {
        let now = Instant::now();
        let mut out = Vec::new();

        for (dir, first_press) in &mut self.dpad_repeat {
            let elapsed = now.duration_since(*first_press);
            if elapsed > self.repeat_delay {
                // Emit repeats at repeat_rate
                let extra = elapsed - self.repeat_delay;
                let reps = (extra.as_millis() / self.repeat_rate.as_millis()) as usize;
                // Only emit once per tick (caller drives the rate)
                if reps > 0 {
                    out.push(Action::DpadRepeat(*dir));
                }
            }
        }

        out
    }
}
