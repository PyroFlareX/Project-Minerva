// =============================================================================
// shell.rs — Torchform shell state machine
//
// The single source of truth for the N3DS-style shell experience, modelled on
// the `S` object + `handleInput()` routing in `torchform-os.html`. It is pure
// Rust with NO Slint dependency, so it is unit-testable in isolation; the
// render layer (`ShellUi` in main.rs) reads this state and pushes it to either
// the emulator window or the standalone shell window.
//
// Routing priority for navigation / confirm / cancel (highest first):
//   1. Radial menu  (L2/R2 hold, stick-steered)   — system overlay
//   2. Command palette                              — search overlay
//   3. Active panel (QuickSettings / Notifications / Switcher)
//   4. Active screen (Lock / Home / App)
// =============================================================================

use std::collections::HashMap;

use torchform_actions::ShellAction;

use crate::audio::SoundCue;
use crate::config::TorchformConfig;
use crate::palette::PaletteState;
use crate::radial::{Direction, MenuLayer, RadialMenuState, system_radial_items};
use crate::settings::{self, SettingsRowData, SettingsSchema};
use crate::workspace::WorkspaceManager;

// ---------------------------------------------------------------------------
// Settings sidebar helpers
// ---------------------------------------------------------------------------

/// Lightweight descriptor for one entry in the sidebar flat list.
/// Used only inside shell.rs to drive navigation logic.
#[derive(Debug, Clone)]
pub struct SidebarEntryData {
    pub is_section: bool,
    pub section_id: String,
}

/// Map a section id to its display group string.
/// Must match the groups in `settings_sidebar_to_slint()` in main.rs.
pub fn section_group(id: &str) -> String {
    match id {
        "display" | "audio" | "input" | "power" | "datetime" | "storage" => "SYSTEM",
        "network" | "bluetooth" | "vpn" | "cellular" | "netmon"          => "CONNECTIVITY",
        "security" | "permissions" | "firewall"                           => "PRIVACY",
        "apps" | "keybinds" | "about" | "sysapps"                        => "DEVICE",
        _                                                                  => "OTHER",
    }.into()
}

// ---------------------------------------------------------------------------
// Apps  (mirrors APPS_DEF / DOCK_IDS in torchform-os.html)
// ---------------------------------------------------------------------------

/// Every app the shell can host. Mirrors `APPS_DEF` in torchform-os.html.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AppId {
    Terminal,
    Browser,
    Files,
    Media,
    Phone,
    Sms,
    Email,
    Settings,
    Sysmon,
    Pkgman,
    Logview,
    Notes,
    Network,
}

impl AppId {
    /// Short id used in models / config (e.g. "terminal").
    pub fn id(self) -> &'static str {
        match self {
            AppId::Terminal => "terminal",
            AppId::Browser  => "browser",
            AppId::Files    => "files",
            AppId::Media    => "media",
            AppId::Phone    => "phone",
            AppId::Sms      => "sms",
            AppId::Email    => "email",
            AppId::Settings => "settings",
            AppId::Sysmon   => "sysmon",
            AppId::Pkgman   => "pkgman",
            AppId::Logview  => "logview",
            AppId::Notes    => "notes",
            AppId::Network  => "network",
        }
    }

    /// Human-readable name shown in the status bar / switcher / home tile.
    pub fn name(self) -> &'static str {
        match self {
            AppId::Terminal => "Terminal",
            AppId::Browser  => "Browser",
            AppId::Files    => "Files",
            AppId::Media    => "Media",
            AppId::Phone    => "Phone",
            AppId::Sms      => "Messages",
            AppId::Email    => "Email",
            AppId::Settings => "Settings",
            AppId::Sysmon   => "Monitor",
            AppId::Pkgman   => "Packages",
            AppId::Logview  => "Logs",
            AppId::Notes    => "Notes",
            AppId::Network  => "Network",
        }
    }

    /// Icon glyph (emoji) for tiles / dock / cards.
    pub fn icon(self) -> &'static str {
        match self {
            AppId::Terminal => "⬛",
            AppId::Browser  => "🌐",
            AppId::Files    => "📁",
            AppId::Media    => "🎵",
            AppId::Phone    => "📞",
            AppId::Sms      => "💬",
            AppId::Email    => "📧",
            AppId::Settings => "⚙️",
            AppId::Sysmon   => "📊",
            AppId::Pkgman   => "📦",
            AppId::Logview  => "📋",
            AppId::Notes    => "📝",
            AppId::Network  => "📶",
        }
    }

    /// Tile background tint (hex string), matching the HTML `APPS_DEF` `bg`.
    pub fn bg(self) -> &'static str {
        match self {
            AppId::Terminal => "#040408",
            AppId::Browser  => "#040810",
            AppId::Files    => "#080600",
            AppId::Media    => "#060408",
            AppId::Phone    => "#040806",
            AppId::Sms      => "#040608",
            AppId::Email    => "#080404",
            AppId::Settings => "#050510",
            AppId::Sysmon   => "#040806",
            AppId::Pkgman   => "#050808",
            AppId::Logview  => "#030308",
            AppId::Notes    => "#080600",
            AppId::Network  => "#040810",
        }
    }


    /// Resolve a palette command id (in either "app.x" or "x" form) to an app.
    pub fn from_command(id: &str) -> Option<AppId> {
        let stem = id.strip_prefix("app.").unwrap_or(id);
        Some(match stem {
            "terminal"                          => AppId::Terminal,
            "browser"                           => AppId::Browser,
            "files" | "file-manager"            => AppId::Files,
            "media" | "media-player"            => AppId::Media,
            "phone"                             => AppId::Phone,
            "sms" | "messages"                  => AppId::Sms,
            "email"                             => AppId::Email,
            "settings"                          => AppId::Settings,
            "sysmon" | "monitor"                => AppId::Sysmon,
            "pkgman" | "packages"               => AppId::Pkgman,
            "logview" | "logs"                  => AppId::Logview,
            "notes"                             => AppId::Notes,
            "network" | "wifi" | "bluetooth"    => AppId::Network,
            _                                   => return None,
        })
    }
}

