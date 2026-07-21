//! torchform-inputd — controller → normalized uinput virtual gamepad, with chord
//! and multiclick aliasing from a TOML config.
//!
//! Pipeline:  physical pads ──reader threads──▶ engine (chords/multiclick)
//!                                                  │
//!                                                  ▼
//!                                          uinput virtual pad
//!                                       (apps + Quickshell.Gamepad)
//!
//! Run before the compositor so the virtual pad is enumerated at startup. Needs
//! write access to /dev/uinput and read access to /dev/input/event* (the `input`
//! group covers both).

mod button;
mod config;
mod device;
mod engine;
mod virtpad;

use anyhow::Result;
use config::Config;
use device::InMsg;
use engine::Engine;
use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::mpsc::{self, RecvTimeoutError, Sender};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};
use virtpad::VirtPad;

/// Paths of controllers with a live reader thread. Threads remove their own path
/// on exit so a reconnected controller is respawned on the next rescan.
type OpenSet = Arc<Mutex<HashSet<PathBuf>>>;

const RESCAN_INTERVAL: Duration = Duration::from_secs(2);

fn config_path() -> PathBuf {
    if let Ok(p) = std::env::var("TORCHFORM_INPUT_CONFIG") {
        return PathBuf::from(p);
    }
    let base = std::env::var("XDG_CONFIG_HOME")
        .unwrap_or_else(|_| format!("{}/.config", std::env::var("HOME").unwrap_or_default()));
    PathBuf::from(base).join("torchform").join("input.toml")
}

fn main() -> Result<()> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    let cfg_path = config_path();
    let cfg = Config::load_or_default(&cfg_path)?;
    log::info!("loaded config from {}", cfg_path.display());

    // Build the virtual pad first so its name exists before we enumerate (we skip
    // it during discovery by name) and before the compositor starts.
    let action_names = cfg.action_names();
    let mut pad = VirtPad::new(&action_names)?;
    virtpad::write_manifest(&pad.action_codes())?;
    log::info!("virtual pad '{}' ready ({} action slots)", virtpad::VIRTPAD_NAME, action_names.len());

    let mut engine = Engine::new(&cfg);
    let t0 = Instant::now();
    let ms = |i: Instant| i.duration_since(t0).as_millis() as u64;

    let (tx, rx) = mpsc::channel::<InMsg>();
    let open: OpenSet = Arc::new(Mutex::new(HashSet::new()));
    spawn_readers(&cfg, &tx, &open);
    let mut last_rescan = Instant::now();

    loop {
        // Block until the next input event or the next pending engine deadline,
        // whichever is sooner — but wake at least every RESCAN_INTERVAL to pick
        // up hotplugged controllers.
        let now = Instant::now();
        let mut timeout = RESCAN_INTERVAL.saturating_sub(now.duration_since(last_rescan));
        if let Some(deadline_ms) = engine.next_deadline() {
            let until = deadline_ms.saturating_sub(ms(now));
            timeout = timeout.min(Duration::from_millis(until));
        }

        match rx.recv_timeout(timeout) {
            Ok(msg) => dispatch(&mut engine, &mut pad, msg, &ms)?,
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => {
                log::error!("all readers gone; exiting");
                break;
            }
        }

        // Fire any elapsed chord/multiclick deadlines.
        for ev in engine.poll(ms(Instant::now())) {
            pad.apply(&ev)?;
        }

        // Periodic hotplug rescan (cheap: just diffs the event-node set).
        if last_rescan.elapsed() >= RESCAN_INTERVAL {
            spawn_readers(&cfg, &tx, &open);
            last_rescan = Instant::now();
        }
    }
    Ok(())
}

fn dispatch(
    engine: &mut Engine,
    pad: &mut VirtPad,
    msg: InMsg,
    ms: &impl Fn(Instant) -> u64,
) -> Result<()> {
    match msg {
        InMsg::Button { btn, pressed, at } => {
            for ev in engine.handle(btn, pressed, ms(at)) {
                pad.apply(&ev)?;
            }
        }
        InMsg::Axis { axis, value } => {
            // Sticks/triggers bypass the engine — straight passthrough.
            pad.emit_axis(axis, value)?;
        }
    }
    Ok(())
}

/// Discover gamepads and spawn a reader thread for any not already open. Each
/// thread removes its path from `open` when it ends, so the next rescan respawns
/// a reconnected controller. (A future udev-monitor version can replace the
/// poll-rescan entirely.)
fn spawn_readers(cfg: &Config, tx: &Sender<InMsg>, open: &OpenSet) {
    for path in device::discover_gamepads() {
        {
            let mut guard = open.lock().unwrap();
            if !guard.insert(path.clone()) {
                continue; // already have a reader for this node
            }
        }
        let cfg = cfg.clone();
        let tx = tx.clone();
        let open = Arc::clone(open);
        let p = path.clone();
        thread::Builder::new()
            .name(format!("reader:{}", path.display()))
            .spawn(move || {
                if let Err(e) = device::run_reader(&p, &cfg, tx) {
                    log::info!("reader {} ended: {e}", p.display());
                }
                open.lock().unwrap().remove(&p);
            })
            .ok();
    }
}
