// =============================================================================
// palette.rs — Command palette state + search
//
// Holds the full command registry and provides substring search filtering.
//
// NOTE: `PaletteEntry` is a native Rust type. main.rs converts it to the
// Slint-generated `CommandEntry` when pushing to the UI model.
// =============================================================================

/// A single command entry (Rust-side representation).
#[derive(Debug, Clone)]
pub struct PaletteEntry {
    pub id:          String,
    pub label:       String,
    pub description: String,
    pub category:    String,
    pub icon:        String,
    pub shortcut:    String,
}

pub struct PaletteState {
    pub visible:       bool,
    pub query:         String,
    pub focused_index: usize,
    pub filtered:      Vec<PaletteEntry>,

    registry: Vec<PaletteEntry>,
}

impl PaletteState {
    pub fn new() -> Self {
        let registry = default_commands();
        let filtered = registry.clone();
        Self {
            visible: false,
            query:   String::new(),
            focused_index: 0,
            filtered,
            registry,
        }
    }

    pub fn open(&mut self) {
        self.query         = String::new();
        self.focused_index = 0;
        self.filtered      = self.registry.clone();
        self.visible       = true;
    }

    pub fn close(&mut self) {
        self.visible = false;
    }

    /// Update the search query and re-filter the registry.
    pub fn set_query(&mut self, q: &str) {
        self.query         = q.to_lowercase();
        self.focused_index = 0;
        self.filtered      = self
            .registry
            .iter()
            .filter(|e| {
                e.label.to_lowercase().contains(&self.query)
                    || e.description.to_lowercase().contains(&self.query)
                    || e.category.to_lowercase().contains(&self.query)
            })
            .cloned()
            .collect();
    }

    pub fn append_char(&mut self, ch: char) {
        let mut q = self.query.clone();
        q.push(ch);
        self.set_query(&q);
    }

    pub fn backspace(&mut self) {
        let mut q = self.query.clone();
        q.pop();
        self.set_query(&q);
    }

    pub fn move_up(&mut self) {
        if !self.filtered.is_empty() && self.focused_index > 0 {
            self.focused_index -= 1;
        }
    }

    pub fn move_down(&mut self) {
        if self.focused_index + 1 < self.filtered.len() {
            self.focused_index += 1;
        }
    }

    /// Returns the command ID of the currently focused entry.
    pub fn focused_id(&self) -> Option<&str> {
        self.filtered
            .get(self.focused_index)
            .map(|e| e.id.as_str())
    }

    /// Register additional commands (e.g. from loaded apps).
    #[allow(dead_code)]
    pub fn register(&mut self, cmds: impl IntoIterator<Item = PaletteEntry>) {
        self.registry.extend(cmds);
    }
}

// ---------------------------------------------------------------------------
// Built-in command registry
// ---------------------------------------------------------------------------

fn default_commands() -> Vec<PaletteEntry> {
    vec![
        PaletteEntry {
            id:          "app.settings".into(),
            label:       "Open Settings".into(),
            description: "System configuration — display, audio, network, security".into(),
            category:    "App".into(),
            icon:        "⚙".into(),
            shortcut:    "".into(),
        },
        PaletteEntry {
            id:          "app.files".into(),
            label:       "File Manager".into(),
            description: "Browse and manage files on NVMe".into(),
            category:    "App".into(),
            icon:        "📁".into(),
            shortcut:    "".into(),
        },
        PaletteEntry {
            id:          "app.editor".into(),
            label:       "Text Editor".into(),
            description: "Code and text editing".into(),
            category:    "App".into(),
            icon:        "✏".into(),
            shortcut:    "".into(),
        },
        PaletteEntry {
            id:          "app.browser".into(),
            label:       "Web Browser".into(),
            description: "Browse the web, optionally via Tor".into(),
            category:    "App".into(),
            icon:        "🌐".into(),
            shortcut:    "".into(),
        },
        PaletteEntry {
            id:          "app.network".into(),
            label:       "Network Manager".into(),
            description: "WiFi, cellular, VPN, Bluetooth".into(),
            category:    "App".into(),
            icon:        "📶".into(),
            shortcut:    "".into(),
        },
        PaletteEntry {
            id:          "app.gpio".into(),
            label:       "GPIO Manager".into(),
            description: "View and control GPIO pins, I2C/SPI scanner".into(),
            category:    "App".into(),
            icon:        "⬡".into(),
            shortcut:    "".into(),
        },
        PaletteEntry {
            id:          "sys.brightness.up".into(),
            label:       "Brightness Up".into(),
            description: "Increase display brightness".into(),
            category:    "System".into(),
            icon:        "☀".into(),
            shortcut:    "L2 → ☀↑".into(),
        },
        PaletteEntry {
            id:          "sys.brightness.down".into(),
            label:       "Brightness Down".into(),
            description: "Decrease display brightness".into(),
            category:    "System".into(),
            icon:        "🌙".into(),
            shortcut:    "L2 → ☀↓".into(),
        },
        PaletteEntry {
            id:          "sys.volume.up".into(),
            label:       "Volume Up".into(),
            description: "Increase system volume".into(),
            category:    "System".into(),
            icon:        "🔊".into(),
            shortcut:    "L2 → 🔊↑".into(),
        },
        PaletteEntry {
            id:          "sys.volume.down".into(),
            label:       "Volume Down".into(),
            description: "Decrease system volume".into(),
            category:    "System".into(),
            icon:        "🔉".into(),
            shortcut:    "L2 → 🔊↓".into(),
        },
        PaletteEntry {
            id:          "sys.wifi.toggle".into(),
            label:       "Toggle WiFi".into(),
            description: "Enable or disable WiFi".into(),
            category:    "System".into(),
            icon:        "📶".into(),
            shortcut:    "L2+R2 → 📶".into(),
        },
        PaletteEntry {
            id:          "sys.bt.toggle".into(),
            label:       "Toggle Bluetooth".into(),
            description: "Enable or disable Bluetooth".into(),
            category:    "System".into(),
            icon:        "⬡".into(),
            shortcut:    "L2+R2 → ⬡".into(),
        },
        PaletteEntry {
            id:          "sys.sleep".into(),
            label:       "Sleep".into(),
            description: "Suspend the device".into(),
            category:    "System".into(),
            icon:        "💤".into(),
            shortcut:    "".into(),
        },
        PaletteEntry {
            id:          "sys.split.toggle".into(),
            label:       "Toggle Split Screen".into(),
            description: "Switch between fullscreen and horizontal split".into(),
            category:    "System".into(),
            icon:        "◫".into(),
            shortcut:    "".into(),
        },
    ]
}
