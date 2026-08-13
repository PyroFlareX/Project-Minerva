// Torchform QuickShell data registry.
// Edit this file to change app cards, palette entries, and radial commands
// without touching the shell state machine or recompiling anything.
.pragma library

var gridApps = [
    { name: "Media",    icon: "🎵", bg: "#1a1535", idx: 0 },
    { name: "Email",    icon: "📧", bg: "#14221a", idx: 1 },
    { name: "Settings", icon: "⚙️", bg: "#1a1a1a", idx: 2 },
    { name: "Sysmon",   icon: "📊", bg: "#0f1a1a", idx: 3 },
    { name: "Pkgman",   icon: "📦", bg: "#1a1520", idx: 4 },
    { name: "Logview",  icon: "📋", bg: "#1a1200", idx: 5 },
    { name: "Notes",    icon: "📝", bg: "#0a1a14", idx: 6 }
]

var dockApps = [
    { name: "Terminal", icon: "⬛", bg: "#0d1117", idx: 7,  running: true  },
    { name: "Browser",  icon: "🌐", bg: "#0f1535", idx: 8,  running: false },
    { name: "SMS",      icon: "💬", bg: "#0a1a0a", idx: 9,  running: false },
    { name: "Phone",    icon: "📞", bg: "#1a0a0a", idx: 10, running: false },
    { name: "Files",    icon: "🗂️", bg: "#1a1520", idx: 11, running: false }
]

// Overlay registry: edit this data-only section to change menu content,
// geometry, and focus order without recompiling the shell.
var overlayConfig = {
    version: 2,
    radial: {
        title: "System",
        radius: 170,
        itemSize: 92,
        initialFocus: 0,
        navigation: { up: -2, down: 2, left: -1, right: 1 },
        items: [
            { id: "sys.brightness.up",   icon: "🔆", label: "Brightness +", description: "Raise display brightness", destination: "Display setting", enabled: true },
            { id: "sys.volume.up",       icon: "🔉", label: "Volume +",     description: "Raise system volume", destination: "Audio setting", enabled: true },
            { id: "sys.wifi",             icon: "📶", label: "Wi-Fi",        description: "Scan and connect networks", destination: "Wi-Fi panel", enabled: true },
            { id: "sys.sleep",            icon: "💤", label: "Sleep",        description: "Suspend after confirmation", destination: "Power control", enabled: true },
            { id: "sys.brightness.down", icon: "🔅", label: "Brightness −", description: "Lower display brightness", destination: "Display setting", enabled: true },
            { id: "sys.volume.down",     icon: "🔈", label: "Volume −",     description: "Lower system volume", destination: "Audio setting", enabled: true },
            { id: "sys.dnd",             icon: "🔕", label: "Do Not Disturb", description: "Toggle notification quiet mode", destination: "Notification setting", enabled: true },
            { id: "sys.power",           icon: "🔌", label: "Power menu",   description: "Show power confirmation", destination: "Power control", enabled: true }
        ]
    },
    quickSettings: {
        side: "right",
        width: 280,
        title: "Quick Settings",
        closeGlyph: "›",
        columns: 2,
        initialFocus: 0,
        sliders: [
            { id: "volume",     icon: "🔉", label: "Volume",     value: 72, min: 0, max: 100, step: 5 },
            { id: "brightness", icon: "🔆", label: "Brightness", value: 85, min: 0, max: 100, step: 5 }
        ],
        tiles: [
            { id: "wifi",      action: "sys.wifi",      icon: "📶", name: "Wi-Fi",       initialOn: true  },
            { id: "bluetooth", action: "sys.bluetooth", icon: "📡", name: "Bluetooth",   initialOn: true  },
            { id: "airplane",  action: "sys.airplane",  icon: "✈",  name: "Airplane",    initialOn: false },
            { id: "dnd",       action: "sys.dnd",       icon: "🔕", name: "DND",         initialOn: false },
            { id: "dark-mode", action: "sys.dark-mode", icon: "🌙", name: "Dark Mode",   initialOn: true  },
            { id: "rotate",    action: "sys.rotate",    icon: "🔄", name: "Auto-rotate", initialOn: false }
        ]
    },
    notifications: {
        side: "left",
        width: 300,
        title: "Notifications",
        closeGlyph: "‹",
        initialFocus: 0,
        items: [
            { id: "email-1", icon: "📧", app: "Email",  time: "2m ago", title: "New message from Alice", body: "Hey, did you see the latest Minerva prototype?" },
            { id: "system-1", icon: "⚙️", app: "System", time: "5m ago", title: "Update available", body: "torchform-shell 0.9.2 is ready to install." }
        ]
    },
    quickMenu: {
        title: "Power",
        width: 380,
        initialFocus: 0,
        items: [
            { id: "power.lock",     icon: "🔒", label: "Lock",      description: "Return to the lock screen", confirm: false },
            { id: "power.session",  icon: "🚪", label: "End session", description: "Stop the Torchform session", confirm: true },
            { id: "power.reboot",   icon: "🔁", label: "Reboot",    description: "Restart the device", confirm: true },
            { id: "power.poweroff", icon: "⏻", label: "Power Off", description: "Halt the device", confirm: true }
        ]
    },
    switcher: {
        title: "App Switcher",
        cardWidth: 200,
        cardHeight: 140,
        spacing: 20,
        initialFocus: 0,
        // Populated at runtime from the apps this session actually opened.
        apps: []
    }
}

