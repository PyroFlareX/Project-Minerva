// =============================================================================
// audio.rs — Fire-and-forget UI sound cues using rodio 0.22
//
// OGG clips are embedded at compile time from assets/sounds/.
// Replace placeholder files with real short OGG clips (< 100ms).
//
// To generate real sounds (requires sox):
//   sox -n nav.ogg     synth 0.05 sine 880
//   sox -n confirm.ogg synth 0.08 sine 1040
//   sox -n cancel.ogg  synth 0.06 sine 440
// =============================================================================

use std::io::Cursor;

const NAV_OGG:     &[u8] = include_bytes!("../assets/sounds/nav.ogg");
const CONFIRM_OGG: &[u8] = include_bytes!("../assets/sounds/confirm.ogg");
const CANCEL_OGG:  &[u8] = include_bytes!("../assets/sounds/cancel.ogg");

#[derive(Debug, Clone, Copy)]
pub enum SoundCue {
    Nav,
    Confirm,
    Cancel,
}

/// Play a sound cue in a background thread (fire-and-forget, non-blocking).
/// Silently does nothing if audio device unavailable or file invalid.
pub fn play(cue: SoundCue) {
    let data: &'static [u8] = match cue {
        SoundCue::Nav     => NAV_OGG,
        SoundCue::Confirm => CONFIRM_OGG,
        SoundCue::Cancel  => CANCEL_OGG,
    };
    std::thread::spawn(move || {
        // rodio 0.22: DeviceSinkBuilder::open_default_sink() → MixerDeviceSink
        // rodio::play(mixer, reader) where reader: Read + Seek
        let sink = match rodio::DeviceSinkBuilder::open_default_sink() {
            Ok(s)  => s,
            Err(_) => return, // no audio device
        };
        // Pass the raw cursor — rodio decodes internally
        let cursor = Cursor::new(data);
        let player = match rodio::play(sink.mixer(), cursor) {
            Ok(p)  => p,
            Err(_) => return, // placeholder / invalid OGG — silent
        };
        player.sleep_until_end();
    });
}
