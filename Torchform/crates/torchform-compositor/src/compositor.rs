// =============================================================================
// compositor.rs — Smithay compositor state + Wayland protocol delegates
//
// TorchState owns all Smithay protocol state. It implements the delegate
// traits required by smithay's macro system.
//
// Tiling model:
//   - First window → fullscreen on upper output
//   - Second window → horizontal split (left + right, each 960×1080)
//   - No floating windows; max two tiles
// =============================================================================

use smithay::{
    backend::renderer::utils::on_commit_buffer_handler,
    delegate_compositor, delegate_data_device, delegate_output,
    delegate_seat, delegate_shm, delegate_xdg_shell,
    input::{
        Seat, SeatHandler, SeatState,
        pointer::CursorImageStatus,
    },
    reexports::{
        calloop::{EventLoop, LoopHandle},
        wayland_server::{
            backend::{ClientData, ClientId, DisconnectReason},
            Display, DisplayHandle,
            protocol::wl_surface::WlSurface,
        },
    },
    utils::{Logical, Point, Rectangle, Size, Serial},
    wayland::{
        buffer::BufferHandler,
        compositor::{
            CompositorClientState, CompositorHandler, CompositorState,
        },
        output::OutputManagerState,
        selection::{
            SelectionHandler,
            data_device::{
                ClientDndGrabHandler, DataDeviceHandler, DataDeviceState,
                ServerDndGrabHandler,
            },
        },
        shell::xdg::{
            PopupSurface, PositionerState, ToplevelSurface,
            XdgShellHandler, XdgShellState,
        },
        shm::{ShmHandler, ShmState},
    },
};

use crate::{
    display::TorchOutput,
    input::ChordTracker,
};

// ---------------------------------------------------------------------------
// Window model
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TileAssignment {
    Fullscreen,
    Left,
    Right,
}

#[derive(Debug)]
pub struct TorchWindow {
    pub toplevel: ToplevelSurface,
    pub tile:     TileAssignment,
}

