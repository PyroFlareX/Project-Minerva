// =============================================================================
// cirque.rs — Cirque GlidePoint TM035/TM040 SPI trackpad driver
//
// The CM5 connects the Cirque pad to SPI0 with one GPIO for the data-ready
// (DR) interrupt. The mainline `cirque_pinnacle` kernel driver exposes it as
// a standard Linux input device, but torchform-inputd optionally reads the
// raw SPI registers directly for finer-grained control (Anymeas mode).
//
// Default operation: read /dev/input/event* for the kernel-reported relative
// or absolute axis events and synthesise a virtual joystick via uinput.
// =============================================================================

use std::fs::File;

use anyhow::{Context, Result};
use tracing::info;

// ---------------------------------------------------------------------------
// Pinnacle register map (SPI mode, ADDR | 0xA0 for read, 0x80 for write)
// ---------------------------------------------------------------------------
#[allow(dead_code)]
mod regs {
    pub const FIRMWARE_ID:      u8 = 0x00;
    pub const FIRMWARE_VER:     u8 = 0x01;
    pub const STATUS1:          u8 = 0x02;
    pub const SYS_CONFIG1:      u8 = 0x03;
    pub const FEED_CONFIG1:     u8 = 0x04;
    pub const FEED_CONFIG2:     u8 = 0x05;
    pub const FEED_CONFIG3:     u8 = 0x06;
    pub const CAL_CONFIG1:      u8 = 0x07;
    pub const PS2_AUX_CTRL:     u8 = 0x08;
    pub const SAMPLE_RATE:      u8 = 0x09;
    pub const Z_IDLE:           u8 = 0x0A;
    pub const Z_SCALER:         u8 = 0x0B;
    pub const SLEEP_INTERVAL:   u8 = 0x0C;
    pub const SLEEP_TIMER:      u8 = 0x0D;
    pub const EMI_THRESHOLD:    u8 = 0x0E;
    pub const PACKET_BYTE_0:    u8 = 0x12;   // Start of absolute coordinate packet
    pub const PACKET_BYTE_1:    u8 = 0x13;
    pub const PACKET_BYTE_2:    u8 = 0x14;
    pub const PACKET_BYTE_3:    u8 = 0x15;
    pub const PACKET_BYTE_4:    u8 = 0x16;
    pub const PACKET_BYTE_5:    u8 = 0x17;
}

/// A decoded absolute-mode sample from the Pinnacle controller.
#[allow(dead_code)]
#[derive(Debug, Clone, Copy)]
pub struct CirqueSample {
    /// X coordinate — 0..2047 (0 = left edge, 2047 = right edge)
    pub x:       u16,
    /// Y coordinate — 0..1535 (0 = top, 1535 = bottom)
    pub y:       u16,
    /// Z (contact pressure) — 0..63  (0 = no touch)
    pub z:       u8,
    /// Button states bit-field (buttons 0..2)
    pub buttons: u8,
}

impl CirqueSample {
    /// Returns true if the finger is currently touching the pad.
    pub fn is_touching(&self) -> bool {
        self.z > 0
    }

    /// Normalise X into [-1.0, 1.0] — suitable for a joystick axis.
    pub fn norm_x(&self) -> f32 {
        (self.x as f32 / 1023.5) - 1.0
    }

    /// Normalise Y into [-1.0, 1.0].
    pub fn norm_y(&self) -> f32 {
        (self.y as f32 / 767.5) - 1.0
    }
}

// ---------------------------------------------------------------------------
// SPI reader — wraps spidev
// ---------------------------------------------------------------------------

pub struct CirqueSpi {
    dev: spidev::Spidev,
}

impl CirqueSpi {
    /// Open the SPI device at `path` (typically `/dev/spidev0.0`).
    pub fn open(path: &str) -> Result<Self> {
        use spidev::{SpiModeFlags, SpidevOptions};

        let mut dev = spidev::Spidev::open(path)
            .with_context(|| format!("open SPI device {path}"))?;

        let opts = SpidevOptions::new()
            .bits_per_word(8)
            .max_speed_hz(10_000_000)   // 10 MHz — well within Pinnacle's 13 MHz max
            .mode(SpiModeFlags::SPI_MODE_1)
            .build();

        dev.configure(&opts)
            .context("configure SPI device")?;

        info!("Cirque SPI device opened: {path}");
        Ok(Self { dev })
    }

