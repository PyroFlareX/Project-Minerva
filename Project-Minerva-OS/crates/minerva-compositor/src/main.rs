// =============================================================================
// minerva-compositor — Priority 8 skeleton
//
// Tries DRM dumb buffers first (/dev/dri/card*), then falls back to the
// Linux fbdev interface (/dev/fb0) for QEMU ramfb / virtio-gpu-less setups.
// Paints Minerva's electric teal (#00D4FF) and holds the mode.
//
// No Wayland socket yet — that comes in Priority 9 alongside the shell.
// =============================================================================

use std::{
    os::unix::io::{AsFd, BorrowedFd},
    time::Duration,
};

use drm::{
    buffer::DrmFourcc,
    control::{connector, Device as ControlDevice},
    Device,
};
use anyhow::{Context, Result};

// ---------------------------------------------------------------------------
// Minimal DRM device wrapper
// ---------------------------------------------------------------------------
struct DrmCard(std::fs::File);

impl AsFd for DrmCard {
    fn as_fd(&self) -> BorrowedFd<'_> {
        self.0.as_fd()
    }
}

impl Device for DrmCard {}
impl ControlDevice for DrmCard {}

impl DrmCard {
    fn open(path: &str) -> Result<Self> {
        let file = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .open(path)
            .with_context(|| format!("open DRM device {path}"))?;
        Ok(Self(file))
    }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------
fn main() -> Result<()> {
    tracing_subscriber::fmt::init();
    tracing::info!("minerva-compositor starting");

    match find_drm_device() {
        Some(path) => {
            tracing::info!("DRM device: {path}");
            run_drm(&path)
        }
        None => {
            tracing::info!("no DRM device — trying /dev/fb0 (ramfb / fbdev)");
            run_fbdev("/dev/fb0")
        }
    }
}

// ---------------------------------------------------------------------------
// DRM path — dumb framebuffer via kernel DRM ioctls (virtio-gpu)
// ---------------------------------------------------------------------------
fn run_drm(path: &str) -> Result<()> {
    let card = DrmCard::open(path)?;

    let res = card.resource_handles().context("DRM resource_handles")?;

    let conn = res
        .connectors()
        .iter()
        .filter_map(|h| card.get_connector(*h, true).ok())
        .find(|c| c.state() == connector::State::Connected)
        .context("no connected display — check QEMU display device")?;

    let mode = *conn.modes().first().context("connector has no modes")?;
    let (w, h) = (mode.size().0 as u32, mode.size().1 as u32);
    tracing::info!("connector: {:?}  mode: {w}x{h}", conn.interface());

    let enc_handle = conn
        .current_encoder()
        .context("connector has no current encoder")?;
    let enc = card.get_encoder(enc_handle).context("get_encoder")?;
    let crtc_handle = enc.crtc().context("encoder has no CRTC")?;

    let mut db = card
        .create_dumb_buffer((w, h), DrmFourcc::Xrgb8888, 32)
        .context("create_dumb_buffer")?;

    // Paint Minerva teal #00D4FF
    // XRGB8888 little-endian: bytes [B, G, R, X] = [0xFF, 0xD4, 0x00, 0x00]
    {
        let mut map = card.map_dumb_buffer(&mut db).context("map_dumb_buffer")?;
        for pixel in map.as_mut().chunks_exact_mut(4) {
            pixel[0] = 0xFF; // B
            pixel[1] = 0xD4; // G
            pixel[2] = 0x00; // R
            pixel[3] = 0x00; // X (padding)
        }
    }

    let fb = card
        .add_framebuffer(&db, 24, 32)
        .context("add_framebuffer")?;

    card.set_crtc(crtc_handle, Some(fb), (0, 0), &[conn.handle()], Some(mode))
        .context("set_crtc")?;

    tracing::info!("DRM compositor active — teal screen on {w}x{h}");
    tracing::info!("next: Wayland socket (Priority 9 — minerva-shell + Slint)");

    loop {
        std::thread::sleep(Duration::from_secs(10));
    }
}

// ---------------------------------------------------------------------------
// fbdev path — direct write to /dev/fb0 (QEMU ramfb, no DRM required)
//
// Reads display dimensions from sysfs, writes teal pixels as ARGB8888
// (the format ramfb exposes by default).
// ---------------------------------------------------------------------------
fn run_fbdev(fb_path: &str) -> Result<()> {
    let (w, h) = fbdev_dimensions().unwrap_or((1280, 720));
    tracing::info!("fbdev {fb_path}  resolution: {w}x{h}");

    // ARGB8888 little-endian: bytes [B, G, R, A] = [0xFF, 0xD4, 0x00, 0xFF]
    // Minerva teal #00D4FF, fully opaque
    let pixel: [u8; 4] = [0xFF, 0xD4, 0x00, 0xFF];
    let row_bytes = (w * 4) as usize;
    let mut row = vec![0u8; row_bytes];
    for p in row.chunks_exact_mut(4) {
        p.copy_from_slice(&pixel);
    }

    let mut fb = std::fs::OpenOptions::new()
        .write(true)
        .open(fb_path)
        .with_context(|| format!("open {fb_path}"))?;

    use std::io::Write as _;
    for _ in 0..h {
        fb.write_all(&row).context("write row to fb0")?;
    }
    fb.flush().context("flush fb0")?;

    tracing::info!("fbdev compositor active — teal screen on {w}x{h}");
    tracing::info!("next: Wayland socket (Priority 9 — minerva-shell + Slint)");

    loop {
        std::thread::sleep(Duration::from_secs(10));
    }
}

/// Read framebuffer width and height from sysfs.
/// Path: /sys/class/graphics/fb0/virtual_size  → "W,H\n"
fn fbdev_dimensions() -> Option<(u32, u32)> {
    let s = std::fs::read_to_string("/sys/class/graphics/fb0/virtual_size").ok()?;
    let mut parts = s.trim().split(',');
    let w: u32 = parts.next()?.parse().ok()?;
    let h: u32 = parts.next()?.parse().ok()?;
    Some((w, h))
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
fn find_drm_device() -> Option<String> {
    (0..8)
        .map(|i| format!("/dev/dri/card{i}"))
        .find(|p| std::path::Path::new(p).exists())
}
