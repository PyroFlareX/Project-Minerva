//! The input engine: turns a stream of logical button edges into virtual-pad
//! output, resolving chords (several buttons together) and multiclick aliases
//! (N presses of one button). Pure logic with an injected millisecond clock so
//! it is fully deterministic under test — no evdev, no real time.
//!
//! ## Model & precedence
//! Each button is classified once at construction into exactly one mode:
//!   * **Chord** — appears in at least one `[[chord]]`. Presses are buffered for
//!     up to `chord_window_ms`; if the held set completes a chord rule the action
//!     fires and the members' presses/releases are swallowed, otherwise the
//!     buffered presses flush through as normal.
//!   * **Multiclick** — appears in a `[[multiclick]]` (and no chord). Presses are
//!     counted within `multiclick_window_ms`; the sequence resolves only when the
//!     window expires (so 2 vs 3 clicks disambiguate cleanly). A configured count
//!     emits its action; anything else flushes as that many discrete press+release
//!     pulses. Such a button is therefore click-only (cannot be held) and carries
//!     the window's latency.
//!   * **Plain** — passes straight through with no latency, preserving true
//!     press/hold/release for games and the shell.
//!
//! Auto-repeat for menu navigation is intentionally **not** done here: the
//! virtual pad must reflect real physical state for games. The shell implements
//! its own nav repeat in QML off the held state the Quickshell.Gamepad plugin
//! exposes. (`repeat_*_ms` in the config is read by the shell, not the engine.)

use crate::button::LogicalButton;
use crate::config::Config;
use std::collections::{HashMap, HashSet};

pub type TimeMs = u64;

/// What the engine emits toward the virtual pad / action manifest.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OutEvent {
    /// A normal button edge to mirror on the virtual pad.
    Button { btn: LogicalButton, pressed: bool },
    /// A momentary named action (chord or multiclick alias). The driver pulses
    /// the mapped virtual action slot press-then-release.
    Action { name: String },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Mode {
    Plain,
    Chord,
    Multiclick,
}

struct ChordRule {
    members: HashSet<LogicalButton>,
    action: String,
}

pub struct Engine {
    mode: HashMap<LogicalButton, Mode>,
    chords: Vec<ChordRule>, // longest first, so the most specific chord wins
    /// button -> sorted set of configured click counts -> action
    multiclick: HashMap<LogicalButton, HashMap<u32, String>>,
    chord_window: TimeMs,
    multiclick_window: TimeMs,

    // ── chord runtime ──
    /// Chord-mode buttons currently held but not yet resolved, in press order.
    chord_buffer: Vec<LogicalButton>,
    chord_deadline: Option<TimeMs>,
    /// Buttons consumed by a fired chord; their release is swallowed.
    consumed: HashSet<LogicalButton>,

    // ── multiclick runtime ──
    click_button: Option<LogicalButton>,
    click_count: u32,
    click_deadline: Option<TimeMs>,
}

impl Engine {
    pub fn new(cfg: &Config) -> Engine {
        let mut mode: HashMap<LogicalButton, Mode> = HashMap::new();
        let mut chords = Vec::new();

        for rule in &cfg.chords {
            let mut members = HashSet::new();
            for name in &rule.buttons {
                match name.parse::<LogicalButton>() {
                    Ok(b) => {
                        members.insert(b);
                        mode.insert(b, Mode::Chord);
                    }
                    Err(e) => log::warn!("chord '{}': {e}", rule.action),
                }
            }
            if members.len() >= 2 {
                chords.push(ChordRule { members, action: rule.action.clone() });
            } else {
                log::warn!("chord '{}' ignored: needs >= 2 valid buttons", rule.action);
            }
        }
        // Most specific (largest) chord checked first.
        chords.sort_by(|a, b| b.members.len().cmp(&a.members.len()));

        let mut multiclick: HashMap<LogicalButton, HashMap<u32, String>> = HashMap::new();
        for rule in &cfg.multiclicks {
            match rule.button.parse::<LogicalButton>() {
                Ok(b) => {
                    // Chord classification wins over multiclick for a shared button.
                    if mode.get(&b) != Some(&Mode::Chord) {
                        mode.insert(b, Mode::Multiclick);
                        multiclick.entry(b).or_default().insert(rule.count, rule.action.clone());
                    } else {
                        log::warn!(
                            "multiclick on '{}' ignored: button already used in a chord",
                            rule.button
                        );
                    }
                }
                Err(e) => log::warn!("multiclick '{}': {e}", rule.action),
            }
        }

        Engine {
            mode,
            chords,
            multiclick,
            chord_window: cfg.timing.chord_window_ms,
            multiclick_window: cfg.timing.multiclick_window_ms,
            chord_buffer: Vec::new(),
            chord_deadline: None,
            consumed: HashSet::new(),
            click_button: None,
            click_count: 0,
            click_deadline: None,
        }
    }