/// Home-grid apps, in display order (everything not in the dock).
/// Mirrors `APPS_DEF.filter(a => !DOCK_IDS.includes(a.id))`.
pub const HOME_GRID: [AppId; 8] = [
    AppId::Media, AppId::Email, AppId::Settings, AppId::Network,
    AppId::Sysmon, AppId::Pkgman, AppId::Logview, AppId::Notes,
];

/// Dock apps, in display order. Mirrors `DOCK_IDS`.
pub const DOCK: [AppId; 5] = [
    AppId::Terminal, AppId::Browser, AppId::Sms, AppId::Phone, AppId::Files,
];

/// Number of columns in the home grid (matches the HTML CSS grid).
const HOME_COLS: usize = 4;

/// The full focusable home order: grid first, then dock.
fn home_order() -> Vec<AppId> {
    HOME_GRID.iter().chain(DOCK.iter()).copied().collect()
}

// ---------------------------------------------------------------------------
// Screens / panels
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Screen {
    Lock,
    Home,
    App,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Panel {
    QuickSettings,
    Notifications,
    Switcher,
    /// Quick-action overlay — Switch-style home-button hold menu.
    QuickMenu,
}

// ---------------------------------------------------------------------------
// Quick-settings / system config (the runtime toggles, mirrors S.cfg)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct QuickCfg {
    pub vol:      i32,
    pub bright:   i32,
    pub wifi:     bool,
    pub bt:       bool,
    pub dnd:      bool,
    pub airplane: bool,
    pub vpn:      bool,
    pub wifi_net: String,
    pub bt_dev:   String,
}

impl Default for QuickCfg {
    fn default() -> Self {
        Self {
            vol: 70, bright: 85,
            wifi: true, bt: true, dnd: false, airplane: false, vpn: true,
            wifi_net: "HomeNet-5G".into(),
            bt_dev:   "QCY H3 Pro".into(),
        }
    }
}

/// The 8 Quick-Settings tiles, in grid order. `key` drives `qs_tile()`.
pub const QS_KEYS: [&str; 8] =
    ["wifi", "bt", "dnd", "airplane", "_ss", "_lock", "_ws0", "_ws1"];

// ---------------------------------------------------------------------------
// Notifications + transient banners
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct Notif {
    pub app:      String,
    pub icon:     String,
    pub title:    String,
    pub body:     String,
    pub time:     String,
    pub src_app:  Option<AppId>,
}

/// A single note entry.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Note {
    pub id:      usize,
    pub title:   String,
    pub body:    String,
    pub time:    String,   // display timestamp, e.g. "Just now"
}

#[derive(Debug, Clone, Default)]
pub struct WifiNet {
    pub ssid:      String,
    pub signal:    i32,   // 0–100
    pub secured:   bool,
    pub connected: bool,
}

#[derive(Debug, Clone, Default)]
pub struct NetworkState {
    pub wifi_list: Vec<WifiNet>,
}

#[derive(Debug, Clone, Default)]
pub struct LogEntry {
    pub level:  String,   // "info"|"warn"|"error"|"debug"
    pub source: String,
    pub text:   String,
    pub time:   String,
}

#[derive(Debug, Clone, Default)]
pub struct SysmonData {
    pub cpu_pct:      f32,
    pub ram_pct:      f32,
    pub gpu_pct:      f32,
    pub temp_c:       f32,
    pub ram_used_mb:  i32,
    pub ram_total_mb: i32,
    pub cpu_name:     String,
    pub core_pcts:    Vec<f32>,
    pub proc_names:   Vec<String>,
    pub proc_cpus:    Vec<f32>,
    pub proc_mems:    Vec<i32>,
}

/// A transient toast banner (mirrors `showBanner`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Banner {
    pub icon:  String,
    pub app:   String,
    pub title: String,
    pub body:  String,
}

fn seed_notifs() -> Vec<Notif> {
    vec![
        Notif { app: "SMS".into(),    icon: "💬".into(), title: "Alice Chen".into(),          body: "Are you free tonight?".into(),               time: "2m".into(), src_app: Some(AppId::Sms) },
        Notif { app: "EMAIL".into(),  icon: "📧".into(), title: "CI: build passed".into(),     body: "main · 47 tests passed · deployed".into(),   time: "8m".into(), src_app: Some(AppId::Email) },
        Notif { app: "SYSTEM".into(), icon: "⚙️".into(), title: "System update ready".into(),  body: "Torchform OS 0.3.1 available".into(),         time: "1h".into(), src_app: Some(AppId::Settings) },
        Notif { app: "SMS".into(),    icon: "💬".into(), title: "Mom".into(),                  body: "Call me when you get a chance".into(),        time: "2h".into(), src_app: Some(AppId::Sms) },
    ]
}

// ---------------------------------------------------------------------------
// Side effects — things handle() cannot do itself (I/O, audio, spawning)
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub enum Effect {
    /// Play a UI sound cue.
    Sound(SoundCue),
    /// Attempt to launch an external Wayland binary for this command id
    /// (only for commands with no embedded app widget).
    LaunchExternal(String),
    /// Show a transient toast banner.
    ShowBanner(Banner),
    /// Persist the config to the user config path.
    SaveConfig,
    /// Suspend the device.
    Suspend,
    /// Persist the notes list to disk.
    SaveNotes(Vec<Note>),
    /// Send SIGTERM to a launched external process.
    KillApp(u32),
}

// ---------------------------------------------------------------------------
// Text target — which field currently receives OSK / LowerKeyPress input
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TextTarget {
    None,
    Palette,
    Notes,
}

// ---------------------------------------------------------------------------
// Konami code easter egg (mirrors KONAMI on the lock screen)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Kon { Up, Down, Left, Right, B, A }

const KONAMI: [Kon; 10] = [
    Kon::Up, Kon::Up, Kon::Down, Kon::Down,
    Kon::Left, Kon::Right, Kon::Left, Kon::Right,
    Kon::B, Kon::A,
];

// ---------------------------------------------------------------------------
// Shell state
// ---------------------------------------------------------------------------

pub struct Shell {
    pub config: TorchformConfig,

    pub screen:   Screen,
    pub panel:    Option<Panel>,
    pub app_id:   Option<AppId>,
    pub run_apps: Vec<AppId>,
    pub pid_map:  HashMap<AppId, u32>,   // app → OS pid for externally-launched apps

