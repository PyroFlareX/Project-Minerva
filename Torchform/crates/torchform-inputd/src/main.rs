// =============================================================================
// torchform-inputd — Torchform input daemon
//
// Runs as a background service. Responsibilities:
//
//   1. Read the Cirque GlidePoint trackpad via SPI (or kernel evdev)
//   2. Read the input MCU's USB HID gamepad events
//   3. Synthesise virtual joystick axes (Cirque → ABS_X/Y on uinput device)
//   4. Detect chords (L2+R2 → system radial, etc.)
//   5. Publish high-level input actions to torchform-shell via Unix socket
//
// The compositor (torchform-compositor) reads the raw uinput device for
// pointer/cursor motion. The shell (torchform-shell) receives the decoded
// actions for overlay control.
// =============================================================================

mod chord;
mod cirque;
mod uinput;

use std::{
    fs::File,
    path::Path,
    time::Duration,
};

use anyhow::{Context, Result};
use tracing::{debug, info, warn};

use chord::{Action, Button, DpadDir, ChordDetector};
use cirque::CirqueSpi;
use torchform_actions::{ShellAction, InputMap, RawInput, ChordMap};

// ---------------------------------------------------------------------------
// Config — paths resolved at startup
// ---------------------------------------------------------------------------

struct Config {
    /// SPI device for Cirque trackpad
    cirque_spi:    Option<String>,
    /// evdev device for input MCU (USB HID gamepad)
    gamepad_evdev: Option<String>,
    /// Socket path for publishing actions to the shell
    shell_socket:  String,
}

impl Config {
    fn detect() -> Self {
        // SPI device — /dev/spidev0.0 on CM5 with SPI0 wired to Cirque
        let cirque_spi = if Path::new("/dev/spidev0.0").exists() {
            Some("/dev/spidev0.0".into())
        } else {
            warn!("Cirque SPI device not found — trackpad disabled");
            None
        };

        // Gamepad evdev — scan for a device with BTN_A
        let gamepad_evdev = find_gamepad_evdev();

        Self {
            cirque_spi,
            gamepad_evdev,
            shell_socket: "/run/torchform/inputd.sock".into(),
        }
    }
}

fn find_gamepad_evdev() -> Option<String> {
    // Scan /dev/input/event* for the input MCU's HID gamepad
    for i in 0..32 {
        let path = format!("/dev/input/event{i}");
        if !Path::new(&path).exists() {
            continue;
        }
        if let Ok(_file) = File::open(&path) {
            // Check for BTN_A (0x130) via EVIOCGBIT ioctl
            // Simplified: just return the first event device found
            // In production use the evdev crate for proper capability checks
            info!("Candidate gamepad evdev: {path}");
            return Some(path);
        }
    }
    warn!("No gamepad evdev found — input MCU not connected or not enumerated yet");
    None
}

// ---------------------------------------------------------------------------
// Input loop
// ---------------------------------------------------------------------------

fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("torchform_inputd=debug".parse().unwrap()),
        )
        .init();

    info!("torchform-inputd starting");

    let cfg = Config::detect();

    // Create the virtual gamepad
    let mut vgp = match uinput::VirtualGamepad::new() {
        Ok(v) => {
            info!("uinput virtual gamepad ready");
            Some(v)
        }
        Err(e) => {
            warn!("Could not create uinput device: {e} — axis synthesis disabled");
            None
        }
    };

    // Open Cirque SPI
    let mut cirque = cfg.cirque_spi.as_deref().and_then(|p| {
        CirqueSpi::open(p).map_err(|e| warn!("Cirque SPI open failed: {e}")).ok()
    });

    // Open gamepad evdev
    let mut gamepad = cfg.gamepad_evdev.as_deref().and_then(|p| {
        File::open(p).map_err(|e| warn!("Gamepad evdev open failed: {e}")).ok()
    });

    // Create Unix domain socket for publishing actions
    std::fs::create_dir_all("/run/torchform").ok();
    let listener = std::os::unix::net::UnixListener::bind(&cfg.shell_socket)
        .context("bind shell socket")?;
    listener.set_nonblocking(true)?;
    info!("Listening on {}", cfg.shell_socket);

    let mut chord = ChordDetector::new();
    let input_map = InputMap::load();
    let mut shell_clients: Vec<std::os::unix::net::UnixStream> = Vec::new();

    let mut last_cirque_x = 0.0f32;
    let mut last_cirque_y = 0.0f32;

    info!("Entering input loop");

    loop {
        // -----------------------------------------------------------------
        // Accept new shell connections
        // -----------------------------------------------------------------
        match listener.accept() {
            Ok((stream, _)) => {
                stream.set_nonblocking(true).ok();
                info!("Shell client connected");
                shell_clients.push(stream);
            }
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {}
            Err(e) => warn!("Socket accept error: {e}"),
        }

        // -----------------------------------------------------------------
        // Read Cirque SPI sample
        // -----------------------------------------------------------------
        if let Some(ref mut spi) = cirque {
            match spi.poll_sample() {
                Ok(Some(sample)) if sample.is_touching() => {
                    let nx = sample.norm_x();
                    let ny = sample.norm_y();

                    if (nx - last_cirque_x).abs() > 0.005 || (ny - last_cirque_y).abs() > 0.005 {
                        last_cirque_x = nx;
                        last_cirque_y = ny;

                        if let Some(ref mut vg) = vgp {
                            vg.set_left_pad(nx, ny).ok();
                        }

                        publish_shell_action(
                            &mut shell_clients,
                            ShellAction::PadMoved { x: nx, y: ny },
                        );
                    }
                }
                Ok(Some(_)) | Ok(None) => {}
                Err(e) => debug!("Cirque poll error: {e}"),
            }
        }

        // -----------------------------------------------------------------
        // Read gamepad evdev events
        // -----------------------------------------------------------------
        if let Some(ref mut gp) = gamepad {
            let mut read_buf = [0u8; 24];
            use std::io::Read;

            match gp.read(&mut read_buf) {
                Ok(24) => {
                    // Parse raw input_event
                    let ev_type  = u16::from_ne_bytes([read_buf[16], read_buf[17]]);
                    let ev_code  = u16::from_ne_bytes([read_buf[18], read_buf[19]]);
                    let ev_value = i32::from_ne_bytes([read_buf[20], read_buf[21], read_buf[22], read_buf[23]]);

                    let raw = chord::InputEventRaw {
                        sec:   i64::from_ne_bytes(read_buf[0..8].try_into().unwrap()),
                        usec:  i64::from_ne_bytes(read_buf[8..16].try_into().unwrap()),
                        etype: ev_type,
                        code:  ev_code,
                        value: ev_value,
                    };

                    let actions = chord.process(&raw);

                    for action in actions {
                        debug!("Action: {:?}", action);
                        if let Some(sa) = chord_action_to_shell(&action, &input_map) {
                            publish_shell_action(&mut shell_clients, sa);
                        }
                    }
                }
                Ok(_) => {}
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {}
                Err(e) => debug!("Gamepad read error: {e}"),
            }
        }

        // -----------------------------------------------------------------
        // D-pad repeat
        // -----------------------------------------------------------------
        let repeats = chord.tick_repeats();
        for action in repeats {
            if let Some(sa) = chord_action_to_shell(&action, &input_map) {
                publish_shell_action(&mut shell_clients, sa);
            }
        }

        // -----------------------------------------------------------------
        // Sleep 2 ms — gives ~500 Hz Cirque polling headroom
        // -----------------------------------------------------------------
        std::thread::sleep(Duration::from_millis(2));
    }
}

