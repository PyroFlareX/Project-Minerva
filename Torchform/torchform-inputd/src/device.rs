//! Physical controller discovery and reading. Detects gamepads generically by
//! evdev capability (not VID/PID), grabs them so their raw events do not leak to
//! apps, and translates raw codes into the logical vocabulary using a standard
//! table plus optional per-device remaps. One reader thread per device feeds the
//! engine over a channel.

use crate::button::{LogicalAxis, LogicalButton};
use crate::config::{Config, DeviceProfile};
use anyhow::Result;
use evdev::{AbsoluteAxisType, Device, InputEventKind, Key};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::mpsc::Sender;
use std::time::Instant;

use crate::virtpad::VIRTPAD_NAME;

/// A message from a device reader thread to the engine loop.
pub enum InMsg {
    Button { btn: LogicalButton, pressed: bool, at: Instant },
    Axis { axis: LogicalAxis, value: i32 },
}

/// True if a device looks like a gamepad: reports the modern South face button
/// (BTN_SOUTH, == legacy BTN_A code) or a legacy joystick trigger (covers older
/// pads like the DragonRise). Keyboards/mice/touchpads won't.
fn is_gamepad(dev: &Device) -> bool {
    dev.supported_keys().map_or(false, |keys| {
        keys.contains(Key::BTN_SOUTH) || keys.contains(Key::BTN_TRIGGER)
    })
}

/// Resolve a device's remap profile from config (by name substring or vid:pid).
fn profile_for<'a>(dev: &Device, cfg: &'a Config) -> Option<&'a DeviceProfile> {
    let name = dev.name().unwrap_or("").to_ascii_lowercase();
    let id = dev.input_id();
    let vidpid = format!("{:04x}:{:04x}", id.vendor(), id.product());
    cfg.devices.iter().find(|p| {
        let spec = p.match_spec.to_ascii_lowercase();
        name.contains(&spec) || vidpid == spec
    })
}

/// Standard raw evdev key → logical button. Oddball pads override via remap.
fn standard_button(k: Key) -> Option<LogicalButton> {
    Some(match k {
        Key::BTN_SOUTH => LogicalButton::South, // BTN_A aliases the same code
        Key::BTN_EAST => LogicalButton::East,   // BTN_B
        Key::BTN_NORTH => LogicalButton::North, // BTN_Y / BTN_X depending on pad
        Key::BTN_WEST => LogicalButton::West,
        Key::BTN_TL => LogicalButton::L1,
        Key::BTN_TR => LogicalButton::R1,
        Key::BTN_TL2 => LogicalButton::L2,
        Key::BTN_TR2 => LogicalButton::R2,
        Key::BTN_SELECT => LogicalButton::Select,
        Key::BTN_START => LogicalButton::Start,
        Key::BTN_MODE => LogicalButton::Mode,
        Key::BTN_THUMBL => LogicalButton::ThumbL,
        Key::BTN_THUMBR => LogicalButton::ThumbR,
        Key::BTN_DPAD_UP => LogicalButton::DpadUp,
        Key::BTN_DPAD_DOWN => LogicalButton::DpadDown,
        Key::BTN_DPAD_LEFT => LogicalButton::DpadLeft,
        Key::BTN_DPAD_RIGHT => LogicalButton::DpadRight,
        _ => return None,
    })
}

/// Look up an evdev Key by its symbolic name (for parsing remap config keys).
/// Covers the button names a controller might expose; unknown names warn.
fn key_from_name(name: &str) -> Option<Key> {
    let n = name.to_ascii_uppercase();
    Some(match n.as_str() {
        "BTN_SOUTH" | "BTN_A" => Key::BTN_SOUTH,
        "BTN_EAST" | "BTN_B" => Key::BTN_EAST,
        "BTN_NORTH" | "BTN_Y" => Key::BTN_NORTH,
        "BTN_WEST" | "BTN_X" => Key::BTN_WEST,
        "BTN_C" => Key::BTN_C,
        "BTN_Z" => Key::BTN_Z,
        "BTN_TL" => Key::BTN_TL,
        "BTN_TR" => Key::BTN_TR,
        "BTN_TL2" => Key::BTN_TL2,
        "BTN_TR2" => Key::BTN_TR2,
        "BTN_SELECT" => Key::BTN_SELECT,
        "BTN_START" => Key::BTN_START,
        "BTN_MODE" => Key::BTN_MODE,
        "BTN_THUMBL" => Key::BTN_THUMBL,
        "BTN_THUMBR" => Key::BTN_THUMBR,
        "BTN_THUMB" => Key::BTN_THUMB,
        "BTN_THUMB2" => Key::BTN_THUMB2,
        "BTN_TRIGGER" => Key::BTN_TRIGGER,
        "BTN_TOP" => Key::BTN_TOP,
        "BTN_TOP2" => Key::BTN_TOP2,
        "BTN_PINKIE" => Key::BTN_PINKIE,
        "BTN_BASE" => Key::BTN_BASE,
        "BTN_BASE2" => Key::BTN_BASE2,
        "BTN_BASE3" => Key::BTN_BASE3,
        "BTN_BASE4" => Key::BTN_BASE4,
        "BTN_BASE5" => Key::BTN_BASE5,
        "BTN_BASE6" => Key::BTN_BASE6,
        "BTN_DPAD_UP" => Key::BTN_DPAD_UP,
        "BTN_DPAD_DOWN" => Key::BTN_DPAD_DOWN,
        "BTN_DPAD_LEFT" => Key::BTN_DPAD_LEFT,
        "BTN_DPAD_RIGHT" => Key::BTN_DPAD_RIGHT,
        _ => return None,
    })
}