    pub home_focus:   usize,
    pub qs_focus:        usize,
    pub qs_slider_focus: i32,   // -1 = on tiles; 0 = vol slider; 1 = bright slider
    pub nf_focus:        usize,
    pub sw_focus:        usize,
    pub qm_focus:        usize,
    pub pin_len:      usize,

    // Settings two-pane state
    pub settings_sidebar_focus: usize,   // index into sidebar entries (including group headers)
    pub settings_sidebar_active: bool,   // true = left pane has d-pad focus

    pub cfg:       QuickCfg,
    pub notifs:    Vec<Notif>,

    // Overlays (coexist with the screen state).
    pub radial:  RadialMenuState,
    pub palette: PaletteState,
    pub radial_stick_active: bool,
    pub stick_x: f32,
    pub stick_y: f32,

    pub workspaces: WorkspaceManager,

    // Per-app focused row + the file browser path + settings rows.
    pub app_rows:        HashMap<AppId, i32>,
    pub files_path:      String,
    pub settings_rows:   Vec<SettingsRowData>,
    pub settings_schema: SettingsSchema,

    // Network state (refreshed on demand and on app open)
    pub network: NetworkState,

    // Sysmon live data (refreshed by a 2s timer in main.rs)
    pub sysmon: SysmonData,

    // Logview state
    pub log_lines:      Vec<LogEntry>,
    pub log_show_info:  bool,
    pub log_show_warn:  bool,
    pub log_show_error: bool,
    pub log_show_debug: bool,
    pub log_tail:       bool,

    // Notes app state
    pub notes_list:     Vec<Note>,
    pub notes_editing:  bool,
    pub notes_edit_idx: Option<usize>,  // None = new note
    pub notes_edit_title: String,
    pub notes_edit_body:  String,
    pub notes_focus_field: usize,       // 0 = title, 1 = body

    konami_idx: usize,
}

impl Shell {
    pub fn new(config: TorchformConfig) -> Self {
        let schema = SettingsSchema::load();
        let settings_rows = settings::make_settings_entries(&schema, &config);
        let cfg = QuickCfg {
            vol:    config.general.volume.map(|v| v as i32).unwrap_or(70),
            bright: config.general.brightness.map(|b| b as i32).unwrap_or(85),
            ..QuickCfg::default()
        };
        Self {
            config,
            screen: Screen::Lock,
            panel:  None,
            app_id: None,
            run_apps: Vec::new(),
            pid_map:  HashMap::new(),
            home_focus:   0,
            qs_focus:        0,
            qs_slider_focus: -1,
            nf_focus:     0,
            sw_focus:     0,
            qm_focus:     0,
            pin_len:      0,
            settings_sidebar_focus:  0,
            settings_sidebar_active: true,
            cfg,
            notifs: seed_notifs(),
            radial:  RadialMenuState::new(),
            palette: PaletteState::new(),
            radial_stick_active: false,
            stick_x: 0.0,
            stick_y: 0.0,
            workspaces: WorkspaceManager::new(),
            app_rows: HashMap::new(),
            files_path: "/home".into(),
            settings_rows,
            settings_schema: schema,
            network: NetworkState::default(),
            sysmon: SysmonData::default(),
            log_lines:      Vec::new(),
            log_show_info:  true,
            log_show_warn:  true,
            log_show_error: true,
            log_show_debug: false,
            log_tail:       true,
            notes_list:        Vec::new(),
            notes_editing:     false,
            notes_edit_idx:    None,
            notes_edit_title:  String::new(),
            notes_edit_body:   String::new(),
            notes_focus_field: 0,
            konami_idx: 0,
        }
    }

    pub fn workspace_index(&self) -> usize {
        self.workspaces.active_index
    }

    /// The focusable home order (grid then dock).
    pub fn home_order(&self) -> Vec<AppId> {
        home_order()
    }

    /// Which text field should currently receive OSK / voice input.
    pub fn active_text_target(&self) -> TextTarget {
        if self.palette.visible {
            return TextTarget::Palette;
        }
        if self.screen == Screen::App && self.app_id == Some(AppId::Notes) && self.notes_editing {
            return TextTarget::Notes;
        }
        TextTarget::None
    }

    pub fn rebuild_settings(&mut self) {
        self.settings_rows = settings::make_settings_entries(&self.settings_schema, &self.config);
    }

    /// Index of the first non-group-header sidebar entry (the first actual section).
    fn first_sidebar_section(&self) -> usize {
        self.settings_schema.sections
            .iter()
            .enumerate()
            .find_map(|(i, _)| {
                // Build the same sidebar list the Slint UI sees: group headers interleaved.
                // The first entry with a non-empty id is a real section.
                let flat = self.sidebar_entries_flat();
                flat.iter().position(|e: &SidebarEntryData| e.is_section && i < flat.len())
            })
            .unwrap_or(0)
    }

    /// Move sidebar focus up, skipping group-header rows.
    fn sidebar_nav_up(&mut self) {
        let flat = self.sidebar_entries_flat();
        let mut i = self.settings_sidebar_focus;
        loop {
            if i == 0 { break; }
            i -= 1;
            if flat[i].is_section { self.settings_sidebar_focus = i; break; }
        }
    }

    /// Move sidebar focus down, skipping group-header rows.
    fn sidebar_nav_down(&mut self) {
        let flat = self.sidebar_entries_flat();
        let max = flat.len().saturating_sub(1);
        let mut i = self.settings_sidebar_focus;
        loop {
            if i >= max { break; }
            i += 1;
            if flat[i].is_section { self.settings_sidebar_focus = i; break; }
        }
    }

    /// The section id (and row pane data) for the currently focused sidebar entry.
    pub fn active_section_id(&self) -> Option<String> {
        let flat = self.sidebar_entries_flat();
        flat.get(self.settings_sidebar_focus)
            .filter(|e| e.is_section)
            .map(|e| e.section_id.clone())
    }

    /// Flat list of sidebar entries in display order, including group-header rows.
    /// This mirrors what `settings_sidebar_to_slint()` produces in main.rs.
    pub fn sidebar_entries_flat(&self) -> Vec<SidebarEntryData> {
        let mut out = Vec::new();
        let mut last_group = String::new();
        for sec in self.settings_schema.sections.iter() {
            let group = section_group(&sec.id);
            if group != last_group {
                out.push(SidebarEntryData { is_section: false, section_id: String::new() });
                last_group = group;
            }
            out.push(SidebarEntryData { is_section: true, section_id: sec.id.clone() });
        }
        out
    }