// Log sources for the Logview app. Alpine has no journalctl; these map onto
// BusyBox syslog, dmesg, and the Torchform session logs.
var logSources = [
    { id: "system",    label: "System" },
    { id: "kernel",    label: "Kernel" },
    { id: "torchform", label: "Torchform" }
]

var radialItems = overlayConfig.radial.items

var paletteCommands = [
    { id: "app.terminal",   label: "Open Terminal",        description: "Run commands and inspect output", category: "Apps",   keywords: "shell console command", icon: "⬛", shortcut: "A" },
    { id: "app.browser",    label: "Open Browser",         description: "Browse the web", category: "Apps",   keywords: "web internet chromium", icon: "🌐", shortcut: "" },
    { id: "app.settings",   label: "Settings",             description: "Configure Torchform and the device", category: "Apps",   keywords: "config preferences options", icon: "⚙️", shortcut: "" },
    { id: "app.files",      label: "Files",                description: "Browse files and folders", category: "Apps",   keywords: "file manager folders storage", icon: "🗂️", shortcut: "" },
    { id: "app.media",      label: "Media Player",         description: "Open video, audio, images, or books", category: "Apps",   keywords: "music video pictures ebooks", icon: "🎵", shortcut: "" },
    { id: "app.sysmon",     label: "System Monitor",       description: "Inspect CPU, memory, disk, and network", category: "Apps",   keywords: "processes performance resources", icon: "📊", shortcut: "" },
    { id: "app.notes",      label: "Notes",                description: "Write and read local notes", category: "Apps",   keywords: "notes markdown write memo", icon: "📝", shortcut: "" },
    { id: "app.logview",    label: "Logs",                 description: "Read system, kernel, and Torchform logs", category: "Apps",   keywords: "log journal syslog dmesg", icon: "📋", shortcut: "" },
    { id: "app.pkgman",     label: "Packages",             description: "Inspect installed apk packages", category: "Apps",   keywords: "package apk install software", icon: "📦", shortcut: "" },
    { id: "sys.power",      label: "Power Menu",           description: "Lock, reboot, or power off", category: "System", keywords: "power reboot shutdown halt lock", icon: "⏻", shortcut: "" },
    { id: "sys.wifi",       label: "Wi-Fi Networks",       description: "Scan, choose, and connect to Wi-Fi", category: "System", keywords: "wireless wlan network password", icon: "📶", shortcut: "" },
    { id: "sys.bluetooth",  label: "Bluetooth",            description: "Scan, pair, and connect devices", category: "System", keywords: "wireless bluetooth pair headset", icon: "🔵", shortcut: "" },
    { id: "sys.lower-osk",  label: "Open Lower Keyboard",  description: "Type on the companion display", category: "System", keywords: "osk keyboard input", icon: "⌨", shortcut: "" },
    { id: "sys.brightness", label: "Brightness",           description: "Adjust display brightness", category: "System", keywords: "display screen light", icon: "🔆", shortcut: "" },
    { id: "sys.sleep",      label: "Sleep",                description: "Request a suspend or power action", category: "System", keywords: "suspend power", icon: "💤", shortcut: "" },
    { id: "sys.volume",     label: "Volume",               description: "Adjust system audio", category: "System", keywords: "sound audio mute", icon: "🔉", shortcut: "" },
    { id: "nav.home",       label: "Go Home",              description: "Return to the home grid", category: "Nav",    keywords: "home launcher", icon: "🏠", shortcut: "START" },
    { id: "nav.lock",       label: "Lock Screen",          description: "Lock Torchform", category: "Nav",    keywords: "lock security", icon: "🔒", shortcut: "" }
]


var lowerActions = [
    { id: "nav.home", label: "Home", key: "START" },
    { id: "app.files", label: "Files", key: "A" },
    { id: "app.terminal", label: "Terminal", key: "X" },
    { id: "app.sysmon", label: "Monitor", key: "Y" },
    { id: "sys.wifi", label: "Wi-Fi", key: "R1" },
    { id: "sys.bluetooth", label: "Bluetooth", key: "L1" }
]