    fn mode_of(&self, b: LogicalButton) -> Mode {
        *self.mode.get(&b).unwrap_or(&Mode::Plain)
    }

    /// Handle one button edge at time `now`. Returns events to emit, in order.
    pub fn handle(&mut self, btn: LogicalButton, pressed: bool, now: TimeMs) -> Vec<OutEvent> {
        match self.mode_of(btn) {
            Mode::Plain => self.handle_plain(btn, pressed),
            Mode::Chord => self.handle_chord(btn, pressed, now),
            Mode::Multiclick => self.handle_multiclick(btn, pressed, now),
        }
    }

    fn handle_plain(&self, btn: LogicalButton, pressed: bool) -> Vec<OutEvent> {
        vec![OutEvent::Button { btn, pressed }]
    }

    fn handle_chord(&mut self, btn: LogicalButton, pressed: bool, now: TimeMs) -> Vec<OutEvent> {
        if pressed {
            self.chord_buffer.push(btn);
            self.chord_deadline = Some(now + self.chord_window);
            // Did this press complete any chord (most specific first)?
            let held: HashSet<LogicalButton> = self.chord_buffer.iter().copied().collect();
            if let Some(idx) = self.chords.iter().position(|r| r.members.is_subset(&held)) {
                let action = self.chords[idx].action.clone();
                // Members are consumed: drop from buffer, swallow their releases.
                let members = self.chords[idx].members.clone();
                self.chord_buffer.retain(|b| !members.contains(b));
                for m in &members {
                    self.consumed.insert(*m);
                }
                if self.chord_buffer.is_empty() {
                    self.chord_deadline = None;
                }
                return vec![OutEvent::Action { name: action }];
            }
            Vec::new() // buffered, awaiting more or the deadline
        } else {
            // Release of a chord button.
            if self.consumed.remove(&btn) {
                return Vec::new(); // part of a fired chord — swallow
            }
            // Released before resolving: flush the buffer as real presses, then
            // release this one too.
            let mut out = self.flush_chord_buffer();
            out.push(OutEvent::Button { btn, pressed: false });
            out
        }
    }

    /// Emit buffered chord-button presses as real passthrough presses.
    fn flush_chord_buffer(&mut self) -> Vec<OutEvent> {
        let out: Vec<OutEvent> = self
            .chord_buffer
            .drain(..)
            .map(|btn| OutEvent::Button { btn, pressed: true })
            .collect();
        self.chord_deadline = None;
        out
    }

    fn handle_multiclick(&mut self, btn: LogicalButton, pressed: bool, now: TimeMs) -> Vec<OutEvent> {
        if !pressed {
            return Vec::new(); // releases are synthesized on resolve
        }
        let mut out = Vec::new();
        if self.click_button == Some(btn) {
            self.click_count += 1;
        } else {
            // A different multiclick button interrupts — resolve the old one.
            out.extend(self.resolve_multiclick());
            self.click_button = Some(btn);
            self.click_count = 1;
        }
        self.click_deadline = Some(now + self.multiclick_window);
        out
    }

    /// Resolve the pending multiclick sequence (on window expiry or interruption).
    fn resolve_multiclick(&mut self) -> Vec<OutEvent> {
        let Some(btn) = self.click_button.take() else {
            return Vec::new();
        };
        let count = self.click_count;
        self.click_count = 0;
        self.click_deadline = None;

        if let Some(action) = self.multiclick.get(&btn).and_then(|m| m.get(&count)) {
            vec![OutEvent::Action { name: action.clone() }]
        } else {
            // No alias for this count — replay as discrete clicks.
            let mut out = Vec::with_capacity(count as usize * 2);
            for _ in 0..count {
                out.push(OutEvent::Button { btn, pressed: true });
                out.push(OutEvent::Button { btn, pressed: false });
            }
            out
        }
    }

    /// The soonest pending deadline, for the main loop's blocking-recv timeout.
    pub fn next_deadline(&self) -> Option<TimeMs> {
        match (self.chord_deadline, self.click_deadline) {
            (Some(a), Some(b)) => Some(a.min(b)),
            (a, b) => a.or(b),
        }
    }

