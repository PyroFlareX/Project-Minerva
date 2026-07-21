import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Torchform.Gamepad
import "."

// Torchform QuickShell Demo
// Upper display: 1920×1080  (Quickshell.screens[0])
// Lower display:  640×480   (Quickshell.screens[1], if present)
//
// Primary input is the controller, via the Torchform.Gamepad plugin which reads
// the torchform-inputd virtual pad (no faked keypresses). A real keyboard still
// works as a dev convenience — both drive the same handler functions.
//
// Controller map               Keyboard (dev)
//   South  → Confirm             A          → Confirm
//   East   → Back                Esc / B    → Back
//   West   → Palette             X          → Palette
//   North  → Radial              Tab        → Radial
//   D-pad  → Navigate            Arrow keys → Navigate
//   Start  → Home                Space      → Home
//   Select → App Switcher        Enter      → App Switcher
//   R1     → Quick Settings      Z          → Quick Settings
//   L1     → Notifications       C          → Notifications
//   Mode   → Home (guide)
// Chord/multiclick actions (from input.toml): "switcher", "power_menu", "home".

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
    property string paletteQuery:  ""
    property int    paletteFocus:  0
    property var paletteFiltered: {
        var q = paletteQuery.toLowerCase()
        if (!q) return paletteCommands
        return paletteCommands.filter(function(c) {
            return c.label.toLowerCase().indexOf(q) >= 0 ||
                   c.category.toLowerCase().indexOf(q) >= 0 ||
                   c.id.toLowerCase().indexOf(q) >= 0
        })
    }
    onPaletteQueryChanged: paletteFocus = 0

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

    Process {
        id: launcherProc
        stdout: StdioCollector {
            onStreamFinished: {
                var msg = text.trim().split("|").slice(1).join("|")
                if (msg.length === 0) msg = text.trim()
                if (msg.length > 0) shell.showBanner(msg)
            }
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
            return [{key:"↑↓←→", label:"Type"}, {key:"A", label:"Key"}, {key:"✓", label:"Launch"}, {key:"Esc", label:"Close"}]
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
        if (oskOpen)      { osk.activateKey(); return }
        if (wifiPanelOpen) {
            wifiPanel.activateFocused()
            return
        }
        if (btPanelOpen) {
            btPanel.activateFocused()
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
            paletteOpen  = false
            paletteQuery = ""
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
        if (paletteOpen)      { paletteOpen = false; paletteQuery = ""; return }
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
        if (paletteOpen) { paletteQuery = ""; paletteFocus = 0; osk.reset() }
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

    // Any overlay open?  Used to decide whether to release input to the app layer.
    readonly property bool anyOverlayOpen:
        radialOpen || paletteOpen || wifiPanelOpen || btPanelOpen ||
        activePanel !== ""

    // In "app mode" the shell yields nav/confirm/back to the focused Wayland app
    // (which reads the same virtual pad directly); global buttons still escape it.
    readonly property bool appMode: activeScreen === "app" && !anyOverlayOpen

    // OSK is visible whenever the palette is open (extends to WiFi passphrase in Phase 3).
    readonly property bool oskOpen: paletteOpen

    function handleRadial() {
        if (activeScreen === "lock") return
        radialLayer = "system"
        radialOpen  = true
        radialFocus = 0
    }

    function navUp() {
        if (oskOpen)          { osk.navUp(); return }
        if (radialOpen)       { radialFocus = (radialFocus + 6) % systemRadial.length; return }
        if (wifiPanelOpen)    { wifiFocus = Math.max(0, wifiFocus - 1); return }
        if (btPanelOpen)      { btFocus   = Math.max(0, btFocus   - 1); return }
        if (activeScreen === "home" && homeFocus >= gridApps.length)
            { homeFocus = gridApps.length - 1; return }
        if (activeScreen === "home" && homeFocus >= 4)
            { homeFocus -= 4 }
    }

    function navDown() {
        if (oskOpen)          { osk.navDown(); return }
        if (radialOpen)       { radialFocus = (radialFocus + 2) % systemRadial.length; return }
        if (wifiPanelOpen)    { wifiFocus = Math.min(Math.max(0, wifiPanel.itemCount - 1), wifiFocus + 1); return }
        if (btPanelOpen)      { btFocus   = Math.min(Math.max(0, btPanel.itemCount - 1), btFocus   + 1); return }
        if (activeScreen === "home") {
            var total = gridApps.length + dockApps.length
            if (homeFocus + 4 < gridApps.length)       homeFocus += 4
            else if (homeFocus < gridApps.length)       homeFocus = gridApps.length
        }
    }

    function navLeft() {
        if (oskOpen)                 { osk.navLeft(); return }
        if (radialOpen)              { radialFocus = (radialFocus + 7) % systemRadial.length; return }
        if (activePanel === "switcher") { switcherFocus = Math.max(0, switcherFocus - 1); return }
        if (activeScreen === "home") { homeFocus = Math.max(0, homeFocus - 1) }
    }

    function navRight() {
        if (oskOpen)                 { osk.navRight(); return }
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
            if (name === "browser" || name === "files" || name === "terminal") {
                launcherProc.command = ["sh", "-lc", "cd \"$HOME/projects/torchform-guishell\" && sh ./torchform-control.sh launch \"$1\"", "torchform-launch", name]
                launcherProc.running = true
            }
        } else {
            showBanner("Action: " + id)
        }
    }

    // ─── Controller input (primary) ───────────────────────────────────────────
    // Maps virtual-pad buttons to the same handlers the keyboard uses. Global
    // buttons act even over a focused app; nav/confirm/back are suppressed in
    // appMode so the focused app receives them directly off the virtual pad.
    function onPadButton(name) {
        if (activeScreen === "lock") {            // only Confirm wakes the lock screen
            if (name === "south") handleConfirm()
            return
        }
        switch (name) {                            // always-global (escape the app)
            case "start":  handleHome();     return
            case "mode":   handleHome();     return
            case "select": handleSwitcher(); return
            case "west":   handlePalette();  return
            case "north":  handleRadial();   return
            case "r1":     handleQS();       return
            case "l1":     handleNotif();    return
        }
        if (appMode) return                        // pass nav/confirm/back to the app
        switch (name) {
            case "south":      handleConfirm(); break
            case "east":       handleBack();    break
            case "dpad_up":    navUp();    break
            case "dpad_down":  navDown();  break
            case "dpad_left":  navLeft();  break
            case "dpad_right": navRight(); break
        }
    }

    // Chord / multiclick actions from input.toml (resolved by the plugin manifest).
    function onPadAction(name) {
        if (activeScreen === "lock") return
        switch (name) {
            case "switcher":   handleSwitcher(); break
            case "home":       handleHome();     break
            case "power_menu": showBanner("Power menu"); break
            default:           showBanner("Action: " + name)
        }
    }

    // D-pad auto-repeat lives here (not in the daemon — the virtual pad keeps true
    // physical state for games). Held direction repeats after a delay, then faster.
    property string heldDir:      ""
    property int    repeatDelayMs: 350
    property int    repeatRateMs:  90

    Timer {
        id: navRepeat
        repeat: true
        onTriggered: {
            interval = shell.repeatRateMs   // first tick was the delay; speed up after
            if (shell.appMode) return
            switch (shell.heldDir) {
                case "up":    shell.navUp();    break
                case "down":  shell.navDown();  break
                case "left":  shell.navLeft();  break
                case "right": shell.navRight(); break
            }
        }
    }

    Connections {
        target: Gamepad
        function onButtonPressed(name) {
            shell.onPadButton(name)
            var dir = ({ dpad_up: "up", dpad_down: "down",
                         dpad_left: "left", dpad_right: "right" })[name]
            if (dir === undefined) return
            shell.heldDir = dir
            navRepeat.interval = shell.repeatDelayMs
            navRepeat.restart()
        }
        function onButtonReleased(name) {
            var dir = ({ dpad_up: "up", dpad_down: "down",
                         dpad_left: "left", dpad_right: "right" })[name]
            if (dir !== undefined && shell.heldDir === dir) {
                navRepeat.stop()
                shell.heldDir = ""
            }
        }
        function onActionTriggered(name) { shell.onPadAction(name) }
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
                // When in appMode (app screen, no overlay) pass nav/confirm keys
                // through (ev.accepted = false) so the focused Wayland app gets them.
                // Lock screen always captures everything.
                if (shell.appMode) {
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
                    id: wifiPanel
                    anchors.fill: parent
                    open:        shell.wifiPanelOpen
                    focusIndex:  shell.wifiFocus
                    onClosed:    shell.wifiPanelOpen = false
                    onNotice: (msg) => shell.showBanner(msg)
                }

                BluetoothPanel {
                    id: btPanel
                    anchors.fill: parent
                    open:        shell.btPanelOpen
                    focusIndex:  shell.btFocus
                    onClosed:    shell.btPanelOpen = false
                    onNotice: (msg) => shell.showBanner(msg)
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
                    onClosed: { shell.paletteOpen = false; shell.paletteQuery = "" }
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

                // OSK — sits at the bottom, visible when palette is open.
                OnScreenKeyboard {
                    id: osk
                    anchors.fill: parent
                    open: shell.paletteOpen
                    onKeyEmitted: (key) => {
                        if (key === "\b") {
                            if (shell.paletteQuery.length > 0)
                                shell.paletteQuery = shell.paletteQuery.slice(0, -1)
                        } else {
                            shell.paletteQuery += key
                        }
                    }
                    onCloseRequested: {
                        if (shell.paletteFiltered.length > 0)
                            shell.launchCommand(shell.paletteFiltered[shell.paletteFocus].id)
                        shell.paletteOpen = false
                        shell.paletteQuery = ""
                    }
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