    fn row(&self, app: AppId) -> i32 {
        *self.app_rows.get(&app).unwrap_or(&0)
    }

    fn set_row(&mut self, app: AppId, row: i32) {
        self.app_rows.insert(app, row);
    }

    // -----------------------------------------------------------------------
    // Navigation helpers (app launching, panels, etc.)
    // -----------------------------------------------------------------------

    /// Launch (or focus) an app and switch to the App screen.
    pub fn launch(&mut self, app: AppId) {
        if !self.run_apps.contains(&app) {
            self.run_apps.push(app);
        }
        self.app_id = Some(app);
        self.screen = Screen::App;
        self.panel  = None;
        self.app_rows.entry(app).or_insert(0);
        if app == AppId::Settings {
            // Start in the sidebar, focused on the first section.
            self.settings_sidebar_active = true;
            self.settings_sidebar_focus  = self.first_sidebar_section();
            self.set_row(AppId::Settings, 0);
        }
        if app == AppId::Files {
            self.files_path = "/home".into();
            self.set_row(AppId::Files, 0);
        }
    }

    pub fn go_home(&mut self) {
        self.screen = Screen::Home;
        self.panel  = None;
    }

    fn resume_app(&mut self, app: AppId) {
        self.app_id = Some(app);
        self.screen = Screen::App;
        self.panel  = None;
    }

    fn kill_app(&mut self, app: AppId) -> Vec<Effect> {
        let mut fx = vec![];
        if let Some(pid) = self.pid_map.remove(&app) {
            fx.push(Effect::KillApp(pid));
        }
        self.run_apps.retain(|a| *a != app);
        if self.app_id == Some(app) {
            self.app_id = self.run_apps.last().copied();
            self.screen = if self.app_id.is_some() { Screen::App } else { Screen::Home };
        }
        if self.sw_focus >= self.run_apps.len() {
            self.sw_focus = self.run_apps.len().saturating_sub(1);
        }
        fx
    }

    /// Resume the running app at switcher index `i` (touch / direct).
    pub fn switcher_activate(&mut self, i: usize) {
        if let Some(app) = self.run_apps.get(i).copied() {
            self.sw_focus = i;
            self.resume_app(app);
        }
    }

    /// Close the running app at switcher index `i` (touch / direct).
    pub fn switcher_close(&mut self, i: usize) -> Vec<Effect> {
        if let Some(app) = self.run_apps.get(i).copied() {
            self.sw_focus = i;
            return self.kill_app(app);
        }
        vec![]
    }

    fn toggle_panel(&mut self, p: Panel) {
        self.panel = if self.panel == Some(p) { None } else { Some(p) };
        match self.panel {
            Some(Panel::QuickSettings) => { self.qs_focus = 0; self.qs_slider_focus = -1; }
            Some(Panel::Notifications) => self.nf_focus = 0,
            Some(Panel::Switcher)      => self.sw_focus = 0,
            Some(Panel::QuickMenu)     => self.qm_focus = 0,
            None => {}
        }
    }

    // -----------------------------------------------------------------------
    // Quick-settings tile activation (mirrors qsTile)
    // -----------------------------------------------------------------------

    fn qs_tile(&mut self, key: &str, fx: &mut Vec<Effect>) {
        match key {
            "wifi"     => self.cfg.wifi = !self.cfg.wifi,
            "bt"       => self.cfg.bt = !self.cfg.bt,
            "dnd"      => self.cfg.dnd = !self.cfg.dnd,
            "airplane" => self.cfg.airplane = !self.cfg.airplane,
            "_lock"    => { self.panel = None; self.screen = Screen::Lock; self.pin_len = 0; }
            "_ws0"     => { self.workspaces.active_index = 0; }
            "_ws1"     => { self.workspaces.active_index = 1.min(self.workspaces.workspaces.len() - 1); }
            "_ss"      => fx.push(Effect::ShowBanner(Banner {
                icon:  "📷".into(),
                app:   "SCREENSHOT".into(),
                title: "Screenshot saved".into(),
                body:  "Saved to Pictures/screenshots/".into(),
            })),
            _ => {}
        }
    }

    fn nf_act(&mut self, idx: usize, fx: &mut Vec<Effect>) {
        if let Some(n) = self.notifs.get(idx) {
            let src = n.src_app;
            self.panel = None;
            if let Some(app) = src {
                self.launch(app);
            }
            let _ = fx; // launching has no external effect for embedded apps
        }
    }

    // -----------------------------------------------------------------------
    // Top-level action handler
    // -----------------------------------------------------------------------