    /// Fire any deadlines that have elapsed by `now`.
    pub fn poll(&mut self, now: TimeMs) -> Vec<OutEvent> {
        let mut out = Vec::new();
        if let Some(d) = self.chord_deadline {
            if now >= d {
                out.extend(self.flush_chord_buffer());
            }
        }
        if let Some(d) = self.click_deadline {
            if now >= d {
                out.extend(self.resolve_multiclick());
            }
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;
    use LogicalButton::*;

    fn engine(toml: &str) -> Engine {
        Engine::new(&Config::from_toml(toml).unwrap())
    }

    #[test]
    fn plain_button_passes_through_instantly() {
        let mut e = engine("");
        assert_eq!(e.handle(South, true, 0), vec![OutEvent::Button { btn: South, pressed: true }]);
        assert_eq!(e.handle(South, false, 10), vec![OutEvent::Button { btn: South, pressed: false }]);
        assert_eq!(e.next_deadline(), None);
    }

    #[test]
    fn chord_fires_when_both_pressed_in_window() {
        let mut e = engine(r#"
            [timing]
            chord_window_ms = 40
            [[chord]]
            buttons = ["l1","r1"]
            action = "switcher"
        "#);
        assert_eq!(e.handle(L1, true, 0), vec![]); // buffered
        let out = e.handle(R1, true, 20);
        assert_eq!(out, vec![OutEvent::Action { name: "switcher".into() }]);
        // Releases of the consumed members are swallowed.
        assert_eq!(e.handle(L1, false, 100), vec![]);
        assert_eq!(e.handle(R1, false, 110), vec![]);
    }

    #[test]
    fn incomplete_chord_flushes_individual_presses_on_deadline() {
        let mut e = engine(r#"
            [timing]
            chord_window_ms = 40
            [[chord]]
            buttons = ["l1","r1"]
            action = "switcher"
        "#);
        assert_eq!(e.handle(L1, true, 0), vec![]);
        assert_eq!(e.next_deadline(), Some(40));
        // Deadline passes with only L1 held → L1 passes through as a real press.
        assert_eq!(e.poll(40), vec![OutEvent::Button { btn: L1, pressed: true }]);
        assert_eq!(e.handle(L1, false, 50), vec![OutEvent::Button { btn: L1, pressed: false }]);
    }

    #[test]
    fn double_click_emits_alias_after_window() {
        let mut e = engine(r#"
            [timing]
            multiclick_window_ms = 200
            [[multiclick]]
            button = "south"
            count = 2
            action = "confirm_double"
        "#);
        assert_eq!(e.handle(South, true, 0), vec![]);
        assert_eq!(e.handle(South, false, 30), vec![]);
        assert_eq!(e.handle(South, true, 80), vec![]);
        assert_eq!(e.handle(South, false, 110), vec![]);
        // Window expires → the double-click alias fires once.
        assert_eq!(e.poll(280), vec![OutEvent::Action { name: "confirm_double".into() }]);
    }

    #[test]
    fn single_click_replays_as_one_press_release_after_window() {
        let mut e = engine(r#"
            [timing]
            multiclick_window_ms = 200
            [[multiclick]]
            button = "south"
            count = 2
            action = "confirm_double"
        "#);
        e.handle(South, true, 0);
        e.handle(South, false, 30);
        assert_eq!(
            e.poll(200),
            vec![
                OutEvent::Button { btn: South, pressed: true },
                OutEvent::Button { btn: South, pressed: false },
            ]
        );
    }

    #[test]
    fn triple_disambiguates_from_double() {
        let mut e = engine(r#"
            [timing]
            multiclick_window_ms = 200
            [[multiclick]]
            button = "south"
            count = 2
            action = "dbl"
            [[multiclick]]
            button = "south"
            count = 3
            action = "trpl"
        "#);
        for t in [0u64, 60, 120] {
            e.handle(South, true, t);
            e.handle(South, false, t + 20);
        }
        assert_eq!(e.poll(330), vec![OutEvent::Action { name: "trpl".into() }]);
    }

    #[test]
    fn chord_classification_wins_over_multiclick_for_shared_button() {
        let e = engine(r#"
            [[chord]]
            buttons = ["south","east"]
            action = "c"
            [[multiclick]]
            button = "south"
            count = 2
            action = "m"
        "#);
        assert_eq!(e.mode_of(South), super::Mode::Chord);
    }
}