impl TorchWindow {
    pub fn geometry(&self, output_size: Size<i32, Logical>) -> Rectangle<i32, Logical> {
        match self.tile {
            TileAssignment::Fullscreen => {
                Rectangle::new((0, 0).into(), output_size)
            }
            TileAssignment::Left => {
                let w = output_size.w / 2;
                Rectangle::new((0, 0).into(), (w, output_size.h).into())
            }
            TileAssignment::Right => {
                let w = output_size.w / 2;
                Rectangle::new((w, 0).into(), (w, output_size.h).into())
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Central compositor state
// ---------------------------------------------------------------------------

#[allow(dead_code)]
pub struct TorchState {
    pub display_handle:    DisplayHandle,
    pub loop_handle:       LoopHandle<'static, Self>,

    // Wayland protocol state
    pub compositor_state:  CompositorState,
    pub xdg_shell_state:   XdgShellState,
    pub shm_state:         ShmState,
    pub output_manager:    OutputManagerState,
    pub seat_state:        SeatState<Self>,
    pub data_device_state: DataDeviceState,

    // Seat
    pub seat:              Seat<Self>,

    // Outputs
    pub upper_output:      TorchOutput,
    pub lower_output:      TorchOutput,

    // Windows (tiling model)
    pub windows:           Vec<TorchWindow>,

    // Input
    pub chord_tracker:     ChordTracker,

    // Pointer
    pub cursor_status:     CursorImageStatus,
    pub pointer_location:  Point<f64, Logical>,

    // Keyboard focus surface
    pub keyboard_focus:    Option<WlSurface>,
    pub focused_tile:      usize,
}

impl TorchState {
    pub fn new(
        display: &Display<Self>,
        event_loop: &EventLoop<'static, Self>,
        upper: TorchOutput,
        lower: TorchOutput,
    ) -> Self {
        let dh = display.handle();

        let compositor_state  = CompositorState::new::<Self>(&dh);
        let xdg_shell_state   = XdgShellState::new::<Self>(&dh);
        let shm_state         = ShmState::new::<Self>(&dh, vec![]);
        let output_manager    = OutputManagerState::new_with_xdg_output::<Self>(&dh);
        let mut seat_state    = SeatState::new();
        let data_device_state = DataDeviceState::new::<Self>(&dh);

        let mut seat = seat_state.new_wl_seat(&dh, "minerva");
        seat.add_keyboard(Default::default(), 200, 25)
            .expect("failed to add keyboard to seat");
        seat.add_pointer();
        seat.add_touch();

        Self {
            display_handle:    dh,
            loop_handle:       event_loop.handle(),
            compositor_state,
            xdg_shell_state,
            shm_state,
            output_manager,
            seat_state,
            data_device_state,
            seat,
            upper_output:      upper,
            lower_output:      lower,
            windows:           Vec::new(),
            chord_tracker:     ChordTracker::default(),
            cursor_status:     CursorImageStatus::default_named(),
            pointer_location:  (0.0, 0.0).into(),
            keyboard_focus:    None,
            focused_tile:      0,
        }
    }

    // -----------------------------------------------------------------------
    // Tiling helpers
    // -----------------------------------------------------------------------

    pub fn map_window(&mut self, toplevel: ToplevelSurface) {
        let size = self.upper_output.size();

        let tile = if self.windows.is_empty() {
            TileAssignment::Fullscreen
        } else {
            // Promote existing fullscreen to Left, new window to Right
            for w in &mut self.windows {
                if w.tile == TileAssignment::Fullscreen {
                    w.tile = TileAssignment::Left;
                    let geo = w.geometry(size);
                    w.toplevel.with_pending_state(|s| { s.size = Some(geo.size); });
                    w.toplevel.send_configure();
                }
            }
            TileAssignment::Right
        };

        let geo = TorchWindow { toplevel: toplevel.clone(), tile }.geometry(size);
        toplevel.with_pending_state(|s| { s.size = Some(geo.size); });
        toplevel.send_configure();

        self.windows.push(TorchWindow { toplevel, tile });
        tracing::info!("Window mapped. tile={:?}  total={}", tile, self.windows.len());
    }

    pub fn unmap_window(&mut self, surface: &WlSurface) {
        self.windows.retain(|w| w.toplevel.wl_surface() != surface);

        // If only one remains, restore fullscreen
        if self.windows.len() == 1 {
            let size = self.upper_output.size();
            let w = &mut self.windows[0];
            w.tile = TileAssignment::Fullscreen;
            w.toplevel.with_pending_state(|s| { s.size = Some(size); });
            w.toplevel.send_configure();
        }
        tracing::info!("Window unmapped. remaining={}", self.windows.len());
    }

    #[allow(dead_code)]
    pub fn cycle_tile_focus(&mut self) {
        if self.windows.len() > 1 {
            self.focused_tile = 1 - self.focused_tile;
        }
    }
}

// ---------------------------------------------------------------------------
// Smithay delegate implementations
// ---------------------------------------------------------------------------

impl CompositorHandler for TorchState {
    fn compositor_state(&mut self) -> &mut CompositorState {
        &mut self.compositor_state
    }

    fn client_compositor_state<'a>(
        &self,
        client: &'a smithay::reexports::wayland_server::Client,
    ) -> &'a CompositorClientState {
        &client.get_data::<ClientState>().unwrap().compositor_state
    }

    fn commit(&mut self, surface: &WlSurface) {
        on_commit_buffer_handler::<Self>(surface);
    }
}
delegate_compositor!(TorchState);

impl BufferHandler for TorchState {
    fn buffer_destroyed(
        &mut self,
        _buffer: &smithay::reexports::wayland_server::protocol::wl_buffer::WlBuffer,
    ) {}
}

impl ShmHandler for TorchState {
    fn shm_state(&self) -> &ShmState {
        &self.shm_state
    }
}
delegate_shm!(TorchState);

impl XdgShellHandler for TorchState {
    fn xdg_shell_state(&mut self) -> &mut XdgShellState {
        &mut self.xdg_shell_state
    }

    fn new_toplevel(&mut self, surface: ToplevelSurface) {
        self.map_window(surface);
    }

    fn new_popup(&mut self, _surface: PopupSurface, _positioner: PositionerState) {}

    fn toplevel_destroyed(&mut self, surface: ToplevelSurface) {
        self.unmap_window(surface.wl_surface());
    }

    fn popup_destroyed(&mut self, _surface: PopupSurface) {}

    fn grab(
        &mut self,
        _surface: PopupSurface,
        _seat: smithay::reexports::wayland_server::protocol::wl_seat::WlSeat,
        _serial: Serial,
    ) {}

    fn reposition_request(
        &mut self,
        _surface: PopupSurface,
        _positioner: PositionerState,
        _token: u32,
    ) {}
}
delegate_xdg_shell!(TorchState);

impl SeatHandler for TorchState {
    type KeyboardFocus = WlSurface;
    type PointerFocus  = WlSurface;
    type TouchFocus    = WlSurface;

    fn seat_state(&mut self) -> &mut SeatState<Self> {
        &mut self.seat_state
    }

    fn cursor_image(&mut self, _seat: &Seat<Self>, image: CursorImageStatus) {
        self.cursor_status = image;
    }

    fn focus_changed(&mut self, _seat: &Seat<Self>, focused: Option<&WlSurface>) {
        self.keyboard_focus = focused.cloned();
    }
}
delegate_seat!(TorchState);

impl smithay::wayland::output::OutputHandler for TorchState {}
delegate_output!(TorchState);

impl SelectionHandler for TorchState {
    type SelectionUserData = ();
}

impl DataDeviceHandler for TorchState {
    fn data_device_state(&self) -> &DataDeviceState {
        &self.data_device_state
    }
}
impl ClientDndGrabHandler for TorchState {}
impl ServerDndGrabHandler for TorchState {}
delegate_data_device!(TorchState);

// ---------------------------------------------------------------------------
// Per-connection client state
// ---------------------------------------------------------------------------

#[derive(Default)]
pub struct ClientState {
    pub compositor_state: CompositorClientState,
}

impl ClientData for ClientState {
    fn initialized(&self, _client_id: ClientId) {}
    fn disconnected(&self, _client_id: ClientId, _reason: DisconnectReason) {}
}
