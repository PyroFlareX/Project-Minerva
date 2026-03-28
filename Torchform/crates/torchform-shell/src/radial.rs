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

    /// Returns the item at the currently focused slot, if any.
    pub fn focused_item(&self) -> Option<&MenuItem> {
        self.items.get(self.focused_index)
    }
}

// ---------------------------------------------------------------------------
// Default system radial items
// ---------------------------------------------------------------------------

pub fn system_radial_items() -> Vec<MenuItem> {
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