    pub fn handle(&mut self, action: ShellAction) -> Vec<Effect> {
        let mut fx = Vec::new();
        match action {
            // ---- Radial open / close ----
            ShellAction::RadialHold { held: true } => {
                if !self.radial.visible {
                    let items = system_radial_items(&self.config.radial.system.slots);
                    self.radial.open(MenuLayer::System, items);
                    self.radial_stick_active = false;
                }
            }
            ShellAction::RadialHold { held: false } => {
                if self.radial.visible {
                    if self.radial_stick_active {
                        fx.push(Effect::Sound(SoundCue::Confirm));
                    }
                    self.radial.close();
                    self.radial_stick_active = false;
                }
            }
            ShellAction::StickMoved { x, y } => {
                self.stick_x = x;
                self.stick_y = y;
                if self.radial.visible {
                    self.radial_stick_active = self.radial.update_from_stick(x, y);
                }
            }

            // ---- Overlay / panel toggles ----
            ShellAction::OpenPalette => {
                if self.palette.visible { self.palette.close(); } else { self.palette.open(); }
            }
            ShellAction::OpenQuickSettings => self.toggle_panel(Panel::QuickSettings),
            ShellAction::OpenNotifications => self.toggle_panel(Panel::Notifications),
            ShellAction::OpenSwitcher      => self.toggle_panel(Panel::Switcher),
            ShellAction::OpenQuickMenu     => self.toggle_panel(Panel::QuickMenu),
            ShellAction::OpenRadial => {
                if !self.radial.visible {
                    let items = system_radial_items(&self.config.radial.system.slots);
                    self.radial.open(MenuLayer::System, items);
                    self.radial_stick_active = false;
                }
            }
            ShellAction::GoHome => {
                // Close any open panel first.
                if self.panel.is_some() {
                    self.panel = None;
                } else {
                    // Go home from Lock, Home, or App (SELECT always exits).
                    self.go_home();
                }
            }
            ShellAction::Lock => {
                self.screen = Screen::Lock;
                self.pin_len = 0;
                self.panel = None;
                self.konami_idx = 0;
            }

            // ---- Workspace cycling ----
            ShellAction::WorkspacePrev => self.workspaces.switch_prev(),
            ShellAction::WorkspaceNext => self.workspaces.switch_next(),

            // ---- Navigation / confirm / cancel (priority-routed) ----
            ShellAction::NavUp    => self.route_nav(Nav::Up,    &mut fx),
            ShellAction::NavDown  => self.route_nav(Nav::Down,  &mut fx),
            ShellAction::NavLeft  => self.route_nav(Nav::Left,  &mut fx),
            ShellAction::NavRight => self.route_nav(Nav::Right, &mut fx),
            ShellAction::Confirm  => self.route_confirm(&mut fx),
            ShellAction::Cancel   => self.route_cancel(&mut fx),

            // ---- Secondary / dismiss (X = dismiss notif / close switcher card) ----
            // (No dedicated ShellAction yet; handled via Cancel/Confirm above.)

            // ---- System actions ----
            ShellAction::BrightnessUp   => self.cfg.bright = (self.cfg.bright + 5).min(100),
            ShellAction::BrightnessDown => self.cfg.bright = (self.cfg.bright - 5).max(0),
            ShellAction::VolumeUp       => self.cfg.vol = (self.cfg.vol + 5).min(100),
            ShellAction::VolumeDown     => self.cfg.vol = (self.cfg.vol - 5).max(0),
            ShellAction::WifiToggle      => self.cfg.wifi = !self.cfg.wifi,
            ShellAction::BluetoothToggle => self.cfg.bt = !self.cfg.bt,
            ShellAction::CellularToggle  => {}
            ShellAction::VpnToggle       => self.cfg.vpn = !self.cfg.vpn,
            ShellAction::SplitToggle     => {}
            ShellAction::Sleep           => fx.push(Effect::Suspend),

            // ---- Text input — routed to the active target ----
            ShellAction::VoiceResult { text } => {
                match self.active_text_target() {
                    TextTarget::Palette => self.palette.set_query(&text),
                    TextTarget::Notes => {
                        if self.notes_focus_field == 0 { self.notes_edit_title.push_str(&text); }
                        else                           { self.notes_edit_body.push_str(&text);  }
                    }
                    TextTarget::None    => {}
                }
            }
            ShellAction::LowerKeyPress { key } => {
                let ch = key.chars().next().unwrap_or(' ');
                match self.active_text_target() {
                    TextTarget::Palette => self.palette.append_char(ch),
                    TextTarget::Notes => {
                        if self.notes_focus_field == 0 { self.notes_edit_title.push(ch); }
                        else                           { self.notes_edit_body.push(ch);  }
                    }
                    TextTarget::None => {}
                }
            }
            ShellAction::LowerBackspace => {
                match self.active_text_target() {
                    TextTarget::Palette => self.palette.backspace(),
                    TextTarget::Notes => {
                        if self.notes_focus_field == 0 { self.notes_edit_title.pop(); }
                        else                           { self.notes_edit_body.pop();  }
                    }
                    TextTarget::None => {}
                }
            }
            ShellAction::LowerSubmit => return self.route_confirm_owned(),

            ShellAction::LowerTap { .. } | ShellAction::PadMoved { .. } => {}
        }
        fx
    }

    fn route_confirm_owned(&mut self) -> Vec<Effect> {
        let mut fx = Vec::new();
        self.route_confirm(&mut fx);
        fx
    }

    // -----------------------------------------------------------------------
    // Priority-routed navigation
    // -----------------------------------------------------------------------

    fn route_nav(&mut self, dir: Nav, fx: &mut Vec<Effect>) {
        fx.push(Effect::Sound(SoundCue::Nav));

        // 1. Radial
        if self.radial.visible {
            self.radial.navigate(dir.into());
            return;
        }
        // 2. Palette
        if self.palette.visible {
            match dir {
                Nav::Up   => self.palette.move_up(),
                Nav::Down => self.palette.move_down(),
                _ => {}
            }
            return;
        }
        // 3. Panel
        if let Some(panel) = self.panel {
            self.nav_panel(panel, dir, fx);
            return;
        }
        // 4. Screen
        match self.screen {
            Screen::Lock => self.lock_konami(Some(dir), false, false),
            Screen::Home => self.nav_home(dir),
            Screen::App  => { if let Some(app) = self.app_id { self.nav_app(app, dir, fx); } }
        }
    }

    fn route_confirm(&mut self, fx: &mut Vec<Effect>) {
        // 1. Radial → activate focused slot
        if self.radial.visible {
            fx.push(Effect::Sound(SoundCue::Confirm));
            self.radial.close();
            self.radial_stick_active = false;
            return;
        }
        // 2. Palette → launch focused command
        if self.palette.visible {
            fx.push(Effect::Sound(SoundCue::Confirm));
            if let Some(id) = self.palette.focused_id().map(|s| s.to_owned()) {
                if let Some(app) = AppId::from_command(&id) {
                    self.launch(app);
                } else {
                    fx.push(Effect::LaunchExternal(id));
                }
            }
            self.palette.close();
            return;
        }
        // 3. Panel
        if let Some(panel) = self.panel {
            self.confirm_panel(panel, fx);
            return;
        }
        // 4. Screen
        match self.screen {
            Screen::Lock => self.lock_confirm(),
            Screen::Home => {
                let order = home_order();
                if let Some(app) = order.get(self.home_focus).copied() {
                    fx.push(Effect::Sound(SoundCue::Confirm));
                    self.launch(app);
                }
            }
            Screen::App => { if let Some(app) = self.app_id { self.confirm_app(app, fx); } }
        }
    }

