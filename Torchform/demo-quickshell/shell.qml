import QtQuick
import Quickshell
import Quickshell.Wayland
import "."

// Torchform QuickShell Demo
// Upper display: 1920×1080  (Quickshell.screens[0])
// Lower display:  640×480   (Quickshell.screens[1], if present)
//
// Keyboard map (matches torchform-shell emulator shortcuts):
//   Space      → Home         Enter/Return → App Switcher
//   A          → Confirm      Escape/B     → Back / close
//   X          → Palette      Z            → Quick Settings
//   C          → Notifications Tab         → Radial (System)
//   Arrow keys → Navigate

ShellRoot {
    id: shell

    // ─── State ──────────────────────────────────────────────────────────────
    property string activeScreen: "lock"  // lock | home | app
    property string activePanel:  ""      // "" | qs | notif | switcher
    property bool   paletteOpen:  false
    property bool   radialOpen:   false
    property string radialLayer:  "system"

    property int    radialFocus:  0
    property int    homeFocus:    0
    property int    pinLen:       0
    property int    notifCount:   2
    property int    batteryPct:   78
    property bool   wifiOn:       true
    property bool   btOn:         true
    property string nowPlaying:   ""
    property string launchedApp:  "Terminal"
    property string launchedIcon: "⬛"
    property string launchedBg:   "#0d1117"

    property string bannerText:    ""
    property bool   bannerVisible: false
    property int    switcherFocus: 0

    // WiFi / Bluetooth panels (sub-panels inside the qs panel)
    property bool   wifiPanelOpen: false
    property int    wifiFocus:     0
    property bool   btPanelOpen:   false
    property int    btFocus:       0

    // Palette state
    property string paletteQuery:    ""
    property int    paletteFocus:    0
    property var    paletteFiltered: paletteCommands

    // ─── Clock ──────────────────────────────────────────────────────────────
    property string timeStr: Qt.formatTime(new Date(), "hh:mm")
    property string dateStr: Qt.formatDate(new Date(), "dddd, MMM d")

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            shell.timeStr = Qt.formatTime(new Date(), "hh:mm")
            shell.dateStr = Qt.formatDate(new Date(), "dddd, MMM d")
        }
    }

    Timer {
        id: bannerTimer
        interval: 3500
        onTriggered: shell.bannerVisible = false
    }

    function showBanner(text) {
        bannerText    = text
        bannerVisible = true
        bannerTimer.restart()
    }

    // ─── App data ────────────────────────────────────────────────────────────
    readonly property var gridApps: [
        { name: "Media",    icon: "🎵", bg: "#1a1535", idx: 0 },
        { name: "Email",    icon: "📧", bg: "#14221a", idx: 1 },
        { name: "Settings", icon: "⚙️", bg: "#1a1a1a", idx: 2 },
        { name: "Sysmon",   icon: "📊", bg: "#0f1a1a", idx: 3 },
        { name: "Pkgman",   icon: "📦", bg: "#1a1520", idx: 4 },
        { name: "Logview",  icon: "📋", bg: "#1a1200", idx: 5 },
        { name: "Notes",    icon: "📝", bg: "#0a1a14", idx: 6 },
    ]

    readonly property var dockApps: [
        { name: "Terminal", icon: "⬛", bg: "#0d1117", idx: 7,  running: true  },
        { name: "Browser",  icon: "🌐", bg: "#0f1535", idx: 8,  running: false },
        { name: "SMS",      icon: "💬", bg: "#0a1a0a", idx: 9,  running: false },
        { name: "Phone",    icon: "📞", bg: "#1a0a0a", idx: 10, running: false },
        { name: "Files",    icon: "🗂️", bg: "#1a1520", idx: 11, running: false },
    ]

    readonly property var systemRadial: [
        { icon: "🔆", label: "Bright+", enabled: true },
        { icon: "🔉", label: "Vol+",    enabled: true },
        { icon: "📶", label: "Wi-Fi",   enabled: true },
        { icon: "💤", label: "Sleep",   enabled: true },
        { icon: "🔅", label: "Bright-", enabled: true },
        { icon: "🔈", label: "Vol-",    enabled: true },
        { icon: "🔕", label: "DND",     enabled: true },
        { icon: "🔌", label: "Power",   enabled: true },
    ]

    readonly property var paletteCommands: [
        { id: "app.terminal",   label: "Open Terminal",  category: "Apps",   icon: "⬛", shortcut: "D → ⬛" },
        { id: "app.browser",    label: "Open Browser",   category: "Apps",   icon: "🌐", shortcut: ""        },
        { id: "app.settings",   label: "Settings",       category: "Apps",   icon: "⚙️", shortcut: ""        },
        { id: "app.files",      label: "Files",          category: "Apps",   icon: "🗂️", shortcut: ""        },
        { id: "app.media",      label: "Media Player",   category: "Apps",   icon: "🎵", shortcut: ""        },
        { id: "sys.wifi",       label: "Wi-Fi Networks", category: "System", icon: "📶", shortcut: ""        },
        { id: "sys.bluetooth",  label: "Bluetooth",      category: "System", icon: "🔵", shortcut: ""        },
        { id: "sys.brightness", label: "Brightness",     category: "System", icon: "🔆", shortcut: ""        },
        { id: "sys.sleep",      label: "Sleep",          category: "System", icon: "💤", shortcut: ""        },
        { id: "sys.volume",     label: "Volume",         category: "System", icon: "🔉", shortcut: ""        },
        { id: "nav.home",       label: "Go Home",        category: "Nav",    icon: "🏠", shortcut: "Space"    },
        { id: "nav.lock",       label: "Lock Screen",    category: "Nav",    icon: "🔒", shortcut: ""        },
    ]

    readonly property var switcherApps: [
        { name: "Terminal", icon: "⬛", bg: "#0d1117" },
        { name: "Browser",  icon: "🌐", bg: "#0f1535" },
    ]

    // ─── Hint bar content ────────────────────────────────────────────────────
    property var currentHints: {
        if (activeScreen === "lock")
            return [{key:"A", label:"Unlock"}]
        if (wifiPanelOpen)
            return [{key:"↑↓", label:"Nav"}, {key:"A", label:"Connect"}, {key:"Esc", label:"Close"}]
        if (btPanelOpen)
            return [{key:"↑↓", label:"Nav"}, {key:"A", label:"Pair"}, {key:"Esc", label:"Close"}]
        if (radialOpen)
            return [{key:"↑↓←→", label:"Select"}, {key:"A", label:"Activate"}, {key:"Esc", label:"Close"}]
        if (paletteOpen)
            return [{key:"↑↓", label:"Nav"}, {key:"A", label:"Launch"}, {key:"Esc", label:"Close"}]
        if (activePanel === "switcher")
            return [{key:"←→", label:"Select"}, {key:"A", label:"Switch"}, {key:"Esc", label:"Close"}]
        if (activePanel !== "")
            return [{key:"↑↓", label:"Nav"}, {key:"Esc", label:"Close"}]
        if (activeScreen === "home")
            return [{key:"↑↓←→", label:"Nav"}, {key:"A", label:"Launch"}, {key:"X", label:"Search"}, {key:"Enter", label:"Apps"}]
        if (activeScreen === "app")
            return [{key:"Space", label:"Home"}, {key:"X", label:"Search"}, {key:"C", label:"Notifs"}, {key:"Z", label:"QS"}]
        return []
    }

    // ─── Action functions ─────────────────────────────────────────────────────
    function handleConfirm() {
        if (wifiPanelOpen) {
            showBanner("Connecting to network " + wifiFocus + "…")
            return
        }
        if (btPanelOpen) {
            showBanner("Pairing device " + btFocus + "…")
            return
        }
        if (radialOpen) {
            var item = systemRadial[radialFocus]
            showBanner(item.label + " activated")
            radialOpen = false
            return
        }
        if (paletteOpen) {
            if (paletteFiltered.length > 0)
                launchCommand(paletteFiltered[paletteFocus].id)
            paletteOpen   = false
            paletteQuery  = ""
            paletteFiltered = paletteCommands
            return
        }
        if (activePanel === "switcher") {
            var app = switcherApps[switcherFocus]
            launchedApp  = app.name
            launchedIcon = app.icon
            launchedBg   = app.bg
            activeScreen = "app"
            activePanel  = ""
            return
        }
        if (activePanel !== "") return
        if (activeScreen === "lock") {
            pinLen++
            if (pinLen >= 4) { activeScreen = "home"; pinLen = 0 }
            return
        }
        if (activeScreen === "home") {
            var all = gridApps.concat(dockApps)
            var chosen = all[homeFocus]
            if (chosen) {
                launchedApp  = chosen.name
                launchedIcon = chosen.icon
                launchedBg   = chosen.bg
                activeScreen = "app"
            }
        }
    }

    function handleBack() {
        if (wifiPanelOpen)    { wifiPanelOpen = false; return }
        if (btPanelOpen)      { btPanelOpen = false; return }
        if (radialOpen)       { radialOpen = false; return }
        if (paletteOpen)      { paletteOpen = false; paletteQuery = ""; paletteFiltered = paletteCommands; return }
        if (activePanel !== "") { activePanel = ""; return }
        if (activeScreen === "app") { activeScreen = "home" }
    }

    function handleHome() {
        if (activeScreen === "lock") return
        radialOpen   = false
        paletteOpen  = false
        activePanel  = ""
        activeScreen = "home"
    }

    function handlePalette() {
        if (activeScreen === "lock") return
        paletteOpen = !paletteOpen
        if (paletteOpen) { paletteQuery = ""; paletteFiltered = paletteCommands; paletteFocus = 0 }
    }

    function handleSwitcher() {
        if (activeScreen === "lock") return
        activePanel = activePanel === "switcher" ? "" : "switcher"
    }

    function handleQS() {
        if (activeScreen === "lock") return
        wifiPanelOpen = false
        btPanelOpen   = false
        activePanel = activePanel === "qs" ? "" : "qs"
    }

    function handleNotif() {
        if (activeScreen === "lock") return
        activePanel = activePanel === "notif" ? "" : "notif"
    }

    function handleWifi() {
        if (activeScreen === "lock") return
        btPanelOpen   = false
        wifiPanelOpen = !wifiPanelOpen
        wifiFocus = 0
    }

    function handleBluetooth() {
        if (activeScreen === "lock") return
        wifiPanelOpen = false
        btPanelOpen   = !btPanelOpen
        btFocus = 0
    }

    // Any overlay open?  Used to decide whether to release keys to the app layer.
    readonly property bool anyOverlayOpen:
        radialOpen || paletteOpen || wifiPanelOpen || btPanelOpen ||
        activePanel !== ""

    function handleRadial() {
        if (activeScreen === "lock") return
        radialLayer = "system"
        radialOpen  = true
        radialFocus = 0
    }

    function navUp() {
        if (radialOpen)       { radialFocus = (radialFocus + 6) % systemRadial.length; return }
        if (paletteOpen)      { paletteFocus = Math.max(0, paletteFocus - 1); return }
        if (wifiPanelOpen)    { wifiFocus = Math.max(0, wifiFocus - 1); return }
        if (btPanelOpen)      { btFocus   = Math.max(0, btFocus   - 1); return }
        if (activeScreen === "home" && homeFocus >= gridApps.length)
            { homeFocus = gridApps.length - 1; return }
        if (activeScreen === "home" && homeFocus >= 4)
            { homeFocus -= 4 }
    }

    function navDown() {
        if (radialOpen)       { radialFocus = (radialFocus + 2) % systemRadial.length; return }
        if (paletteOpen)      { paletteFocus = Math.min(paletteFiltered.length - 1, paletteFocus + 1); return }
        if (wifiPanelOpen)    { wifiFocus = Math.min(3, wifiFocus + 1); return }  // 4 networks
        if (btPanelOpen)      { btFocus   = Math.min(3, btFocus   + 1); return }  // 4 devices
        if (activeScreen === "home") {
            var total = gridApps.length + dockApps.length
            if (homeFocus + 4 < gridApps.length)       homeFocus += 4
            else if (homeFocus < gridApps.length)       homeFocus = gridApps.length
        }
    }

    function navLeft() {
        if (radialOpen)              { radialFocus = (radialFocus + 7) % systemRadial.length; return }
        if (activePanel === "switcher") { switcherFocus = Math.max(0, switcherFocus - 1); return }
        if (activeScreen === "home") { homeFocus = Math.max(0, homeFocus - 1) }
    }

    function navRight() {
        if (radialOpen)              { radialFocus = (radialFocus + 1) % systemRadial.length; return }
        if (activePanel === "switcher") { switcherFocus = Math.min(switcherApps.length - 1, switcherFocus + 1); return }
        if (activeScreen === "home") {
            var total = gridApps.length + dockApps.length
            homeFocus = Math.min(total - 1, homeFocus + 1)
        }
    }

    function launchCommand(id) {
        if (id === "nav.lock")      { activeScreen = "lock"; pinLen = 0; return }
        if (id === "nav.home")      { handleHome(); return }
        if (id === "sys.wifi")      { paletteOpen = false; handleWifi(); return }
        if (id === "sys.bluetooth") { paletteOpen = false; handleBluetooth(); return }
        if (id.startsWith("app.")) {
            var name = id.slice(4)
            var all  = gridApps.concat(dockApps)
            var app  = all.find(a => a.name.toLowerCase() === name) ||
                       all.find(a => a.name.toLowerCase().startsWith(name))
            if (app) { launchedApp = app.name; launchedIcon = app.icon; launchedBg = app.bg; activeScreen = "app" }
        } else {
            showBanner("Action: " + id)
        }
    }

    // ─── Upper display — 1920×1080 ────────────────────────────────────────────
    PanelWindow {
        id: upperWin
        screen: Quickshell.screens[0]

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "torchform-upper"
        anchors { left: true; right: true; top: true; bottom: true }

        color: Tokens.bgBase

        Item {
            anchors.fill: parent
            focus: true

            Keys.onPressed: (ev) => {
                // --- Global shortcuts: always active (lock screen excluded) ---
                // These open/close overlays regardless of what is on screen.
                switch (ev.key) {
                    case Qt.Key_Space:  ev.accepted = true; shell.handleHome();        return
                    case Qt.Key_X:      ev.accepted = true; shell.handlePalette();     return
                    case Qt.Key_Enter:  ev.accepted = true; shell.handleSwitcher();    return
                    case Qt.Key_Z:      ev.accepted = true; shell.handleQS();          return
                    case Qt.Key_C:      ev.accepted = true; shell.handleNotif();       return
                    case Qt.Key_Tab:    ev.accepted = true; shell.handleRadial();      return
                    default: break
                }

                // --- Context-sensitive: only captured while NOT in plain app mode ---
                // When activeScreen === "app" and no overlay is open, pass nav/confirm
                // keys through (ev.accepted = false) so future real Wayland apps can
                // receive them.  Lock screen always captures everything.
                var appMode = shell.activeScreen === "app" && !shell.anyOverlayOpen
                if (appMode) {
                    ev.accepted = false
                    return
                }

                ev.accepted = true
                switch (ev.key) {
                    case Qt.Key_A:      shell.handleConfirm(); break
                    case Qt.Key_Return: shell.handleConfirm(); break
                    case Qt.Key_Escape: shell.handleBack();    break
                    case Qt.Key_B:      shell.handleBack();    break
                    case Qt.Key_Up:     shell.navUp();         break
                    case Qt.Key_Down:   shell.navDown();       break
                    case Qt.Key_Left:   shell.navLeft();       break
                    case Qt.Key_Right:  shell.navRight();      break
                    default:            ev.accepted = false
                }
            }

            // ── Status bar ────────────────────────────────────────────────
            StatusBar {
                id: statusBar
                anchors { top: parent.top; left: parent.left; right: parent.right }
                timeStr:    shell.timeStr
                appName:    shell.activeScreen === "app" ? shell.launchedApp : ""
                notifCount: shell.notifCount
                batteryPct: shell.batteryPct
                wifiOn:     shell.wifiOn
                btOn:       shell.btOn
                nowPlaying: shell.nowPlaying
            }

            // ── Content ───────────────────────────────────────────────────
            Item {
                id: contentArea
                anchors {
                    top: statusBar.bottom; bottom: hintBar.top
                    left: parent.left;     right: parent.right
                }

                LockScreen {
                    anchors.fill: parent
                    visible: shell.activeScreen === "lock"
                    timeStr: shell.timeStr
                    dateStr: shell.dateStr
                    pinLen:  shell.pinLen
                }

                HomeScreen {
                    anchors.fill: parent
                    visible:  shell.activeScreen === "home"
                    gridApps: shell.gridApps
                    dockApps: shell.dockApps
                    homeFocus: shell.homeFocus
                    onTileActivated: (idx) => { shell.homeFocus = idx; shell.handleConfirm() }
                }

                AppWindow {
                    anchors.fill: parent
                    visible:  shell.activeScreen === "app"
                    appName:  shell.launchedApp
                    appIcon:  shell.launchedIcon
                    appBg:    shell.launchedBg
                }

                // Overlays (ordered back to front) ─────────────────────────

                QuickSettings {
                    anchors.fill: parent
                    open: shell.activePanel === "qs"
                    onClosed: shell.activePanel = ""
                }

                WiFiPanel {
                    anchors.fill: parent
                    open:        shell.wifiPanelOpen
                    focusIndex:  shell.wifiFocus
                    onClosed:    shell.wifiPanelOpen = false
                    onConnectRequested: (ssid) => shell.showBanner("Connecting to " + ssid + "…")
                }

                BluetoothPanel {
                    anchors.fill: parent
                    open:        shell.btPanelOpen
                    focusIndex:  shell.btFocus
                    onClosed:    shell.btPanelOpen = false
                    onPairRequested: (addr) => shell.showBanner("Pairing " + addr + "…")
                }

                Notifications {
                    anchors.fill: parent
                    open: shell.activePanel === "notif"
                    notifCount: shell.notifCount
                    onClosed: shell.activePanel = ""
                }

                AppSwitcher {
                    anchors.fill: parent
                    open: shell.activePanel === "switcher"
                    apps: shell.switcherApps
                    focusIndex: shell.switcherFocus
                    onAppSelected: (idx) => { shell.switcherFocus = idx; shell.handleConfirm() }
                    onClosed: shell.activePanel = ""
                }

                CommandPalette {
                    anchors.fill: parent
                    open:       shell.paletteOpen
                    query:      shell.paletteQuery
                    commands:   shell.paletteFiltered
                    focusIndex: shell.paletteFocus
                    onCommandSelected: (idx) => { shell.paletteFocus = idx; shell.handleConfirm() }
                    onClosed: { shell.paletteOpen = false; shell.paletteQuery = ""; shell.paletteFiltered = shell.paletteCommands }
                }

                RadialMenu {
                    anchors.fill: parent
                    open:       shell.radialOpen
                    activeLayer: shell.radialLayer
                    items:      shell.systemRadial
                    focusIndex: shell.radialFocus
                    onItemActivated: (idx) => { shell.radialFocus = idx; shell.handleConfirm() }
                    onDismissed: shell.radialOpen = false
                }

                // Banner toast
                Rectangle {
                    visible: shell.bannerVisible
                    anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 12 }
                    width: bannerText.implicitWidth + 40
                    height: 36
                    radius: 18
                    color: Tokens.bgElevated
                    border.color: Tokens.accent
                    border.width: 1

                    opacity: shell.bannerVisible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Tokens.animNormal } }
                    y: shell.bannerVisible ? 0 : -40
                    Behavior on y { NumberAnimation { duration: Tokens.animNormal; easing.type: Easing.OutCubic } }

                    Text {
                        id: bannerText
                        anchors.centerIn: parent
                        text: shell.bannerText
                        font.pixelSize: 13
                        font.family: Tokens.fontSans
                        color: Tokens.textPrimary
                    }
                }
            }

            // ── Hint bar ──────────────────────────────────────────────────
            HintBar {
                id: hintBar
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                hints: shell.currentHints
            }
        }
    }

    // ─── Lower display — 640×480 ──────────────────────────────────────────────
    PanelWindow {
        visible: Quickshell.screens.length > 1
        screen:  Quickshell.screens.length > 1 ? Quickshell.screens[1] : Quickshell.screens[0]

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.namespace: "torchform-lower"
        anchors { left: true; right: true; top: true; bottom: true }

        LowerPanel {
            anchors.fill: parent
            timeStr:     shell.timeStr
            activeApp:   shell.launchedApp
            batteryPct:  shell.batteryPct
            paletteOpen: shell.paletteOpen
            radialOpen:  shell.radialOpen
        }
    }
}
