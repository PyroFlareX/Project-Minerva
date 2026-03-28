// =============================================================================
// display.rs — Display output management
//
// Torchform manages two Wayland outputs:
//   - Upper: 1920×1080 primary display (DSI0)
//   - Lower: 640×480  companion touchscreen (DSI1)
//
// In production these map to two DRM/KMS CRTC+connector pairs via the CM5's
// dual MIPI DSI outputs. In development (Winit backend) they open as two
// separate windows.
// =============================================================================

use smithay::{
    output::{Output, PhysicalProperties, Subpixel},
    reexports::wayland_server::DisplayHandle,
    utils::{Logical, Size, Transform},
};

/// Logical names for the two displays.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DisplayRole {
    Upper,
    Lower,
}

/// Geometry configuration for each output.
pub struct DisplayConfig {
    pub role:       DisplayRole,
    pub name:       &'static str,
    pub width:      u32,
    pub height:     u32,
    /// Physical size in mm — used by Wayland for DPI hints.
    pub phys_mm:    (u32, u32),
    pub make:       &'static str,
    pub model:      &'static str,
}

impl DisplayConfig {
    pub fn upper() -> Self {
        Self {
            role:    DisplayRole::Upper,
            name:    "DSI-1",
            width:   1920,
            height:  1080,
            phys_mm: (122, 68),   // 5.5" at 16:9 → ~122×68 mm
            make:    "Minerva",
            model:   "Upper-5.5",
        }
    }

    pub fn lower() -> Self {
        Self {
            role:    DisplayRole::Lower,
            name:    "DSI-2",
            width:   640,
            height:  480,
            phys_mm: (71, 53),    // 3.5" at 4:3 → ~71×53 mm
            make:    "Minerva",
            model:   "Lower-3.5",
        }
    }
}

/// Wrapper around a Smithay `Output` with Torchform metadata.
pub struct TorchOutput {
    pub output: Output,
    pub role:   DisplayRole,
}

impl TorchOutput {
    pub fn new(cfg: DisplayConfig, dh: &DisplayHandle) -> Self {
        let output = Output::new(
            cfg.name.to_string(),
            PhysicalProperties {
                size: (cfg.phys_mm.0 as i32, cfg.phys_mm.1 as i32).into(),
                subpixel: Subpixel::Unknown,
                make: cfg.make.to_string(),
                model: cfg.model.to_string(),
            },
        );

        // Advertise the preferred mode
        let mode = smithay::output::Mode {
            size:    (cfg.width as i32, cfg.height as i32).into(),
            refresh: 60_000, // 60 Hz in mHz
        };
        output.add_mode(mode);
        output.set_preferred(mode);
        output.change_current_state(Some(mode), Some(Transform::Normal), None, None);

        // Publish on the Wayland display
        output.create_global::<crate::compositor::TorchState>(dh);

        Self {
            output,
            role: cfg.role,
        }
    }

    pub fn size(&self) -> Size<i32, Logical> {
        self.output
            .current_mode()
            .map(|m| m.size.to_logical(1))
            .unwrap_or_else(|| (1920, 1080).into())
    }
}