    fn route_cancel(&mut self, fx: &mut Vec<Effect>) {
        fx.push(Effect::Sound(SoundCue::Cancel));

        if self.radial.visible {
            self.radial.close();
            self.radial_stick_active = false;
            return;
        }
        if self.palette.visible {
            self.palette.close();
            return;
        }
        if self.panel.is_some() {
            self.panel = None;
            return;
        }
        match self.screen {
            Screen::Lock => self.lock_konami(None, true, false),
            Screen::Home => {}
            Screen::App  => {
                // Settings: B in row pane → return to sidebar
                if self.app_id == Some(AppId::Settings) && !self.settings_sidebar_active {
                    self.settings_sidebar_active = true;
                }
                // All other apps: B does nothing — apps manage their own back navigation.
                // Use Select (go_home) or Start (switcher) to exit an app.
            }
        }
    }

    // -----------------------------------------------------------------------
    // Panel navigation / confirm
    // -----------------------------------------------------------------------

    fn nav_panel(&mut self, panel: Panel, dir: Nav, fx: &mut Vec<Effect>) {
        let _ = fx; // used by QS slider L/R path below
        match panel {
            Panel::QuickSettings => {
                // Focus zones: qs_slider_focus >= 0 means on a slider (0=vol, 1=bright);
                // -1 means focus is on the 2-column tile grid.
                let n = QS_KEYS.len(); // 8 tiles
                if self.qs_slider_focus >= 0 {
                    let sf = self.qs_slider_focus as usize;
                    match dir {
                        Nav::Up => {
                            if sf > 0 { self.qs_slider_focus -= 1; }
                            // At vol (0): no-op, already at top.
                        }
                        Nav::Down => {
                            if sf < 1 {
                                // vol → bright
                                self.qs_slider_focus += 1;
                            } else {
                                // bright → exit to top row of tiles
                                self.qs_slider_focus = -1;
                                self.qs_focus = 0;
                            }
                        }
                        Nav::Left => {
                            if sf == 0 { self.cfg.vol = (self.cfg.vol - 5).max(0); }
                            else       { self.cfg.bright = (self.cfg.bright - 5).max(0); }
                        }
                        Nav::Right => {
                            if sf == 0 { self.cfg.vol = (self.cfg.vol + 5).min(100); }
                            else       { self.cfg.bright = (self.cfg.bright + 5).min(100); }
                        }
                    }
                } else {
                    // On tiles — 2-column grid.
                    match dir {
                        Nav::Up => {
                            if self.qs_focus < 2 {
                                // Top row → enter bright slider
                                self.qs_slider_focus = 1;
                            } else {
                                self.qs_focus -= 2;
                            }
                        }
                        Nav::Down => {
                            self.qs_focus = (self.qs_focus + 2).min(n - 1);
                        }
                        Nav::Left => {
                            // Stay within row: only move if on the right column.
                            if self.qs_focus % 2 == 1 { self.qs_focus -= 1; }
                        }
                        Nav::Right => {
                            // Stay within row: only move if on the left column and slot exists.
                            if self.qs_focus.is_multiple_of(2) && self.qs_focus + 1 < n {
                                self.qs_focus += 1;
                            }
                        }
                    }
                }
            }
            Panel::Notifications => {
                let n = self.notifs.len();
                self.nf_focus = match dir {
                    Nav::Up   => self.nf_focus.saturating_sub(1),
                    Nav::Down => (self.nf_focus + 1).min(n.saturating_sub(1)),
                    _ => self.nf_focus,
                };
            }
            Panel::Switcher => {
                let n = self.run_apps.len();
                self.sw_focus = match dir {
                    Nav::Left  => self.sw_focus.saturating_sub(1),
                    Nav::Right => (self.sw_focus + 1).min(n.saturating_sub(1)),
                    _ => self.sw_focus,
                };
            }
            Panel::QuickMenu => {
                let n = 4usize;
                self.qm_focus = match dir {
                    Nav::Up   => self.qm_focus.saturating_sub(1),
                    Nav::Down => (self.qm_focus + 1).min(n - 1),
                    _ => self.qm_focus,
                };
            }
        }
    }

    fn confirm_panel(&mut self, panel: Panel, fx: &mut Vec<Effect>) {
        match panel {
            Panel::QuickSettings => {
                let key = QS_KEYS[self.qs_focus];
                self.qs_tile(key, fx);
            }
            Panel::Notifications => self.nf_act(self.nf_focus, fx),
            Panel::Switcher => {
                if let Some(app) = self.run_apps.get(self.sw_focus).copied() {
                    self.resume_app(app);
                }
            }
            Panel::QuickMenu => {
                self.panel = None;
                match self.qm_focus {
                    0 => fx.push(Effect::Suspend), // Power Off (stub: suspend)
                    1 => fx.push(Effect::Suspend), // Sleep
                    2 => {                          // Lock
                        self.screen = Screen::Lock;
                        self.pin_len = 0;
                        self.konami_idx = 0;
                    }
                    3 => self.launch(AppId::Settings), // Settings
                    _ => {}
                }
            }
        }
    }

    /// Secondary action (X button): dismiss a notification / close a switcher card.
    pub fn secondary(&mut self) -> Vec<Effect> {
        let mut fx = vec![];
        match self.panel {
            Some(Panel::Notifications) => {
                if self.nf_focus < self.notifs.len() {
                    self.notifs.remove(self.nf_focus);
                    self.nf_focus = self.nf_focus.saturating_sub(1);
                }
            }
            Some(Panel::Switcher) => {
                if let Some(app) = self.run_apps.get(self.sw_focus).copied() {
                    fx.extend(self.kill_app(app));
                }
            }
            _ => {}
        }
        fx
    }

    // -----------------------------------------------------------------------
    // Home navigation (faithful port of the HTML home routing)
    // -----------------------------------------------------------------------

    fn nav_home(&mut self, dir: Nav) {
        let grid = HOME_GRID.len();
        let total = grid + DOCK.len();
        match dir {
            Nav::Right => self.home_focus = (self.home_focus + 1).min(total - 1),
            Nav::Left  => self.home_focus = self.home_focus.saturating_sub(1),
            Nav::Down => {
                if self.home_focus < grid {
                    self.home_focus = (self.home_focus + HOME_COLS).min(grid - 1);
                } else {
                    self.home_focus = (self.home_focus + 1).min(total - 1);
                }
            }
            Nav::Up => {
                if self.home_focus >= grid {
                    self.home_focus = grid - 1;
                } else {
                    self.home_focus = self.home_focus.saturating_sub(HOME_COLS);
                }
            }
        }
    }

