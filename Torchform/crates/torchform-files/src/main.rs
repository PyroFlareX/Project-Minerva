// =============================================================================
// torchform-files — Standalone Torchform file browser
//
// Runs as a Wayland client (launched by torchform-shell) or as a standalone
// window for desktop development.  Arrow keys navigate; Enter enters a dir;
// Backspace / left arrow navigates to parent; Escape closes.
// =============================================================================

slint::include_modules!();

use std::{cell::RefCell, rc::Rc};
use anyhow::Result;
use tracing::info;

fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("torchform_files=info".parse().unwrap()),
        )
        .init();

    info!("torchform-files starting");

    let path = Rc::new(RefCell::new("/home".to_owned()));
    let focused = Rc::new(RefCell::new(0usize));

    let win = FilesWindow::new()?;

    // Initial load
    let initial_path = path.borrow().clone();
    win.set_current_path(initial_path.clone().into());
    win.set_entries(read_dir_model(&initial_path));
    win.set_focused_row(0);

    // --- navigate into a directory ------------------------------------------
    win.on_navigate({
        let win2 = win.as_weak();
        let path2 = path.clone();
        let focused2 = focused.clone();
        move |name| {
            let candidate = format!("{}/{}", path2.borrow().trim_end_matches('/'), name);
            if std::path::Path::new(&candidate).is_dir() {
                *path2.borrow_mut() = candidate.clone();
                *focused2.borrow_mut() = 0;
                if let Some(w) = win2.upgrade() {
                    w.set_current_path(candidate.clone().into());
                    w.set_entries(read_dir_model(&candidate));
                    w.set_focused_row(0);
                }
            }
        }
    });

    // --- navigate to parent -------------------------------------------------
    win.on_navigate_parent({
        let win2 = win.as_weak();
        let path2 = path.clone();
        let focused2 = focused.clone();
        move || {
            let parent = std::path::Path::new(&*path2.borrow())
                .parent()
                .map(|p| p.to_string_lossy().into_owned())
                .unwrap_or_else(|| "/".into());
            *path2.borrow_mut() = parent.clone();
            *focused2.borrow_mut() = 0;
            if let Some(w) = win2.upgrade() {
                w.set_current_path(parent.clone().into());
                w.set_entries(read_dir_model(&parent));
                w.set_focused_row(0);
            }
        }
    });

    // --- close --------------------------------------------------------------
    win.on_close_requested({
        let win2 = win.as_weak();
        move || { win2.upgrade().map(|w| w.hide().ok()); }
    });

    // --- nav up -------------------------------------------------------------
    win.on_action_nav_up({
        let win2 = win.as_weak();
        let focused2 = focused.clone();
        move || {
            if let Some(w) = win2.upgrade() {
                let cur = *focused2.borrow();
                let next = if cur > 0 { cur - 1 } else { 0 };
                *focused2.borrow_mut() = next;
                w.set_focused_row(next as i32);
            }
        }
    });

    // --- nav down -----------------------------------------------------------
    win.on_action_nav_down({
        let win2 = win.as_weak();
        let focused2 = focused.clone();
        let path2 = path.clone();
        move || {
            if let Some(w) = win2.upgrade() {
                let dir_entries = list_dir(&path2.borrow());
                let max = dir_entries.len().saturating_sub(1);
                let cur = *focused2.borrow();
                let next = (cur + 1).min(max);
                *focused2.borrow_mut() = next;
                w.set_focused_row(next as i32);
            }
        }
    });

    // --- confirm (enter directory) ------------------------------------------
    win.on_action_confirm({
        let win2 = win.as_weak();
        let focused2 = focused.clone();
        let path2 = path.clone();
        move || {
            let idx = *focused2.borrow();
            let entries = list_dir(&path2.borrow());
            if let Some((name, is_dir)) = entries.get(idx) {
                if *is_dir {
                    let candidate = format!("{}/{}", path2.borrow().trim_end_matches('/'), name);
                    *path2.borrow_mut() = candidate.clone();
                    *focused2.borrow_mut() = 0;
                    if let Some(w) = win2.upgrade() {
                        w.set_current_path(candidate.clone().into());
                        w.set_entries(read_dir_model(&candidate));
                        w.set_focused_row(0);
                    }
                }
                // Files: no-op for now (future: open in editor via torchform-run)
            }
        }
    });

    // --- cancel (close) -----------------------------------------------------
    win.on_action_cancel({
        let win2 = win.as_weak();
        move || { win2.upgrade().map(|w| w.hide().ok()); }
    });

    win.run()?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Filesystem helpers
// ---------------------------------------------------------------------------

fn list_dir(path: &str) -> Vec<(String, bool)> {
    match std::fs::read_dir(path) {
        Ok(rd) => {
            let mut items: Vec<(bool, String)> = rd
                .filter_map(|e| e.ok())
                .map(|e| {
                    let is_dir = e.metadata().map_or(false, |m| m.is_dir());
                    (is_dir, e.file_name().to_string_lossy().into_owned())
                })
                .collect();
            items.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(&b.1)));
            items.into_iter().map(|(d, n)| (n, d)).collect()
        }
        Err(e) => {
            tracing::warn!("read_dir({path}): {e}");
            Vec::new()
        }
    }
}

fn read_dir_model(path: &str) -> slint::ModelRc<FileEntry> {
    let items = list_dir(path);
    let entries: Vec<FileEntry> = items.into_iter().map(|(name, is_dir)| {
        if is_dir {
            FileEntry {
                icon: "📁".into(),
                name: name.into(),
                kind: "dir".into(),
                size: "—".into(),
            }
        } else {
            let size = std::fs::metadata(format!("{path}/{name}"))
                .map(|m| format_size(m.len()))
                .unwrap_or_else(|_| "—".into());
            FileEntry {
                icon: file_icon(&name),
                name: name.into(),
                kind: "file".into(),
                size: size.into(),
            }
        }
    }).collect();
    Rc::new(slint::VecModel::from(entries)).into()
}

fn file_icon(name: &str) -> slint::SharedString {
    match name.rsplit('.').next().unwrap_or("") {
        "rs" | "toml" | "json" | "yaml" | "yml" | "md" => "📝",
        "png" | "jpg" | "jpeg" | "gif" | "webp"        => "🖼",
        "mp3" | "ogg" | "flac" | "wav"                 => "🎵",
        "mp4" | "mkv" | "webm" | "mov"                 => "🎬",
        "pdf"                                           => "📄",
        "zip" | "tar" | "gz" | "xz" | "zst"            => "📦",
        _                                               => "📄",
    }.into()
}

fn format_size(bytes: u64) -> String {
    const KB: u64 = 1024;
    const MB: u64 = KB * 1024;
    const GB: u64 = MB * 1024;
    if bytes >= GB      { format!("{:.1} GB", bytes as f64 / GB as f64) }
    else if bytes >= MB { format!("{:.1} MB", bytes as f64 / MB as f64) }
    else if bytes >= KB { format!("{:.1} KB", bytes as f64 / KB as f64) }
    else                { format!("{} B", bytes) }
}
