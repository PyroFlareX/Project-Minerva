// =============================================================================
// workspace.rs — Workspace model
//
// A workspace is a named context: which apps are running, their tile layout,
// and per-workspace settings. Loaded from workspace.toml files on the NVMe.
// =============================================================================

use std::path::PathBuf;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceConfig {
    pub name:    String,
    pub layout:  LayoutMode,
    pub tiles:   Vec<TileConfig>,
    pub env:     std::collections::HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum LayoutMode {
    Fullscreen,
    HorizontalSplit,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TileConfig {
    pub app_id:   String,
    pub slot:     TileSlot,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum TileSlot {
    Fullscreen,
    Left,
    Right,
}

// ---------------------------------------------------------------------------
// Runtime workspace state
// ---------------------------------------------------------------------------

#[allow(dead_code)]
#[derive(Debug)]
pub struct Workspace {
    pub config:       WorkspaceConfig,
    pub config_path:  PathBuf,
    /// IDs of apps currently running in this workspace.
    pub running_apps: Vec<String>,
    /// Index of the focused tile (0 = fullscreen or left, 1 = right).
    pub focused_tile: usize,
}

impl Workspace {
    pub fn from_config(config: WorkspaceConfig, path: PathBuf) -> Self {
        Self {
            config,
            config_path: path,
            running_apps: Vec::new(),
            focused_tile: 0,
        }
    }

    /// Cycle focus between tiles (L1 / R1).
    pub fn cycle_focus(&mut self) {
        if self.config.layout == LayoutMode::HorizontalSplit {
            self.focused_tile = 1 - self.focused_tile;
        }
    }

    /// Returns the app ID occupying the focused tile, if any.
    #[allow(dead_code)]
    pub fn focused_app(&self) -> Option<&str> {
        let tile = self.config.tiles.get(self.focused_tile)?;
        Some(&tile.app_id)
    }
}

// ---------------------------------------------------------------------------
// WorkspaceManager
// ---------------------------------------------------------------------------

pub struct WorkspaceManager {
    pub workspaces:      Vec<Workspace>,
    pub active_index:    usize,
}

impl WorkspaceManager {
    pub fn new() -> Self {
        // Start with a single default workspace
        let default = WorkspaceConfig {
            name:   "Default".into(),
            layout: LayoutMode::Fullscreen,
            tiles:  Vec::new(),
            env:    Default::default(),
        };
        Self {
            workspaces:   vec![Workspace::from_config(default, PathBuf::new())],
            active_index: 0,
        }
    }

    #[allow(dead_code)]
    pub fn active(&self) -> &Workspace {
        &self.workspaces[self.active_index]
    }

    pub fn active_mut(&mut self) -> &mut Workspace {
        &mut self.workspaces[self.active_index]
    }

    /// Load a workspace from a TOML file.
    #[allow(dead_code)]
    pub fn load_from_file(&mut self, path: PathBuf) -> anyhow::Result<()> {
        let text = std::fs::read_to_string(&path)?;
        let config: WorkspaceConfig = toml::from_str(&text)?;
        self.workspaces.push(Workspace::from_config(config, path));
        Ok(())
    }
}
