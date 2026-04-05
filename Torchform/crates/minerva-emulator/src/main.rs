// main.rs — Minerva hardware emulator entry point.
//
// Flags:
//   --stream-mode          Enable live display streaming from device
//   --upper-port <u16>     TCP port for upper display H.264 stream (default 5910)
//   --lower-port <u16>     TCP port for lower display H.264 stream (default 5911)
//
// Without --stream-mode the window opens with placeholder text in both panels;
// all existing startup behaviour is preserved.

mod stream;

slint::include_modules!();

use std::sync::Arc;
use stream::DisplayStream;

fn main() {
    // -------------------------------------------------------------------------
    // Parse flags from argv (no clap — not a dependency of this crate).
    // -------------------------------------------------------------------------
    let mut stream_mode = false;
    let mut upper_port: u16 = 5910;
    let mut lower_port: u16 = 5911;

    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--stream-mode" => stream_mode = true,
            "--upper-port" => {
                if let Some(v) = args.next() {
                    upper_port = v.parse().unwrap_or(5910);
                }
            }
            "--lower-port" => {
                if let Some(v) = args.next() {
                    lower_port = v.parse().unwrap_or(5911);
                }
            }
            _ => {}
        }
    }

    // -------------------------------------------------------------------------
    // Create the Slint component.
    // -------------------------------------------------------------------------
    let component = MinervaEmulator::new().expect("failed to create MinervaEmulator");

    // -------------------------------------------------------------------------
    // If --stream-mode: wire up both display streams before entering the loop.
    // -------------------------------------------------------------------------
    let _upper_handle;
    let _lower_handle;

    if stream_mode {
        // --- Upper stream (port, width=1080, height=1920) ---
        let upper_weak = component.as_weak();
        _upper_handle = DisplayStream::new(upper_port, 1080, 1920).start(move |frame: Arc<[u8]>| {
            // Build the pixel buffer on this thread (SharedPixelBuffer is Send).
            let buffer = rgba_to_rgb8_buffer(&frame, 1080, 1920);
            let weak = upper_weak.clone();
            slint::invoke_from_event_loop(move || {
                if let Some(c) = weak.upgrade() {
                    c.set_upper_frame(slint::Image::from_rgb8(buffer));
                }
            })
            .ok();
        });

        // --- Lower stream (port, width=800, height=480) ---
        let lower_weak = component.as_weak();
        _lower_handle = DisplayStream::new(lower_port, 800, 480).start(move |frame: Arc<[u8]>| {
            let buffer = rgba_to_rgb8_buffer(&frame, 800, 480);
            let weak = lower_weak.clone();
            slint::invoke_from_event_loop(move || {
                if let Some(c) = weak.upgrade() {
                    c.set_lower_frame(slint::Image::from_rgb8(buffer));
                }
            })
            .ok();
        });
    } else {
        // Assign dummy handles so the variables are always initialised.
        _upper_handle = std::thread::spawn(|| {});
        _lower_handle = std::thread::spawn(|| {});
    }

    // -------------------------------------------------------------------------
    // Run the event loop.
    // -------------------------------------------------------------------------
    component.run().expect("event loop exited with error");
}

/// Convert a raw RGBA buffer (`width × height × 4` bytes) to an RGB8
/// `SharedPixelBuffer` (alpha channel dropped).  The buffer is `Send` so it
/// can be moved into `invoke_from_event_loop` and converted to `Image` there.
fn rgba_to_rgb8_buffer(
    rgba: &[u8],
    width: u32,
    height: u32,
) -> slint::SharedPixelBuffer<slint::Rgb8Pixel> {
    let mut buffer =
        slint::SharedPixelBuffer::<slint::Rgb8Pixel>::new(width, height);
    let dst = buffer.make_mut_bytes();
    for (out, src) in dst.chunks_mut(3).zip(rgba.chunks(4)) {
        out[0] = src[0];
        out[1] = src[1];
        out[2] = src[2];
        // src[3] is alpha — discarded
    }
    buffer
}