/// A compiled per-device translation table: raw Key → logical button.
struct KeyMap {
    map: HashMap<Key, LogicalButton>,
}

impl KeyMap {
    fn build(profile: Option<&DeviceProfile>) -> KeyMap {
        let mut map = HashMap::new();
        if let Some(p) = profile {
            for (raw_name, logical_name) in &p.remap {
                match (key_from_name(raw_name), logical_name.parse::<LogicalButton>()) {
                    (Some(k), Ok(b)) => {
                        map.insert(k, b);
                    }
                    (None, _) => log::warn!("remap: unknown evdev key '{raw_name}'"),
                    (_, Err(e)) => log::warn!("remap: {e}"),
                }
            }
        }
        KeyMap { map }
    }

    fn translate(&self, k: Key) -> Option<LogicalButton> {
        self.map.get(&k).copied().or_else(|| standard_button(k))
    }
}

/// Enumerate `/dev/input/event*`, returning paths of attached gamepads (skipping
/// our own virtual pad to avoid a feedback loop).
pub fn discover_gamepads() -> Vec<PathBuf> {
    let mut found = Vec::new();
    for (path, dev) in evdev::enumerate() {
        if dev.name() == Some(VIRTPAD_NAME) {
            continue;
        }
        if is_gamepad(&dev) {
            log::info!("controller: {} ({})", dev.name().unwrap_or("?"), path.display());
            found.push(path);
        }
    }
    found
}

/// Open one controller, grab it, and read forever, forwarding logical events to
/// `tx`. Returns when the device disappears or errors (so the caller can respawn
/// on the next hotplug rescan). Hat axes (ABS_HAT0X/Y) become d-pad buttons.
pub fn run_reader(path: &Path, cfg: &Config, tx: Sender<InMsg>) -> Result<()> {
    let mut dev = Device::open(path)?;
    let keymap = KeyMap::build(profile_for(&dev, cfg));
    // Grab so the raw device's events don't reach apps — only our virtual pad does.
    if let Err(e) = dev.grab() {
        log::warn!("could not grab {}: {e} (raw events may leak)", path.display());
    }

    // Track hat state to synthesize d-pad press/release edges.
    let mut hat_x: i32 = 0;
    let mut hat_y: i32 = 0;

    loop {
        for ev in dev.fetch_events()? {
            let now = Instant::now();
            match ev.kind() {
                InputEventKind::Key(k) => {
                    if let Some(btn) = keymap.translate(k) {
                        // evdev value 2 is autorepeat — ignore, we only want edges.
                        if ev.value() == 2 {
                            continue;
                        }
                        let _ = tx.send(InMsg::Button { btn, pressed: ev.value() == 1, at: now });
                    }
                }
                InputEventKind::AbsAxis(axis) => {
                    handle_abs(axis, ev.value(), &mut hat_x, &mut hat_y, now, &tx);
                }
                _ => {}
            }
        }
    }
}

/// Map an absolute-axis event: hats → d-pad button edges, sticks/triggers → axes.
fn handle_abs(
    axis: AbsoluteAxisType,
    value: i32,
    hat_x: &mut i32,
    hat_y: &mut i32,
    now: Instant,
    tx: &Sender<InMsg>,
) {
    let send = |b: LogicalButton, pressed: bool| {
        let _ = tx.send(InMsg::Button { btn: b, pressed, at: now });
    };
    match axis {
        AbsoluteAxisType::ABS_HAT0X => {
            // Release the previous direction, press the new one.
            if *hat_x < 0 { send(LogicalButton::DpadLeft, false); }
            if *hat_x > 0 { send(LogicalButton::DpadRight, false); }
            if value < 0 { send(LogicalButton::DpadLeft, true); }
            if value > 0 { send(LogicalButton::DpadRight, true); }
            *hat_x = value;
        }
        AbsoluteAxisType::ABS_HAT0Y => {
            if *hat_y < 0 { send(LogicalButton::DpadUp, false); }
            if *hat_y > 0 { send(LogicalButton::DpadDown, false); }
            if value < 0 { send(LogicalButton::DpadUp, true); }
            if value > 0 { send(LogicalButton::DpadDown, true); }
            *hat_y = value;
        }
        AbsoluteAxisType::ABS_X => { let _ = tx.send(InMsg::Axis { axis: LogicalAxis::LeftX, value }); }
        AbsoluteAxisType::ABS_Y => { let _ = tx.send(InMsg::Axis { axis: LogicalAxis::LeftY, value }); }
        AbsoluteAxisType::ABS_RX => { let _ = tx.send(InMsg::Axis { axis: LogicalAxis::RightX, value }); }
        AbsoluteAxisType::ABS_RY => { let _ = tx.send(InMsg::Axis { axis: LogicalAxis::RightY, value }); }
        AbsoluteAxisType::ABS_Z => { let _ = tx.send(InMsg::Axis { axis: LogicalAxis::L2Analog, value }); }
        AbsoluteAxisType::ABS_RZ => { let _ = tx.send(InMsg::Axis { axis: LogicalAxis::R2Analog, value }); }
        _ => {}
    }
}
