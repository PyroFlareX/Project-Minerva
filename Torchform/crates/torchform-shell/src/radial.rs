// =============================================================================
// radial.rs — Radial menu state machine
//
// Tracks which layer is open, which item is focused, and handles D-pad
// navigation across the 8-slot ring.
//
// NOTE: `MenuItem` and `MenuLayer` are native Rust types. main.rs converts
// them to the Slint-generated `RadialItem` / `RadialLayer` when updating the UI.
// =============================================================================

/// Clockwise ordering of the 8 slots:
/// 0=top, 1=top-right, 2=right, 3=bottom-right,
/// 4=bottom, 5=bottom-left, 6=left, 7=top-left
const SLOT_COUNT: usize = 8;

/// Directional input from the D-pad or left Cirque pad.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Direction {
    Up,
    Down,
    Left,
    Right,
}

/// Which trigger layer opened the menu.
#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MenuLayer {
    App1,    // L2 alone
    App2,    // R2 alone
    System,  // L2 + R2
}

/// A single item in the radial menu (Rust-side representation).
#[derive(Debug, Clone)]
pub struct MenuItem {
    pub label:     String,
    pub icon:      String,
    pub enabled:   bool,
    pub is_nested: bool,
}

pub struct RadialMenuState {
    pub visible:       bool,
    pub layer:         MenuLayer,
    pub items:         Vec<MenuItem>,
    pub focused_index: usize,
}

impl RadialMenuState {
    pub fn new() -> Self {
        Self {
            visible:       false,
            layer:         MenuLayer::System,
            items:         Vec::new(),
            focused_index: 0,
        }
    }

    /// Open the menu with a specific layer and item set.
    pub fn open(&mut self, layer: MenuLayer, items: Vec<MenuItem>) {
        self.layer         = layer;
        self.items         = items;
        self.focused_index = 0;
        self.visible       = true;
    }

    pub fn close(&mut self) {
        self.visible = false;
    }

    /// Move focus using D-pad direction.
    /// The ring is arranged clockwise; up/right increment, down/left decrement.
    pub fn navigate(&mut self, dir: Direction) {
        if self.items.is_empty() {
            return;
        }
        let count = self.items.len().min(SLOT_COUNT);
        self.focused_index = match dir {
            Direction::Up | Direction::Right => (self.focused_index + 1) % count,
            Direction::Down | Direction::Left => {
                (self.focused_index + count - 1) % count
            }
        };
    }


    /// Update the focused slot from an analog stick position.
    /// `x` and `y` are normalised [-1.0, 1.0]; Y is screen-coords (up = negative).
    /// Returns true if the stick is past the deadzone (a direction is held).
    pub fn update_from_stick(&mut self, x: f32, y: f32) -> bool {
        const DEADZONE: f32 = 0.3;
        let mag = (x * x + y * y).sqrt();
        if self.items.is_empty() || mag < DEADZONE {
            return false;
        }
        let count = self.items.len().min(SLOT_COUNT);
        // atan2(y, x): right=0, up=-π/2 (screen coords: up = negative y).
        // Shift +π/2 so slot 0 (top) is at angle 0 and rotation is clockwise.
        let angle = y.atan2(x) + std::f32::consts::FRAC_PI_2;
        let angle = (angle + 2.0 * std::f32::consts::PI) % (2.0 * std::f32::consts::PI);
        self.focused_index =
            ((angle * count as f32 / (2.0 * std::f32::consts::PI)) + 0.5) as usize % count;
        true
    }
}

// ---------------------------------------------------------------------------
// System radial items — built from config, falling back to built-in defaults
// ---------------------------------------------------------------------------

/// Build the system radial item list from config slots.
/// If the config has no slots defined, returns the built-in defaults.
pub fn system_radial_items(slots: &[crate::config::RadialSlotConfig]) -> Vec<MenuItem> {
    if slots.is_empty() {
        return default_radial_items();
    }
    slots.iter().take(SLOT_COUNT).map(|s| MenuItem {
        label:     s.label.clone(),
        icon:      s.icon.clone(),
        enabled:   s.enabled,
        is_nested: s.nested,
    }).collect()
}

fn default_radial_items() -> Vec<MenuItem> {
    vec![
        MenuItem { label: "Brightness".into(), icon: "☀".into(),  enabled: true,  is_nested: true },
        MenuItem { label: "Volume".into(),     icon: "🔊".into(),  enabled: true,  is_nested: true },
        MenuItem { label: "WiFi".into(),       icon: "📶".into(),  enabled: true,  is_nested: false },
        MenuItem { label: "Bluetooth".into(),  icon: "⬡".into(),   enabled: true,  is_nested: false },
        MenuItem { label: "Cellular".into(),   icon: "📡".into(),  enabled: true,  is_nested: false },
        MenuItem { label: "VPN".into(),        icon: "🔒".into(),  enabled: true,  is_nested: false },
        MenuItem { label: "Sleep".into(),      icon: "💤".into(),  enabled: true,  is_nested: false },
        MenuItem { label: "Settings".into(),   icon: "⚙".into(),   enabled: true,  is_nested: false },
    ]
}
