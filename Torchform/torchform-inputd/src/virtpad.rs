//! The uinput virtual gamepad. One normalized output device that both real apps
//! /games and the Quickshell.Gamepad plugin consume. Logical buttons map to the
//! standard evdev gamepad layout; chord/multiclick actions are pulsed on spare
//! BTN_TRIGGER_HAPPY* slots, with a JSON manifest mapping action name → slot so
//! the plugin can resolve them.

use crate::button::{LogicalAxis, LogicalButton};
use crate::engine::OutEvent;
use anyhow::{Context, Result};
use evdev::{
    uinput::{VirtualDevice, VirtualDeviceBuilder},
    AbsInfo, AbsoluteAxisType, AttributeSet, EventType, InputEvent, Key, UinputAbsSetup,
};
use std::collections::HashMap;
use std::path::PathBuf;

pub const VIRTPAD_NAME: &str = "torchform-virtpad";

/// First spare button used for actions; 16 slots run up from here.
const ACTION_SLOTS: usize = 16;

/// Maps a logical button to its standard evdev output key.
fn out_key(b: LogicalButton) -> Key {
    match b {
        LogicalButton::South => Key::BTN_SOUTH,
        LogicalButton::East => Key::BTN_EAST,
        LogicalButton::West => Key::BTN_WEST,
        LogicalButton::North => Key::BTN_NORTH,
        LogicalButton::L1 => Key::BTN_TL,
        LogicalButton::R1 => Key::BTN_TR,
        LogicalButton::L2 => Key::BTN_TL2,
        LogicalButton::R2 => Key::BTN_TR2,
        LogicalButton::Select => Key::BTN_SELECT,
        LogicalButton::Start => Key::BTN_START,
        LogicalButton::Mode => Key::BTN_MODE,
        LogicalButton::ThumbL => Key::BTN_THUMBL,
        LogicalButton::ThumbR => Key::BTN_THUMBR,
        LogicalButton::DpadUp => Key::BTN_DPAD_UP,
        LogicalButton::DpadDown => Key::BTN_DPAD_DOWN,
        LogicalButton::DpadLeft => Key::BTN_DPAD_LEFT,
        LogicalButton::DpadRight => Key::BTN_DPAD_RIGHT,
    }
}

fn out_axis(a: LogicalAxis) -> AbsoluteAxisType {
    match a {
        LogicalAxis::LeftX => AbsoluteAxisType::ABS_X,
        LogicalAxis::LeftY => AbsoluteAxisType::ABS_Y,
        LogicalAxis::RightX => AbsoluteAxisType::ABS_RX,
        LogicalAxis::RightY => AbsoluteAxisType::ABS_RY,
        LogicalAxis::L2Analog => AbsoluteAxisType::ABS_Z,
        LogicalAxis::R2Analog => AbsoluteAxisType::ABS_RZ,
    }
}

/// The Nth action slot (0-based) as a BTN_TRIGGER_HAPPY* key.
fn action_slot_key(n: usize) -> Key {
    // evdev numbers these consecutively from BTN_TRIGGER_HAPPY1 (0x2c0).
    Key::new(Key::BTN_TRIGGER_HAPPY1.code() + n as u16)
}

pub struct VirtPad {
    dev: VirtualDevice,
    /// action name → slot key
    actions: HashMap<String, Key>,
}

impl VirtPad {
    /// Build the virtual pad advertising the full standard layout plus
    /// `action_names.len()` action slots (capped at 16).
    pub fn new(action_names: &[String]) -> Result<VirtPad> {
        let mut keys = AttributeSet::<Key>::new();
        for b in LogicalButton::ALL {
            keys.insert(out_key(b));
        }

        let mut actions = HashMap::new();
        if action_names.len() > ACTION_SLOTS {
            log::warn!(
                "{} actions configured but only {ACTION_SLOTS} virtual slots; extra ignored",
                action_names.len()
            );
        }
        for (i, name) in action_names.iter().take(ACTION_SLOTS).enumerate() {
            let k = action_slot_key(i);
            keys.insert(k);
            actions.insert(name.clone(), k);
        }

        // Sticks span the signed 16-bit range; triggers 0..255. A flat AbsInfo
        // is fine — the plugin/apps read raw values.
        let stick = AbsInfo::new(0, i16::MIN as i32, i16::MAX as i32, 16, 128, 1);
        let trigger = AbsInfo::new(0, 0, 255, 0, 0, 1);

        let mut builder = VirtualDeviceBuilder::new()
            .context("open /dev/uinput (need write access + 'input' group)")?
            .name(VIRTPAD_NAME)
            .with_keys(&keys)?;
        for a in [LogicalAxis::LeftX, LogicalAxis::LeftY, LogicalAxis::RightX, LogicalAxis::RightY] {
            builder = builder.with_absolute_axis(&UinputAbsSetup::new(out_axis(a), stick))?;
        }
        for a in [LogicalAxis::L2Analog, LogicalAxis::R2Analog] {
            builder = builder.with_absolute_axis(&UinputAbsSetup::new(out_axis(a), trigger))?;
        }
        let dev = builder.build().context("build uinput virtual gamepad")?;

        Ok(VirtPad { dev, actions })
    }

    /// action name → evdev code, for writing the manifest.
    pub fn action_codes(&self) -> HashMap<String, u16> {
        self.actions.iter().map(|(n, k)| (n.clone(), k.code())).collect()
    }

    /// Apply one engine output event to the device (each followed by a SYN).
    pub fn apply(&mut self, ev: &OutEvent) -> Result<()> {
        match ev {
            OutEvent::Button { btn, pressed } => {
                let val = if *pressed { 1 } else { 0 };
                self.emit(&[InputEvent::new(EventType::KEY, out_key(*btn).code(), val)])?;
            }
            OutEvent::Action { name } => {
                // Copy the code out first so the immutable lookup ends before the
                // mutable emit borrow (Key is Copy).
                match self.actions.get(name).map(|k| k.code()) {
                    Some(code) => {
                        // Momentary pulse: press then release.
                        self.emit(&[InputEvent::new(EventType::KEY, code, 1)])?;
                        self.emit(&[InputEvent::new(EventType::KEY, code, 0)])?;
                    }
                    None => log::warn!("action '{name}' has no virtual slot"),
                }
            }
        }
        Ok(())
    }

    /// Pass a raw analog axis value straight through to the virtual pad.
    pub fn emit_axis(&mut self, axis: LogicalAxis, value: i32) -> Result<()> {
        self.emit(&[InputEvent::new(EventType::ABSOLUTE, out_axis(axis).0, value)])?;
        Ok(())
    }

    fn emit(&mut self, events: &[InputEvent]) -> Result<()> {
        self.dev.emit(events).context("emit to virtual pad")?;
        Ok(())
    }
}

/// Where the action manifest is written so the plugin can find it.
pub fn manifest_path() -> PathBuf {
    let base = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into());
    PathBuf::from(base).join("torchform").join("inputd-actions.json")
}

/// Write `{ "virtpad": "<name>", "actions": { "switcher": 704, ... } }` so the
/// Quickshell.Gamepad plugin can map action evdev codes back to names.
pub fn write_manifest(action_codes: &HashMap<String, u16>) -> Result<()> {
    let path = manifest_path();
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).ok();
    }
    let json = serde_json::json!({
        "virtpad": VIRTPAD_NAME,
        "actions": action_codes,
    });
    std::fs::write(&path, serde_json::to_vec_pretty(&json)?)
        .with_context(|| format!("write manifest {}", path.display()))?;
    log::info!("wrote action manifest {}", path.display());
    Ok(())
}