    /// Read a single Pinnacle register.
    fn read_reg(&mut self, addr: u8) -> Result<u8> {
        use spidev::SpidevTransfer;

        // Pinnacle SPI read: send ADDR | 0xA0, then 3 filler bytes, read 1 byte
        let tx = [addr | 0xA0, 0xFB, 0xFB, 0xFB, 0xFB];
        let mut rx = [0u8; 5];
        let mut xfer = SpidevTransfer::read_write(&tx, &mut rx);
        self.dev.transfer(&mut xfer).context("SPI transfer")?;
        Ok(rx[4])
    }

    /// Write a single Pinnacle register.
    #[allow(dead_code)]
    fn write_reg(&mut self, addr: u8, val: u8) -> Result<()> {
        use std::io::Write as _;
        let buf = [addr | 0x80, val];
        self.dev.write_all(&buf).context("SPI write")?;
        Ok(())
    }

    /// Clear the SW_DR status bit so the next sample can be flagged.
    fn clear_flags(&mut self) -> Result<()> {
        // Write 0 to STATUS1 bits 2..3
        self.write_reg(regs::STATUS1, 0)
    }

    /// Poll for a new absolute-mode sample. Returns None if no data ready.
    pub fn poll_sample(&mut self) -> Result<Option<CirqueSample>> {
        let status = self.read_reg(regs::STATUS1)?;
        if status & 0x04 == 0 {
            // DR bit not set — no new data
            return Ok(None);
        }

        // Read the 6-byte absolute packet
        let b0 = self.read_reg(regs::PACKET_BYTE_0)?;
        let _b1 = self.read_reg(regs::PACKET_BYTE_1)?;  // reserved byte — must be read to advance pointer
        let b2 = self.read_reg(regs::PACKET_BYTE_2)?;
        let b3 = self.read_reg(regs::PACKET_BYTE_3)?;
        let b4 = self.read_reg(regs::PACKET_BYTE_4)?;
        let b5 = self.read_reg(regs::PACKET_BYTE_5)?;
        self.clear_flags()?;

        // Decode per Cirque Pinnacle datasheet (absolute mode, no ERA)
        // X[11:0] = {b4[3:0], b2[7:0]}  — 12-bit
        // Y[11:0] = {b4[7:4], b3[7:0]}  — 12-bit
        // Z[5:0]  = b5[5:0]
        let x = ((b4 as u16 & 0x0F) << 8) | (b2 as u16);
        let y = ((b4 as u16 & 0xF0) << 4) | (b3 as u16);
        let z = b5 & 0x3F;
        let buttons = b0 & 0x07;

        Ok(Some(CirqueSample { x, y, z, buttons }))
    }
}

// ---------------------------------------------------------------------------
// Kernel evdev reader (fallback when kernel cirque_pinnacle driver is active)
// ---------------------------------------------------------------------------

/// Reads relative axis events from the kernel-provided evdev node.
/// The cirque_pinnacle driver exposes the pad as a relative mouse.
#[allow(dead_code)]
pub struct CirqueEvdev {
    file: File,
}

#[allow(dead_code)]
impl CirqueEvdev {
    pub fn open(path: &str) -> Result<Self> {
        let file = File::open(path)
            .with_context(|| format!("open evdev {path}"))?;
        info!("Cirque evdev opened: {path}");
        Ok(Self { file })
    }

    /// Non-blocking read — returns (rel_x, rel_y) deltas, or None if no event.
    pub fn read_rel(&mut self) -> Option<(i32, i32)> {
        // Linux input_event: { timeval (16 bytes), type (2), code (2), value (4) }
        let mut buf = [0u8; 24];
        use std::io::Read;
        match self.file.read(&mut buf) {
            Ok(24) => {
                let ev_type = u16::from_ne_bytes([buf[16], buf[17]]);
                let ev_code = u16::from_ne_bytes([buf[18], buf[19]]);
                let ev_value = i32::from_ne_bytes([buf[20], buf[21], buf[22], buf[23]]);
                match (ev_type, ev_code) {
                    (0x02, 0x00) => Some((ev_value, 0)),  // EV_REL, REL_X
                    (0x02, 0x01) => Some((0, ev_value)),  // EV_REL, REL_Y
                    _ => None,
                }
            }
            _ => None,
        }
    }
}
