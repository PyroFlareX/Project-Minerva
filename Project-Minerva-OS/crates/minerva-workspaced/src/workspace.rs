use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

// =============================================================================
// workspace.toml schema — /data/workspaces/<name>/workspace.toml
// =============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceToml {
    pub workspace: WorkspaceMeta,
    #[serde(default, rename = "app")]
    pub apps: Vec<AppEntry>,
    #[serde(default)]
    pub env: std::collections::HashMap<String, String>,
    #[serde(default)]
    pub startup: Option<StartupConfig>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceMeta {
    pub name: String,
    #[serde(default)]
    pub icon: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub notes: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppEntry {
    pub command: String,
    #[serde(default)]
    pub args: Vec<String>,
    /// Role hint: "primary" | "secondary" | etc. Informational only.
    #[serde(default)]
    pub role: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StartupConfig {
    /// Optional shell script to run before apps are launched.
    pub script: Option<String>,
}

impl WorkspaceToml {
    pub fn load(workspace_dir: &Path) -> Result<Self> {
        let path = workspace_dir.join("workspace.toml");
        let content = std::fs::read_to_string(&path)?;
        Ok(toml::from_str(&content)?)
    }

    pub fn save(&self, workspace_dir: &Path) -> Result<()> {
        std::fs::create_dir_all(workspace_dir)?;
        let path = workspace_dir.join("workspace.toml");
        std::fs::write(path, toml::to_string_pretty(self)?)?;
        Ok(())
    }
}

// =============================================================================
// Runtime workspace state — tracked by minerva-workspaced in memory
// =============================================================================

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WorkspaceStatus {
    /// Apps are running.
    Active,
    /// Apps are backgrounded (Wayland surfaces hidden).
    Background,
    /// Apps have been closed; workspace definition still on disk.
    Inactive,
}

#[derive(Debug, Clone)]
pub struct Workspace {
    pub name: String,
    pub dir: PathBuf,
    pub config: WorkspaceToml,
    pub status: WorkspaceStatus,
}

impl Workspace {
    pub fn load(name: &str) -> Result<Self> {
        let dir = PathBuf::from("/data/workspaces").join(name);
        let config = WorkspaceToml::load(&dir)?;
        Ok(Self {
            name: name.to_string(),
            dir,
            config,
            status: WorkspaceStatus::Inactive,
        })
    }

    pub fn list_all() -> Result<Vec<String>> {
        let base = Path::new("/data/workspaces");
        if !base.exists() {
            return Ok(vec![]);
        }
        let mut names = vec![];
        for entry in std::fs::read_dir(base)? {
            let entry = entry?;
            let path = entry.path();
            if path.is_dir() && path.join("workspace.toml").exists() {
                if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                    names.push(name.to_string());
                }
            }
        }
        names.sort();
        Ok(names)
    }
}

// =============================================================================
// IPC message types — Unix socket between compositor/shell and workspaced
// =============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum WorkspaceCommand {
    /// List all known workspaces and their status.
    List,
    /// Switch to (or launch) a workspace by name.
    Switch { name: String },
    /// Close the active workspace's apps.
    Close { name: String },
    /// Query the currently active workspace.
    GetActive,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum WorkspaceEvent {
    /// Response to List.
    WorkspaceList { workspaces: Vec<WorkspaceInfo> },
    /// Emitted after a successful switch.
    Switched { name: String },
    /// Emitted after a workspace is closed.
    Closed { name: String },
    /// Response to GetActive.
    ActiveWorkspace { name: Option<String> },
    /// Error response.
    Error { message: String },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceInfo {
    pub name: String,
    pub icon: Option<String>,
    pub tags: Vec<String>,
    pub status: WorkspaceStatusInfo,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WorkspaceStatusInfo {
    Active,
    Background,
    Inactive,
}