// ---------------------------------------------------------------------------
// chord::Action → ShellAction translation via InputMap
// ---------------------------------------------------------------------------

fn chord_action_to_shell(action: &Action, map: &InputMap) -> Option<ShellAction> {
    chord_action_to_shell_with_chords(action, map, &ChordMap::default())
}

fn chord_action_to_shell_with_chords(action: &Action, map: &InputMap, chord_map: &ChordMap) -> Option<ShellAction> {
    match action {
        // Button edges — look up in InputMap by raw name
        Action::ButtonPressed(btn) => {
            let raw = button_raw_name(btn, true);
            map.resolve(&RawInput::new(raw))
        }
        Action::ButtonReleased(btn) => {
            let raw = button_raw_name(btn, false);
            map.resolve(&RawInput::new(raw))
        }
        // L2/R2 hold state changes
        Action::L2HeldChange(held) => {
            let key = if *held { "l2_hold_true" } else { "l2_hold_false" };
            map.resolve(&RawInput::new(key))
        }
        Action::R2HeldChange(held) => {
            let key = if *held { "r2_hold_true" } else { "r2_hold_false" };
            map.resolve(&RawInput::new(key))
        }
        // System chord — not directly in InputMap; shell handles via RadialHold
        Action::SystemChordEntered => None,
        Action::SystemChordExited  => None,
        // D-pad repeats — same as ButtonPressed for the direction
        Action::DpadRepeat(dir) => {
            let raw = match dir {
                DpadDir::Up    => "dpad_up",
                DpadDir::Down  => "dpad_down",
                DpadDir::Left  => "dpad_left",
                DpadDir::Right => "dpad_right",
            };
            map.resolve(&RawInput::new(raw))
        }
        // Chord and hold events — resolved via ChordMap
        Action::ChordFired { name } | Action::HoldFired { name } => {
            chord_map.resolve(name)
        }
        // Analog axes — constructed directly (bypass InputMap)
        Action::RightStickMoved { x, y } => Some(ShellAction::StickMoved { x: *x, y: *y }),
        Action::LeftPadMoved { x, y }    => Some(ShellAction::PadMoved   { x: *x, y: *y }),
    }
}

fn button_raw_name(btn: &Button, pressed: bool) -> &'static str {
    // Only pressed-edge inputs are mapped in the default InputMap.
    // Released edges are not mapped for most buttons (except L2/R2 which use
    // separate L2HeldChange / R2HeldChange events above).
    if !pressed { return ""; }
    match btn {
        Button::A           => "button_a",
        Button::B           => "button_b",
        Button::X           => "button_x",
        Button::Y           => "button_y",
        Button::L1          => "l1",
        Button::R1          => "r1",
        Button::L2          => "l2_hold_true",
        Button::R2          => "r2_hold_true",
        Button::Select      => "button_select",
        Button::Start       => "button_start",
        Button::DpadUp      => "dpad_up",
        Button::DpadDown    => "dpad_down",
        Button::DpadLeft    => "dpad_left",
        Button::DpadRight   => "dpad_right",
        Button::LeftPadClick => "pad_click",
    }
}

// ---------------------------------------------------------------------------
// Publish a ShellAction to all connected shell clients as a JSON line
// ---------------------------------------------------------------------------

fn publish_shell_action(clients: &mut Vec<std::os::unix::net::UnixStream>, action: ShellAction) {
    use std::io::Write;

    let msg = match serde_json::to_string(&action) {
        Ok(s) => format!("{s}\n"),
        Err(e) => {
            debug!("Failed to serialize action: {e}");
            return;
        }
    };
    let bytes = msg.as_bytes();

    clients.retain_mut(|client| {
        match client.write_all(bytes) {
            Ok(_) => true,
            Err(_) => {
                debug!("Shell client disconnected");
                false
            }
        }
    });
}