    // -----------------------------------------------------------------------
    // Per-app input dispatch (rich behavior arrives with torchform-apps; for
    // now Settings is fully wired and other apps adjust their focused row).
    // -----------------------------------------------------------------------

    fn nav_app(&mut self, app: AppId, dir: Nav, fx: &mut Vec<Effect>) {
        if app == AppId::Settings {
            if self.settings_sidebar_active {
                // Sidebar pane: Up/Down navigate sections; Right enters the row pane
                match dir {
                    Nav::Up    => { fx.push(Effect::Sound(SoundCue::Nav)); self.sidebar_nav_up(); }
                    Nav::Down  => { fx.push(Effect::Sound(SoundCue::Nav)); self.sidebar_nav_down(); }
                    Nav::Right => self.settings_enter_rows(),
                    Nav::Left  => {}
                }
            } else {
                // Row pane: Up/Down navigate rows; L/R adjust values; Left returns to sidebar
                match dir {
                    Nav::Up => {
                        let cur = self.row(AppId::Settings) as usize;
                        let next = settings::focus_up(cur, &self.settings_rows) as i32;
                        self.set_row(AppId::Settings, next);
                        fx.push(Effect::Sound(SoundCue::Nav));
                    }
                    Nav::Down => {
                        let cur = self.row(AppId::Settings) as usize;
                        let next = settings::focus_down(cur, &self.settings_rows) as i32;
                        self.set_row(AppId::Settings, next);
                        fx.push(Effect::Sound(SoundCue::Nav));
                    }
                    Nav::Left | Nav::Right => {
                        let delta = if matches!(dir, Nav::Right) { 1 } else { -1 };
                        let row = self.row(AppId::Settings) as usize;
                        if let Some(entry) = self.settings_rows.get(row) {
                            let key = entry.key.clone();
                            let schema_ref = self.settings_schema.clone();
                            if settings::apply_adjustment(&key, delta, &mut self.config, &schema_ref) {
                                fx.push(Effect::SaveConfig);
                            }
                            self.rebuild_settings();
                        }
                    }
                }
            }
            return;
        }
        if app == AppId::Notes {
            if self.notes_editing {
                // Navigate between title (0) and body (1) fields
                match dir {
                    Nav::Up   => { self.notes_focus_field = 0; }
                    Nav::Down => { self.notes_focus_field = 1; }
                    _ => {}
                }
            } else {
                // Navigate note list
                match dir {
                    Nav::Up   => { let r = (self.row(app) - 1).max(0); self.set_row(app, r); }
                    Nav::Down => { let r = self.row(app) + 1; self.set_row(app, r); }
                    _ => {}
                }
            }
            return;
        }
        // Generic apps: up/down adjust the focused row (clamped at 0).
        match dir {
            Nav::Up   => { let r = (self.row(app) - 1).max(0); self.set_row(app, r); }
            Nav::Down => { let r = self.row(app) + 1; self.set_row(app, r); }
            _ => {}
        }
    }

    /// Enter the row pane for the currently-focused sidebar section.
    pub fn settings_enter_rows(&mut self) {
        self.settings_sidebar_active = false;
        // Load the rows for the active section
        self.settings_switch_section();
        self.set_row(AppId::Settings, 0);
    }

    /// Switch the active section to match `settings_sidebar_focus`.
    /// Rebuilds `settings_rows` with only that section's rows.
    pub fn settings_switch_section(&mut self) {
        let flat = self.sidebar_entries_flat();
        if let Some(entry) = flat.get(self.settings_sidebar_focus) {
            if entry.is_section {
                self.settings_rows = settings::make_section_entries(
                    &self.settings_schema,
                    &self.config,
                    &entry.section_id,
                );
            }
        }
    }

    fn confirm_app(&mut self, app: AppId, fx: &mut Vec<Effect>) {
        if app == AppId::Notes {
            if self.notes_editing {
                // A while editing = save the note
                let note = Note {
                    id:    self.notes_edit_idx.unwrap_or(self.notes_list.len()),
                    title: self.notes_edit_title.clone(),
                    body:  self.notes_edit_body.clone(),
                    time:  "Just now".into(),
                };
                if let Some(idx) = self.notes_edit_idx {
                    if let Some(n) = self.notes_list.get_mut(idx) { *n = note.clone(); }
                } else {
                    self.notes_list.push(note.clone());
                }
                fx.push(Effect::SaveNotes(self.notes_list.clone()));
                self.notes_editing = false;
            } else {
                // A on a note in the list = open it for editing
                let row = self.row(AppId::Notes) as usize;
                if row < self.notes_list.len() {
                    let n = &self.notes_list[row];
                    self.notes_edit_idx   = Some(row);
                    self.notes_edit_title = n.title.clone();
                    self.notes_edit_body  = n.body.clone();
                    self.notes_focus_field = 1;
                    self.notes_editing    = true;
                } else {
                    // Past list end = new note (same as X)
                    self.notes_edit_idx   = None;
                    self.notes_edit_title = String::new();
                    self.notes_edit_body  = String::new();
                    self.notes_focus_field = 0;
                    self.notes_editing    = true;
                }
            }
            fx.push(Effect::Sound(SoundCue::Confirm));
            return;
        }
        if app == AppId::Settings {
            if self.settings_sidebar_active {
                // A in sidebar = enter this section's rows
                self.settings_enter_rows();
                fx.push(Effect::Sound(SoundCue::Confirm));
                return;
            }
            // A in row pane = activate the focused row
            let row = self.row(AppId::Settings) as usize;
            if let Some(entry) = self.settings_rows.get(row) {
                let key = entry.key.clone();

                // Dotfile scan action
                if key == "sysapps.scan" {
                    use torchform_config::{expand_tilde, dotfiles};
                    let root = expand_tilde("~/.config");
                    let found = dotfiles::scan_config_dir(&root);
                    self.config.dotfiles.detected = dotfiles::to_cache_entries(&found);
                    fx.push(Effect::SaveConfig);
                    self.settings_switch_section();
                    return;
                }

                if settings::apply_activation(&key, &mut self.config) {
                    fx.push(Effect::SaveConfig);
                }
                self.settings_switch_section();
            }
        }
    }

