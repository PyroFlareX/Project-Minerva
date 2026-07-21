# torchform-inputd

Input driver daemon for the Torchform handheld shell. Takes any detected evdev
controller and produces **one normalized uinput virtual gamepad** that both real
apps/games and the `Quickshell.Gamepad` QML plugin consume. Adds **chord** and
**multiclick** aliasing from a TOML config. No virtual keypresses — the shell
reads a real gamepad.

```
physical pads ──reader threads──▶ engine (chords/multiclick) ──▶ uinput virtual pad
   (evdev, grabbed)                  (pure, deterministic)        (apps + plugin read)
```

## Build & run

```sh
cargo build --release
# needs /dev/uinput write + /dev/input/event* read → be in the `input` group:
#   doas addgroup "$USER" input    # then re-login
./target/release/torchform-inputd
```

Start it **before** the compositor so the virtual pad is enumerated at startup.
Config is read from `$TORCHFORM_INPUT_CONFIG`, else
`~/.config/torchform/input.toml` (falls back to built-in defaults if absent).
See [`config/input.toml`](config/input.toml) for the format.

## Daemon ↔ plugin contract

- The virtual pad is named **`torchform-virtpad`** and advertises the standard
  evdev gamepad layout: `BTN_SOUTH/EAST/WEST/NORTH`, `BTN_TL/TR/TL2/TR2`,
  `BTN_SELECT/START/MODE`, `BTN_THUMBL/THUMBR`, `BTN_DPAD_*`, and axes
  `ABS_X/Y/RX/RY` (sticks) + `ABS_Z/RZ` (triggers).
- **Chord / multiclick actions** are pulsed (press→release) on spare
  `BTN_TRIGGER_HAPPY1..16` slots. The mapping from action name → evdev code is
  written to a manifest at `$XDG_RUNTIME_DIR/torchform/inputd-actions.json`:
  ```json
  { "virtpad": "torchform-virtpad", "actions": { "switcher": 704, "home": 705 } }
  ```
  The `Quickshell.Gamepad` plugin opens `torchform-virtpad`, reads it via evdev,
  and emits `buttonPressed/Released(name)` for standard buttons plus
  `actionTriggered(name)` for slots it resolves through the manifest.

## Module map

| File          | Role                                                              |
|---------------|-------------------------------------------------------------------|
| `button.rs`   | Logical button/axis vocabulary (pure; unit-tested)                |
| `config.rs`   | TOML config structs + parsing (pure; unit-tested)                 |
| `engine.rs`   | Chord/multiclick state machine, injected ms clock (pure; tested)  |
| `device.rs`   | evdev controller discovery, grab, raw→logical translation         |
| `virtpad.rs`  | uinput virtual gamepad + action manifest                          |
| `main.rs`     | Wiring: reader threads, hotplug rescan, engine→pad event loop      |

The pure modules carry the hard logic and full test coverage
(`cargo test`); the evdev/uinput layer is isolated in `device.rs` + `virtpad.rs`.

## Known limitations (v1)

- Hotplug is a 2s poll-rescan, not a udev monitor (planned).
- D-pad auto-repeat lives in the shell (QML), not here, so the virtual pad keeps
  true physical state for games.
- A button can be in a chord **or** a multiclick rule, not both (chord wins).
