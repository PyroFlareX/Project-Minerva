// =============================================================================
// uinput.rs — Virtual gamepad via Linux uinput
//
// torchform-inputd creates a virtual gamepad device that the Cirque trackpad
// axes and synthesised joystick events are written to. The compositor reads
// this device just like a hardware gamepad.
//
// Virtual device layout:
//   ABS_X, ABS_Y       — left pad (Cirque) as joystick axes
//   ABS_RX, ABS_RY     — right stick (TLV493D via MCU)
//   ABS_Z, ABS_RZ      — L2/R2 analog triggers
//   BTN_A..BTN_TR2     — face buttons + shoulders + triggers
//   ABS_HAT0X/Y        — D-pad as hat switch
// =============================================================================

use anyhow::{Context, Result};
use tracing::info;

pub struct VirtualGamepad {
    device: uinput::Device,
}

impl VirtualGamepad {
    pub fn new() -> Result<Self> {
        let device = uinput::open("/dev/uinput")
            .context("open /dev/uinput (need write permission or be in 'input' group)")?
            .name("Torchform Virtual Gamepad")
            .context("set device name")?
            .event(uinput::event::controller::Controller::All)
            .context("enable controller events")?
            // Left pad axes (Cirque)
            .event(uinput::event::absolute::Absolute::Position(
                uinput::event::absolute::Position::X,
            ))
            .context("ABS_X")?
            .min(-32768)
            .max(32767)
            .fuzz(16)
            .flat(128)
            .event(uinput::event::absolute::Absolute::Position(
                uinput::event::absolute::Position::Y,
            ))
            .context("ABS_Y")?
            .min(-32768)
            .max(32767)
            .fuzz(16)
            .flat(128)
            // Right stick axes
            .event(uinput::event::absolute::Absolute::Position(
                uinput::event::absolute::Position::RX,
            ))
            .context("ABS_RX")?
            .min(-32768)
            .max(32767)
            .fuzz(16)
            .flat(128)
            .event(uinput::event::absolute::Absolute::Position(
                uinput::event::absolute::Position::RY,
            ))
            .context("ABS_RY")?
            .min(-32768)
            .max(32767)
            .fuzz(16)
            .flat(128)
            // Triggers
            .event(uinput::event::absolute::Absolute::Position(
                uinput::event::absolute::Position::Z,
            ))
            .context("ABS_Z")?
            .min(0)
            .max(255)
            .event(uinput::event::absolute::Absolute::Position(
                uinput::event::absolute::Position::RZ,
            ))
            .context("ABS_RZ")?
            .min(0)
            .max(255)
            // Hat (D-pad)
            .event(uinput::event::absolute::Absolute::Hat(
                uinput::event::absolute::Hat::X0,
            ))
            .context("ABS_HAT0X")?
            .min(-1)
            .max(1)
            .event(uinput::event::absolute::Absolute::Hat(
                uinput::event::absolute::Hat::Y0,
            ))
            .context("ABS_HAT0Y")?
            .min(-1)
            .max(1)
            .create()
            .context("create uinput device")?;

        info!("Virtual gamepad created");
        Ok(Self { device })
    }

    /// Write Cirque trackpad position as joystick ABS_X/Y.
    /// `nx`, `ny` are normalised values in [-1.0, 1.0].
    pub fn set_left_pad(&mut self, nx: f32, ny: f32) -> Result<()> {
        let ix = (nx * 32767.0) as i32;
        let iy = (ny * 32767.0) as i32;
        self.device
            .position(&uinput::event::absolute::Position::X, ix)
            .context("ABS_X write")?;
        self.device
            .position(&uinput::event::absolute::Position::Y, iy)
            .context("ABS_Y write")?;
        self.device.synchronize().context("sync")?;
        Ok(())
    }

    /// Write right stick position as ABS_RX/RY.
    pub fn set_right_stick(&mut self, nx: f32, ny: f32) -> Result<()> {
        let ix = (nx * 32767.0) as i32;
        let iy = (ny * 32767.0) as i32;
        self.device
            .position(&uinput::event::absolute::Position::RX, ix)
            .context("ABS_RX write")?;
        self.device
            .position(&uinput::event::absolute::Position::RY, iy)
            .context("ABS_RY write")?;
        self.device.synchronize().context("sync")?;
        Ok(())
    }

    /// Write D-pad as ABS_HAT0X/Y.
    pub fn set_dpad(&mut self, x: i32, y: i32) -> Result<()> {
        self.device
            .position(&uinput::event::absolute::Hat::X0, x)
            .context("HAT0X write")?;
        self.device
            .position(&uinput::event::absolute::Hat::Y0, y)
            .context("HAT0Y write")?;
        self.device.synchronize().context("sync")?;
        Ok(())
    }
}