    // -----------------------------------------------------------------------
    // Lock screen
    // -----------------------------------------------------------------------

    fn lock_confirm(&mut self) {
        // Konami first (A is the final key); then PIN.
        self.lock_konami(None, false, true);
        if self.screen != Screen::Lock {
            return; // konami unlocked
        }
        self.pin_len = (self.pin_len + 1).min(4);
        if self.pin_len >= 4 {
            self.screen = Screen::Home;
            self.pin_len = 0;
        }
    }

    fn lock_konami(&mut self, dir: Option<Nav>, is_b: bool, is_a: bool) {
        let token = if let Some(d) = dir {
            Some(match d { Nav::Up => Kon::Up, Nav::Down => Kon::Down, Nav::Left => Kon::Left, Nav::Right => Kon::Right })
        } else if is_b {
            Some(Kon::B)
        } else if is_a {
            Some(Kon::A)
        } else {
            None
        };
        if let Some(tok) = token {
            if self.konami_idx < KONAMI.len() && tok == KONAMI[self.konami_idx] {
                self.konami_idx += 1;
            } else {
                self.konami_idx = if tok == KONAMI[0] { 1 } else { 0 };
            }
            if self.konami_idx == KONAMI.len() {
                self.konami_idx = 0;
                self.screen = Screen::Home;
                self.pin_len = 0;
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Small local direction enum (decoupled from radial::Direction so the routing
// reads clearly), with a conversion for the radial menu.
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Nav { Up, Down, Left, Right }

impl From<Nav> for Direction {
    fn from(n: Nav) -> Self {
        match n {
            Nav::Up => Direction::Up,
            Nav::Down => Direction::Down,
            Nav::Left => Direction::Left,
            Nav::Right => Direction::Right,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn shell() -> Shell {
        Shell::new(TorchformConfig::default())
    }

    #[test]
    fn boots_to_lock() {
        let s = shell();
        assert_eq!(s.screen, Screen::Lock);
        assert!(s.panel.is_none());
    }

    #[test]
    fn pin_unlocks_to_home() {
        let mut s = shell();
        for _ in 0..4 { s.handle(ShellAction::Confirm); }
        assert_eq!(s.screen, Screen::Home);
        assert_eq!(s.pin_len, 0);
    }

    #[test]
    fn konami_unlocks() {
        let mut s = shell();
        use ShellAction::*;
        for a in [NavUp, NavUp, NavDown, NavDown, NavLeft, NavRight, NavLeft, NavRight, Cancel, Confirm] {
            s.handle(a);
        }
        assert_eq!(s.screen, Screen::Home);
    }

    #[test]
    fn home_launches_first_grid_app() {
        let mut s = shell();
        s.screen = Screen::Home;
        s.handle(ShellAction::Confirm); // home_focus 0 = Media
        assert_eq!(s.screen, Screen::App);
        assert_eq!(s.app_id, Some(AppId::Media));
        assert!(s.run_apps.contains(&AppId::Media));
    }

    #[test]
    fn home_nav_right_then_launch() {
        let mut s = shell();
        s.screen = Screen::Home;
        s.handle(ShellAction::NavRight); // focus 1 = Email
        s.handle(ShellAction::Confirm);
        assert_eq!(s.app_id, Some(AppId::Email));
    }

    #[test]
    fn quick_settings_toggle_and_tile() {
        let mut s = shell();
        s.screen = Screen::Home;
        s.handle(ShellAction::OpenQuickSettings);
        assert_eq!(s.panel, Some(Panel::QuickSettings));
        let wifi_before = s.cfg.wifi;
        // qs_focus 0 = wifi
        s.handle(ShellAction::Confirm);
        assert_eq!(s.cfg.wifi, !wifi_before);
        // Toggling QS again closes it.
        s.handle(ShellAction::OpenQuickSettings);
        assert!(s.panel.is_none());
    }

    #[test]
    fn screenshot_tile_emits_banner() {
        let mut s = shell();
        s.screen = Screen::Home;
        s.handle(ShellAction::OpenQuickSettings);
        // Navigate to _ss (index 4): down (0->2), down (2->4)
        s.handle(ShellAction::NavDown);
        s.handle(ShellAction::NavDown);
        assert_eq!(QS_KEYS[s.qs_focus], "_ss");
        let fx = s.handle(ShellAction::Confirm);
        assert!(fx.iter().any(|e| matches!(e, Effect::ShowBanner(_))));
    }

    #[test]
    fn switcher_resume_and_kill() {
        let mut s = shell();
        s.screen = Screen::Home;
        s.launch(AppId::Terminal);
        s.launch(AppId::Browser);
        s.handle(ShellAction::OpenSwitcher);
        assert_eq!(s.panel, Some(Panel::Switcher));
        // Kill focused (sw_focus 0 = Terminal)
        s.secondary();
        assert!(!s.run_apps.contains(&AppId::Terminal));
        assert!(s.run_apps.contains(&AppId::Browser));
    }

    #[test]
    fn back_in_app_does_nothing_b_cannot_exit_apps() {
        let mut s = shell();
        s.launch(AppId::Terminal);
        s.launch(AppId::Browser);
        // B (Cancel) does nothing while inside an app — apps handle their own back nav.
        s.handle(ShellAction::Cancel);
        assert_eq!(s.screen, Screen::App);
        assert_eq!(s.app_id, Some(AppId::Browser));
        // GoHome (Select) exits the app and returns to Home.
        s.handle(ShellAction::GoHome);
        assert_eq!(s.screen, Screen::Home);
    }

    #[test]
    fn notification_opens_source_app() {
        let mut s = shell();
        s.screen = Screen::Home;
        s.handle(ShellAction::OpenNotifications);
        assert_eq!(s.panel, Some(Panel::Notifications));
        s.handle(ShellAction::Confirm); // nf_focus 0 → SMS
        assert_eq!(s.app_id, Some(AppId::Sms));
        assert!(s.panel.is_none());
    }

    #[test]
    fn radial_opens_on_hold_and_closes_on_release() {
        let mut s = shell();
        s.screen = Screen::Home;
        s.handle(ShellAction::RadialHold { held: true });
        assert!(s.radial.visible);
        s.handle(ShellAction::RadialHold { held: false });
        assert!(!s.radial.visible);
    }
}
