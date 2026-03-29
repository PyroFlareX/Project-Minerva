// =============================================================================
// torchform-compositor — Torchform Wayland compositor
//
// Built on Smithay. Manages:
//   - Two Wayland outputs: upper (1920×1080) + lower (640×480)
//   - XDG shell window lifecycle (map, unmap, configure)
//   - Fullscreen-first tiling: fullscreen OR horizontal split only
//   - Input routing from libinput (production) or Winit (development)
//   - Compositor exposes WAYLAND_DISPLAY socket for Slint shell + apps
//
// Backend selection:
//   TORCHFORM_BACKEND=winit   → Winit (desktop dev, QEMU)   [default]
//   TORCHFORM_BACKEND=udev    → DRM/KMS via libseat (device)
// =============================================================================

mod compositor;
mod display;
mod input;

use std::{sync::Arc, time::Duration};

use anyhow::{Context, Result};
use tracing::info;

use smithay::{
    input::keyboard::FilterResult,
    reexports::{
        calloop::EventLoop,
        wayland_server::Display,
    },
    wayland::socket::ListeningSocketSource,
};

use compositor::{TorchState, ClientState};
use display::{DisplayConfig, TorchOutput};

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("torchform_compositor=debug".parse().unwrap())
                .add_directive("smithay=warn".parse().unwrap()),
        )
        .init();

    info!("torchform-compositor starting");

    let backend = std::env::var("TORCHFORM_BACKEND")
        .unwrap_or_else(|_| "winit".into());

    match backend.as_str() {
        "udev" => run_udev(),
        _      => run_winit(),
    }
}

// ---------------------------------------------------------------------------
// Winit backend — development / QEMU
// ---------------------------------------------------------------------------

fn run_winit() -> Result<()> {
    use smithay::backend::{
        renderer::gles::GlesRenderer,
        winit::{self, WinitEvent},
    };

    info!("Using Winit backend (set TORCHFORM_BACKEND=udev for hardware)");

    let mut event_loop: EventLoop<'static, TorchState> =
        EventLoop::try_new().context("create event loop")?;

    let mut display: Display<TorchState> =
        Display::new().context("create Wayland display")?;

    // Create Wayland socket via smithay's ListeningSocketSource
    let listening_socket = ListeningSocketSource::new_auto()
        .context("open Wayland socket")?;
    let socket_name = listening_socket.socket_name().to_os_string();
    info!("Wayland socket: {}", socket_name.to_string_lossy());
    std::env::set_var("WAYLAND_DISPLAY", &socket_name);

    // Insert socket as calloop event source — accepts new clients
    event_loop
        .handle()
        .insert_source(listening_socket, |client_stream, _, state: &mut TorchState| {
            state.display_handle
                .insert_client(client_stream, Arc::new(ClientState::default()))
                .ok();
        })
        .context("insert listening socket source")?;

    // Create outputs
    let upper = TorchOutput::new(DisplayConfig::upper(), &display.handle());
    let lower = TorchOutput::new(DisplayConfig::lower(), &display.handle());

    // Init compositor state
    let mut state = TorchState::new(&display, &event_loop, upper, lower);

    // Set up Winit backend for the upper display (GlesRenderer is the concrete type)
    let (mut winit_backend, mut winit_evt_loop) =
        winit::init::<GlesRenderer>()
            .map_err(|e| anyhow::anyhow!("Winit init failed: {e}"))?;

    let sz = winit_backend.window_size();
    info!("Winit backend ready — {}×{}", sz.w, sz.h);

    info!("Entering event loop");

    loop {
        // Dispatch Winit events
        use smithay::reexports::winit::platform::pump_events::PumpStatus;

        let status = winit_evt_loop.dispatch_new_events(|event: WinitEvent| {
            match event {
                WinitEvent::Resized { size, .. } => {
                    tracing::debug!("Winit resize: {:?}", size);
                }
                WinitEvent::Input(input_event) => {
                    handle_winit_input(&mut state, input_event);
                }
                WinitEvent::CloseRequested => {
                    info!("Window close requested — exiting");
                    std::process::exit(0);
                }
                _ => {}
            }
        });

        if let PumpStatus::Exit(_) = status {
            break;
        }

        // Render (placeholder — real renderer goes here)
        winit_backend.bind().ok();
        // TODO: Render windows via GL renderer
        winit_backend.submit(None).ok();

        // Dispatch pending Wayland client messages
        display.dispatch_clients(&mut state).ok();
        display.flush_clients().ok();

        // Give the calloop sources (listening socket) a chance to run
        event_loop
            .dispatch(Duration::from_millis(1), &mut state)
            .context("event loop dispatch")?;
    }

    Ok(())
}

fn handle_winit_input(
    state: &mut TorchState,
    event: smithay::backend::input::InputEvent<smithay::backend::winit::WinitInput>,
) {
    use smithay::backend::input::{Event, InputEvent, KeyboardKeyEvent};

    match event {
        InputEvent::Keyboard { event } => {
            let keycode = event.key_code();
            let key_state = event.state();

            if let Some(kbd) = state.seat.get_keyboard() {
                kbd.input::<(), _>(
                    state,
                    keycode,
                    key_state,
                    smithay::utils::SERIAL_COUNTER.next_serial(),
                    event.time_msec(),
                    |_, _, _| FilterResult::Forward,
                );
            }
        }
        InputEvent::PointerMotionAbsolute { event } => {
            use smithay::backend::input::AbsolutePositionEvent;
            let size = state.upper_output.size();
            let x = event.x_transformed(size.w) as f64;
            let y = event.y_transformed(size.h) as f64;
            state.pointer_location = (x, y).into();
        }
        InputEvent::PointerButton { .. } => {
            // Route to focused window via Smithay pointer
        }
        _ => {}
    }
}

// ---------------------------------------------------------------------------
// UDev/DRM backend — production (Raspberry Pi CM5)
// ---------------------------------------------------------------------------

fn run_udev() -> Result<()> {
    info!("Using UDev/DRM backend");

    if std::env::var("XDG_RUNTIME_DIR").is_err() {
        std::env::set_var("XDG_RUNTIME_DIR", "/run/torchform");
        std::fs::create_dir_all("/run/torchform").ok();
    }

    let mut event_loop: EventLoop<'static, TorchState> =
        EventLoop::try_new().context("create event loop")?;

    let display: Display<TorchState> =
        Display::new().context("create Wayland display")?;

    let listening_socket = ListeningSocketSource::new_auto()
        .context("open Wayland socket")?;
    let socket_name = listening_socket.socket_name().to_os_string();
    info!("Wayland socket: {}", socket_name.to_string_lossy());
    std::env::set_var("WAYLAND_DISPLAY", &socket_name);

    event_loop
        .handle()
        .insert_source(listening_socket, |client_stream, _, state: &mut TorchState| {
            state.display_handle
                .insert_client(client_stream, Arc::new(ClientState::default()))
                .ok();
        })
        .context("insert listening socket source")?;

    let upper = TorchOutput::new(DisplayConfig::upper(), &display.handle());
    let lower = TorchOutput::new(DisplayConfig::lower(), &display.handle());

    let mut state = TorchState::new(&display, &event_loop, upper, lower);

    // TODO: Set up UdevBackend, libseat, libinput sources here.
    // See smithay/examples/anvil for full udev backend setup.

    info!("UDev backend stub — full DRM/KMS integration pending");
    info!("Run with TORCHFORM_BACKEND=winit for development");

    event_loop
        .run(Duration::from_millis(16), &mut state, |_| {})
        .context("event loop")?;

    Ok(())
}
