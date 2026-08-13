// =============================================================================
// dotfiles.rs — Dotfile discovery scanner
//
// Walks a directory (typically ~/.config/) up to max_depth=3, finds config
// files by extension, and returns a sorted Vec<DotfileEntry>.
//
// No external walkdir dep — uses std::fs::read_dir recursively.
// =============================================================================

use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DotfileFormat {
    Toml,
    Json,
    Yaml,
    Ini,
    Conf,
    Sh,
    Unknown,
}

impl DotfileFormat {
    pub fn from_extension(ext: &str) -> Self {
        match ext.to_ascii_lowercase().as_str() {
            "toml"              => Self::Toml,
            "json"              => Self::Json,
            "yaml" | "yml"      => Self::Yaml,
            "ini"               => Self::Ini,
            "conf" | "cfg"      => Self::Conf,
            "sh" | "bash" | "zsh" | "profile" | "bashrc" | "zshrc" => Self::Sh,
            _                   => Self::Unknown,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Toml    => "toml",
            Self::Json    => "json",
            Self::Yaml    => "yaml",
            Self::Ini     => "ini",
            Self::Conf    => "conf",
            Self::Sh      => "sh",
            Self::Unknown => "unknown",
        }
    }

    /// True if the format has enough known structure to be parsed/edited.
    pub fn is_editable(&self) -> bool {
        matches!(self, Self::Toml | Self::Json | Self::Yaml | Self::Ini | Self::Conf)
    }
}

#[derive(Debug, Clone)]
pub struct DotfileEntry {
    pub path:       PathBuf,
    pub format:     DotfileFormat,
    pub size_bytes: u64,
    pub editable:   bool,
}

impl DotfileEntry {
    /// Serialisable path string (for storage in DotfileCacheEntry).
    pub fn path_string(&self) -> String {
        self.path.display().to_string()
    }
}

/// Walk `root` up to `max_depth` levels deep.  Returns all files whose
/// extension matches a known config format, sorted by path.
pub fn scan_config_dir(root: &Path) -> Vec<DotfileEntry> {
    let mut entries = Vec::new();
    walk_dir(root, 0, 3, &mut entries);
    entries.sort_by(|a, b| a.path.cmp(&b.path));
    entries
}

fn walk_dir(dir: &Path, depth: usize, max_depth: usize, out: &mut Vec<DotfileEntry>) {
    if depth > max_depth { return; }

    let rd = match std::fs::read_dir(dir) {
        Ok(rd) => rd,
        Err(_) => return,
    };

    for entry in rd.flatten() {
        let path = entry.path();
        let ft = match entry.file_type() {
            Ok(ft) => ft,
            Err(_) => continue,
        };

        if ft.is_dir() {
            walk_dir(&path, depth + 1, max_depth, out);
        } else if ft.is_file() {
            if let Some(entry) = classify_file(&path) {
                out.push(entry);
            }
        }
    }
}


fn classify_file(path: &Path) -> Option<DotfileEntry> {
    // Match by extension or by filename (dotfiles like .bashrc)
    let format = if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        DotfileFormat::from_extension(ext)
    } else {
        // Extensionless dotfiles: .bashrc, .zshrc, .profile, etc.
        let name = path.file_name().and_then(|n| n.to_str())?;
        let base = name.trim_start_matches('.');
        DotfileFormat::from_extension(base)
    };

    // Skip truly unknown binary files
    if format == DotfileFormat::Unknown {
        return None;
    }

    let size_bytes = std::fs::metadata(path).map(|m| m.len()).unwrap_or(0);
    let editable = format.is_editable();

    Some(DotfileEntry { path: path.to_owned(), format, size_bytes, editable })
}

// ---------------------------------------------------------------------------
// Convert scan results to cache entries (for TorchformConfig storage)
// ---------------------------------------------------------------------------

use crate::config::DotfileCacheEntry;

pub fn to_cache_entries(entries: &[DotfileEntry]) -> Vec<DotfileCacheEntry> {
    entries.iter().map(|e| DotfileCacheEntry {
        path:       e.path_string(),
        format:     e.format.as_str().to_owned(),
        size_bytes: e.size_bytes,
        editable:   e.editable,
    }).collect()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn format_from_extension() {
        assert_eq!(DotfileFormat::from_extension("toml"), DotfileFormat::Toml);
        assert_eq!(DotfileFormat::from_extension("YAML"), DotfileFormat::Yaml);
        assert_eq!(DotfileFormat::from_extension("yml"),  DotfileFormat::Yaml);
        assert_eq!(DotfileFormat::from_extension("ini"),  DotfileFormat::Ini);
        assert_eq!(DotfileFormat::from_extension("sh"),   DotfileFormat::Sh);
        assert_eq!(DotfileFormat::from_extension("exe"),  DotfileFormat::Unknown);
    }

    #[test]
    fn editable_formats() {
        assert!(DotfileFormat::Toml.is_editable());
        assert!(DotfileFormat::Json.is_editable());
        assert!(DotfileFormat::Yaml.is_editable());
        assert!(!DotfileFormat::Sh.is_editable());
        assert!(!DotfileFormat::Unknown.is_editable());
    }

    #[test]
    fn scan_temp_dir() {
        use std::fs;
        let tmp = std::env::temp_dir().join("torchform_dotfile_test");
        let _ = fs::create_dir_all(&tmp);
        fs::write(tmp.join("config.toml"), "[section]\nkey = 1").unwrap();
        fs::write(tmp.join("settings.json"), "{}").unwrap();
        fs::write(tmp.join("README.md"), "# hi").unwrap(); // should be excluded

        let results = scan_config_dir(&tmp);
        let names: Vec<_> = results.iter()
            .map(|e| e.path.file_name().unwrap().to_str().unwrap())
            .collect();
        assert!(names.contains(&"config.toml"));
        assert!(names.contains(&"settings.json"));
        assert!(!names.contains(&"README.md")); // .md is Unknown → excluded

        let _ = fs::remove_dir_all(&tmp);
    }
}
