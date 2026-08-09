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
            { id: "sys.brightness.up",   icon: "🔆", label: "Bright+", enabled: true },
            { id: "sys.volume.up",       icon: "🔉", label: "Vol+",    enabled: true },
            { id: "sys.wifi",             icon: "📶", label: "Wi-Fi",   enabled: true },
            { id: "sys.sleep",            icon: "💤", label: "Sleep",   enabled: true },
            { id: "sys.brightness.down", icon: "🔅", label: "Bright-", enabled: true },
            { id: "sys.volume.down",     icon: "🔈", label: "Vol-",    enabled: true },
            { id: "sys.dnd",             icon: "🔕", label: "DND",     enabled: true },
            { id: "sys.power",            icon: "🔌", label: "Power",   enabled: true }
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
    switcher: {
        title: "App Switcher",
        cardWidth: 200,
        cardHeight: 140,
        spacing: 20,
        initialFocus: 0,
        apps: [
            { name: "Terminal", icon: "⬛", bg: "#0d1117" },
            { name: "Files",    icon: "🗂️", bg: "#1a1520" },
            { name: "Sysmon",   icon: "📊", bg: "#0f1a1a" }
        ]
    }
}

var radialItems = overlayConfig.radial.items

var paletteCommands = [
    { id: "app.terminal",   label: "Open Terminal",  category: "Apps",   icon: "⬛", shortcut: "A" },
    { id: "app.browser",    label: "Open Browser",   category: "Apps",   icon: "🌐", shortcut: "" },
    { id: "app.settings",   label: "Settings",       category: "Apps",   icon: "⚙️", shortcut: "" },
    { id: "app.files",      label: "Files",          category: "Apps",   icon: "🗂️", shortcut: "" },
    { id: "app.media",      label: "Media Player",   category: "Apps",   icon: "🎵", shortcut: "" },
    { id: "app.sysmon",     label: "System Monitor",  category: "Apps",   icon: "📊", shortcut: "" },
    { id: "sys.wifi",       label: "Wi-Fi Networks", category: "System", icon: "📶", shortcut: "" },
    { id: "sys.bluetooth",  label: "Bluetooth",      category: "System", icon: "🔵", shortcut: "" },
    { id: "sys.brightness", label: "Brightness",     category: "System", icon: "🔆", shortcut: "" },
    { id: "sys.sleep",      label: "Sleep",          category: "System", icon: "💤", shortcut: "" },
    { id: "sys.volume",     label: "Volume",         category: "System", icon: "🔉", shortcut: "" },
    { id: "nav.home",       label: "Go Home",        category: "Nav",    icon: "🏠", shortcut: "START" },
    { id: "nav.lock",       label: "Lock Screen",    category: "Nav",    icon: "🔒", shortcut: "" }
]


var lowerActions = [
    { id: "nav.home", label: "Home", key: "START" },
    { id: "app.files", label: "Files", key: "A" },
    { id: "app.terminal", label: "Terminal", key: "X" },
    { id: "app.sysmon", label: "Monitor", key: "Y" },
    { id: "sys.wifi", label: "Wi-Fi", key: "R1" },
    { id: "sys.bluetooth", label: "Bluetooth", key: "L1" }
]
