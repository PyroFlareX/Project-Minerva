import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Torchform.Gamepad
import "data.js" as Data
import "."
// Active outputs are assigned by geometry: largest area → upper display,
// smallest area → lower companion.  The launcher may rotate/scale them.
// QML sizes are designed for the configured logical role geometry.
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

    // Input focus is explicit: every modal overlay owns the controller and
    // keyboard focus until it closes.  "app"/"home" are the return targets.
    property string focusOwner: "lock"
    property string focusReturnOwner: ""
    property int    focusEpoch: 0
    property int    radialFocus:  0
    property int    quickSettingsFocus: 0
    property int    notificationsFocus: 0
    property int    homeFocus:    0
    property int    pinLen:       0
    property int    notifCount:   0
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

    // WiFi / Bluetooth panels (nested overlays inside quick settings).
    property bool wifiPanelOpen: false
    property int  wifiFocus:     0
    property bool btPanelOpen:   false
    property int  btFocus:       0

    // Runtime values are separate from the data-only layout registry.
    property var quickSettingsSliderValues: []
    property var quickSettingsTileStates:   []
    property bool dndEnabled: false
    property int quickActionPendingIndex: -1
    property int quickSliderPendingIndex: -1
    property int quickSliderPendingPrevious: 0

    // Device-backed app state.  These values are intentionally plain QML data
    // so the shell can be restarted after editing scripts or data.js.
    property string batteryStatus: "unknown"
    property bool   batteryKnown: false
    property bool   lowBattery: false
    property string cpuLoad: "—"
    property string memoryUse: "—"
    property string diskUse: "—"
    property string temperature: "—"
    property string uptime: "—"
    property string sysmonUpdated: "waiting"
    property var    sysmonMetrics: ({})
    property var    fileEntries: []
    property string filePath: "~"
    property int    fileFocus: 0
    property bool   filesLoading: false
    property string filesStatus: ""
    property var    terminalLines: [
        "Torchform command runner",
        "Type a shell command and press Enter.",
        ""
    ]
    property bool terminalRunning: false
    property string terminalLast: ""

    readonly property var upperScreen: findScreen(true)
    readonly property var lowerScreen: findScreen(false)

    function findScreen(largest) {
        var chosen = null
        for (var i = 0; i < Quickshell.screens.length; ++i) {
            var candidate = Quickshell.screens[i]
            if (!chosen || (candidate.width * candidate.height > chosen.width * chosen.height) === largest)
                chosen = candidate
        }
        return chosen || Quickshell.screens[0]
    }

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
    Process {
        id: quickActionProc
        stdout: StdioCollector {
            onStreamFinished: {
                var raw = text.trim()
                if (raw.length === 0) return
                var parts = raw.split("|")
                var kind = parts[0]
                var message = parts.slice(kind === "state" ? 2 : 1).join("|")
                if (kind === "state" && shell.quickActionPendingIndex >= 0) {
                    var states = shell.quickSettingsTileStates.slice()
                    states[shell.quickActionPendingIndex] = parts[1] === "on"
                    shell.quickSettingsTileStates = states
                    if (shell.quickSettingsConfig.tiles[shell.quickActionPendingIndex].action === "sys.dnd")
                        shell.dndEnabled = parts[1] === "on"
                } else if (kind === "error" && shell.quickSliderPendingIndex >= 0) {
                    var values = shell.quickSettingsSliderValues.slice()
                    values[shell.quickSliderPendingIndex] = shell.quickSliderPendingPrevious
                    shell.quickSettingsSliderValues = values
                }
                shell.quickActionPendingIndex = -1
                shell.quickSliderPendingIndex = -1
                shell.showBanner(message || raw)
                shell.writeState()
            }
        }
    }
    Process {
        id: quickStateProc
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = text.trim().split("|")
                if (parts[0] !== "state" || parts.length < 3) return
                if (parts[1] === "dnd") {
                    shell.dndEnabled = parts[2] === "on"
                    var tiles = shell.quickSettingsTileStates.slice()
                    var dndIndex = -1
                    var configuredTiles = shell.quickSettingsConfig.tiles || []
                    for (var i = 0; i < configuredTiles.length; i++) {
                        if (configuredTiles[i].action === "sys.dnd") {
                            dndIndex = i
                            break
                        }
                    }
                    if (dndIndex >= 0) {
                        tiles[dndIndex] = shell.dndEnabled
                        shell.quickSettingsTileStates = tiles
                    }
                    shell.writeState()
                }
            }
        }
    }



    Process {
        id: applicationsProc
        stdout: StdioCollector {
            onStreamFinished: {
                var dynamicApps = []
                var dynamicCommands = []
                var seen = {}
                Data.gridApps.concat(Data.dockApps).forEach(function(app) {
                    seen[app.name.toLowerCase()] = true
                })
                var raw = text.trim()
                if (raw.length > 0) {
                    raw.split("\n").forEach(function(line) {
                        var parts = line.split("\t")
                        if (parts[0] !== "app" || parts.length < 5) return
                        var name = parts[1].trim()
                        var key = name.toLowerCase()
                        var exec = parts.slice(3, parts.length - 1).join("\t").trim()
                        if (!name || !exec || seen[key]) return
                        seen[key] = true
                        var icon = parts[2] || "🚀"
                        var kind = parts[parts.length - 1] || "executable"
                        var app = {
                            name: name,
                            icon: icon,
                            bg: "#151a2a",
                            exec: exec,
                            external: true
                        }
                        dynamicApps.push(app)
                        dynamicCommands.push({
                            id: "launcher:" + dynamicApps.length,
                            label: name,
                            category: kind === "desktop" ? "Applications" : "Local Commands",
                            icon: icon,
                            bg: "#151a2a",
                            shortcut: "",
                            exec: exec,
                            external: true
                        })
                    })
                }
                var nextGrid = Data.gridApps.slice()
                dynamicApps.forEach(function(app, index) {
                    app.idx = nextGrid.length
                    nextGrid.push(app)
                })
                var nextDock = []
                Data.dockApps.forEach(function(app, index) {
                    var copy = {}
                    for (var key in app) copy[key] = app[key]
                    copy.idx = nextGrid.length + index
                    nextDock.push(copy)
                })
                shell.gridApps = nextGrid
                shell.dockApps = nextDock
                shell.paletteCommands = Data.paletteCommands.concat(dynamicCommands)
                var total = nextGrid.length + nextDock.length
                shell.homeFocus = Math.min(shell.homeFocus, Math.max(0, total - 1))
                shell.writeState()
            }
        }
    }


    Timer {
        id: bannerTimer
        interval: 3500
        onTriggered: shell.bannerVisible = false
    }

    function showBanner(text) {
        shell.bannerText = text
        shell.bannerVisible = true
        bannerTimer.restart()
    }

    function runControl(proc, args) {
        proc.command = [
            "sh", "-lc",
            "cd \"$HOME/projects/torchform-guishell\" && sh ./torchform-control.sh \"$@\"",
            "torchform-control"
        ].concat(args)
        proc.running = true
    }

    Process {
        id: filesProc
        stdout: StdioCollector {
            onStreamFinished: {
                var rows = []
                var status = ""
                var currentPath = shell.filePath
                var raw = text.trim()
                if (raw.length > 0) {
                    raw.split("\n").forEach(function(line) {
                        var parts = line.split("\t")
                        if (parts[0] === "path") {
                            currentPath = parts.slice(1).join("\t")
                        } else if (parts[0] === "status") {
                            status = parts.slice(1).join("\t")
                        } else if (parts[0] === "entry" && parts.length >= 5) {
                            rows.push({
                                name: parts[1],
                                kind: parts[2],
                                size: parts[3] === "0" ? "" : parts[3] + " B",
                                path: parts.slice(4).join("\t")
                            })
                        }
                    })
                }
                shell.filePath = currentPath
                shell.fileEntries = rows
                shell.fileFocus = Math.max(0, Math.min(shell.fileFocus, Math.max(0, rows.length - 1)))
                shell.filesStatus = status
                shell.filesLoading = false
                shell.writeState()
            }
        }
    }

    Process {
        id: sysmonProc
        stdout: StdioCollector {
            onStreamFinished: {
                var metrics = {}
                var raw = text.trim()
                var line = raw.split("\n")[0] || ""
                line.split("|").forEach(function(part) {
                    var at = part.indexOf("=")
                    if (at > 0)
                        metrics[part.slice(0, at)] = part.slice(at + 1)
                })
                var battery = Number(metrics.battery)
                shell.sysmonMetrics = metrics
                shell.cpuLoad = metrics.load || "—"
                shell.memoryUse = metrics.memory || "—"
                shell.diskUse = metrics.disk || "—"
                shell.temperature = metrics.temperature || "—"
                shell.uptime = metrics.uptime || "—"
                shell.batteryKnown = Number.isFinite(battery) && battery >= 0
                if (shell.batteryKnown) shell.batteryPct = battery
                shell.batteryStatus = metrics.battery_status || "unknown"
                shell.lowBattery = shell.batteryKnown && shell.batteryPct <= 20 &&
                                   shell.batteryStatus.toLowerCase().indexOf("discharg") >= 0
                metrics.batteryLow = shell.lowBattery
                shell.sysmonMetrics = metrics
                shell.sysmonUpdated = Qt.formatTime(new Date(), "hh:mm:ss")
                shell.writeState()
            }
        }
    }

    Process {
        id: terminalProc
        stdout: StdioCollector {
            onStreamFinished: {
                var output = text.replace(/\r/g, "").split("\n")
                var lines = shell.terminalLines.concat(output)
                while (lines.length > 200) lines.shift()
                shell.terminalLines = lines
                shell.terminalLast = ""
                for (var i = output.length - 1; i >= 0; --i) {
                    var candidate = output[i].trim()
                    if (candidate !== "" && candidate.indexOf("[exit ") !== 0) {
                        shell.terminalLast = candidate
                        break
                    }
                }
                shell.terminalRunning = false
                shell.writeState()
            }
        }
    }

    Process { id: stateProc }

    Timer {
        id: sysmonTimer
        interval: shell.launchedApp === "Sysmon" ? 2000 : 30000
        running: true
        repeat: true
        onTriggered: shell.sampleSysmon()
    }

    Timer {
        id: stateTimer
        interval: 1000
        running: true
        repeat: true
        onTriggered: shell.writeState()
    }

    function sampleSysmon() {
        if (!sysmonProc.running) shell.runControl(sysmonProc, ["sysmon"])
    }

    function writeState() {
        if (stateProc.running) return
        var state = {
            screen: activeScreen,
            panel: activePanel,
            palette: paletteOpen,
            paletteFocus: paletteFocus,
            radial: radialOpen,
            radialFocus: radialFocus,
            app: launchedApp,
            homeFocus: homeFocus,
            fileFocus: fileFocus,
            filesReady: fileEntries.length > 0,
            terminalLast: terminalLast,
            sysmonReady: sysmonMetrics.load !== undefined,
            batteryKnown: batteryKnown,
            batteryPct: batteryPct,
            batteryStatus: batteryStatus,
            lowBattery: lowBattery,
            focusOwner: focusOwner,
            focusCaptured: anyOverlayOpen,
            focusEpoch: focusEpoch,
            overlayLayoutVersion: overlayConfig.version,
            quickSettingsFocus: quickSettingsFocus,
            quickSettingsSliderValues: quickSettingsSliderValues,
            quickSettingsTileStates: quickSettingsTileStates,
            dndEnabled: dndEnabled,
            notificationsFocus: notificationsFocus,
            switcherFocus: switcherFocus,
            upper: upperScreen ? upperScreen.name : "",
            lower: lowerScreen ? lowerScreen.name : ""
        }
        shell.runControl(stateProc, ["state-write", JSON.stringify(state)])
    }

    function refreshFiles(path) {
        if (path !== undefined && path !== "") filePath = path
        filesLoading = true
        filesStatus = ""
        runControl(filesProc, ["files-list", filePath])
    }

    function openFileEntry(index) {
        var entry = fileEntries[index]
        if (!entry) return
        if (entry.kind === "dir") {
            filePath = entry.path
            fileFocus = 0
            refreshFiles()
        } else {
            showBanner("Selected " + entry.name)
        }
    }

    function parentFiles() {
        if (fileEntries.length > 0 && fileEntries[0].name === "..") {
            openFileEntry(0)
        } else {
            refreshFiles("/")
        }
    }

    function submitTerminal(command) {
        command = command.trim()
        if (command.length === 0 || terminalRunning) return
        terminalLines = terminalLines.concat(["torchform@minerva:~$ " + command])
        terminalRunning = true
        runControl(terminalProc, ["terminal-exec", command])
    }

    function launchExternal(app) {
        launcherProc.command = [
            "sh", "-lc",
            "cd \"$HOME/projects/torchform-guishell\" && sh ./torchform-control.sh launch \"$1\"",
            "torchform-launch", app
        ]
        launcherProc.running = true
    }

    function launchExternalExec(command) {
        launcherProc.command = [
            "sh", "-lc",
            "cd \"$HOME/projects/torchform-guishell\" && sh ./torchform-control.sh launch-exec \"$1\"",
            "torchform-launch-exec", command
        ]
        launcherProc.running = true
    }

    function refreshApplications() {
        applicationsProc.command = [
            "sh", "-lc",
            "cd \"$HOME/projects/torchform-guishell\" && sh ./torchform-control.sh applications-list",
            "torchform-applications"
        ]
        applicationsProc.running = true
    }
    function refreshQuickSettingsState() {
        runControl(quickStateProc, ["quick-state", "dnd"])
    }


    // ─── Data-driven UI registry (edit data.js; no QML rebuild required) ─────
    readonly property var overlayConfig:       Data.overlayConfig
    readonly property var radialConfig:        overlayConfig.radial
    readonly property var quickSettingsConfig:  overlayConfig.quickSettings
    readonly property var notificationsConfig:  overlayConfig.notifications
    readonly property var switcherConfig:      overlayConfig.switcher
    property var gridApps:                     Data.gridApps
    property var dockApps:                     Data.dockApps
    property var paletteCommands:              Data.paletteCommands
    readonly property var switcherApps:         switcherConfig.apps

    function resetOverlayRuntime() {
        var sliders = []
        ;(quickSettingsConfig.sliders || []).forEach(function(slider) {
            sliders.push(Number(slider.value) || 0)
        })
        var tiles = []
        ;(quickSettingsConfig.tiles || []).forEach(function(tile) {
            tiles.push(!!tile.initialOn)
        })
        quickSettingsSliderValues = sliders
        quickSettingsTileStates = tiles
        var dndTile = (quickSettingsConfig.tiles || []).find(function(tile) {
            return tile.action === "sys.dnd"
        })
        dndEnabled = !!(dndTile && dndTile.initialOn)
        quickSettingsFocus = quickSettingsConfig.initialFocus || 0
        notificationsFocus = notificationsConfig.initialFocus || 0
        switcherFocus = switcherConfig.initialFocus || 0
        notifCount = (notificationsConfig.items || []).length
    }

    Component.onCompleted: {
        resetOverlayRuntime()
        refreshApplications()
        refreshQuickSettingsState()
    }

    // ─── Hint bar content ────────────────────────────────────────────────────
    property var currentHints: {
        if (activeScreen === "lock")
            return [{button:"A", label:"Unlock"}]
        if (wifiPanelOpen)
            return [{button:"D-PAD", label:"Navigate"}, {button:"A", label:"Connect"}, {button:"B", label:"Close"}]
        if (btPanelOpen)
            return [{button:"D-PAD", label:"Navigate"}, {button:"A", label:"Pair"}, {button:"B", label:"Close"}]
        if (radialOpen)
            return [{button:"D-PAD", label:"Select"}, {button:"A", label:"Activate"}, {button:"B", label:"Close"}]
        if (paletteOpen)
            return [{button:"D-PAD", label:"Navigate"}, {button:"A", label:"Type / Launch"}, {button:"B", label:"Close"}]
        if (activePanel === "switcher")
            return [{button:"D-PAD", label:"Select"}, {button:"A", label:"Switch"}, {button:"B", label:"Close"}]
        if (activePanel !== "")
            return [{button:"D-PAD", label:"Navigate"}, {button:"B", label:"Close"}]
        if (activeScreen === "home")
            return [{button:"D-PAD", label:"Navigate"}, {button:"A", label:"Launch"}, {button:"X", label:"Palette"}, {button:"SELECT", label:"Apps"}]
        if (activeScreen === "app")
            return [{button:"START", label:"Home"}, {button:"X", label:"Palette"}, {button:"L1", label:"Notifications"}, {button:"R1", label:"Quick Settings"}]
        return []
    }

    // ─── Focus ownership ────────────────────────────────────────────────────
    function baseFocusOwner() {
        if (activeScreen === "app") return "app"
        return activeScreen
    }

    function claimInputFocus(owner) {
        focusOwner = owner
        focusEpoch += 1
        upperInput.focus = true
        upperInput.forceActiveFocus()
    }

    function releaseOverlayFocus() {
        var owner = baseFocusOwner()
        claimInputFocus(owner)
        if (owner === "app" && launchedApp === "Terminal")
            appWindow.focusTerminalInput()
    }

    function closeAllOverlays() {
        radialOpen = false
        paletteOpen = false
        activePanel = ""
        wifiPanelOpen = false
        btPanelOpen = false
        focusReturnOwner = ""
    }

    function openExclusiveOverlay(owner) {
        closeAllOverlays()
        claimInputFocus(owner)
    }

    function closeNestedOverlay() {
        wifiPanelOpen = false
        btPanelOpen = false
        var owner = focusReturnOwner || baseFocusOwner()
        focusReturnOwner = ""
        claimInputFocus(owner)
        writeState()
    }

    // ─── Action functions ─────────────────────────────────────────────────────
    function openApp(app) {
        if (!app) return
        launchedApp  = app.name
        launchedIcon = app.icon
        launchedBg   = app.bg
        activeScreen = "app"
        claimInputFocus("app")
        fileFocus = 0
        if (app.name === "Files") {
            filePath = "~"
            refreshFiles()
        } else if (app.name === "Sysmon") {
            sampleSysmon()
        } else if (app.name === "Terminal") {
            appWindow.focusTerminalInput()
        } else if (app.external && app.exec) {
            launchExternalExec(app.exec)
        }
        writeState()
    }

    function handleConfirm() {
        if (wifiPanelOpen) {
            wifiPanel.activateFocused()
            return
        }
        if (btPanelOpen) {
            btPanel.activateFocused()
            return
        }
        if (radialOpen) {
            var radialItem = radialConfig.items[radialFocus]
            radialOpen = false
            claimInputFocus(baseFocusOwner())
            if (radialItem && radialItem.id) launchCommand(radialItem.id)
            else if (radialItem) showBanner(radialItem.label + " activated")
            writeState()
            return
        }
        if (paletteOpen) {
            var command = paletteFiltered.length > 0 ? paletteFiltered[paletteFocus] : null
            paletteOpen = false
            paletteQuery = ""
            osk.reset()
            claimInputFocus(baseFocusOwner())
            if (command) launchCommand(command.id)
            writeState()
            return
        }
        if (activePanel === "qs") {
            activateQuickSettings()
            return
        }
        if (activePanel === "notif") {
            activateNotification()
            return
        }
        if (activePanel === "switcher") {
            var switcherApp = switcherApps[switcherFocus]
            var allApps = gridApps.concat(dockApps)
            var chosen = allApps.find(function(candidate) {
                return switcherApp && candidate.name === switcherApp.name
            })
            closeAllOverlays()
            openApp(chosen)
            releaseOverlayFocus()
            writeState()
            return
        }
        if (activeScreen === "lock") {
            pinLen++
            if (pinLen >= 4) {
                activeScreen = "home"
                pinLen = 0
                homeFocus = 0
                claimInputFocus("home")
            }
            writeState()
            return
        }
        if (activeScreen === "home") {
            openApp(gridApps.concat(dockApps)[homeFocus])
            return
        }
        if (activeScreen === "app" && launchedApp === "Files") {
            openFileEntry(fileFocus)
        } else if (activeScreen === "app" && launchedApp === "Sysmon") {
            sampleSysmon()
        } else if (activeScreen === "app" && launchedApp === "Terminal") {
            appWindow.submitTerminalInput()
        }
    }

    function activateQuickSettings() {
        var sliderCount = quickSettingsConfig.sliders.length
        if (quickSettingsFocus < sliderCount) {
            showBanner(quickSettingsConfig.sliders[quickSettingsFocus].label + " " +
                       quickSettingsSliderValues[quickSettingsFocus] + "%")
            return
        }
        var tileIndex = quickSettingsFocus - sliderCount
        var tile = quickSettingsConfig.tiles[tileIndex]
        if (!tile) return
        if (tile.action === "sys.wifi") {
            handleWifi()
            return
        }
        if (tile.action === "sys.bluetooth") {
            handleBluetooth()
            return
        }
        var target = quickSettingsTileStates[tileIndex] ? "off" : "on"
        quickActionPendingIndex = tileIndex
        runControl(quickActionProc, ["quick-action", tile.action, target])
        writeState()
    }

    function activateNotification() {
        if (dndEnabled) {
            showBanner("Do Not Disturb is enabled")
            return
        }
        var item = notificationsConfig.items[notificationsFocus]
        if (item) showBanner(item.app + ": " + item.title)
        writeState()
    }

    function adjustQuickSettings(delta) {
        var index = quickSettingsFocus
        var slider = quickSettingsConfig.sliders[index]
        if (!slider) return
        var values = quickSettingsSliderValues.slice()
        var step = Number(slider.step) || 1
        var previous = Number(values[index]) || 0
        var next = previous + delta * step
        next = Math.max(Number(slider.min) || 0, Math.min(Number(slider.max) || 100, next))
        values[index] = next
        quickSettingsSliderValues = values
        quickSliderPendingIndex = index
        quickSliderPendingPrevious = previous
        runControl(quickActionProc, ["quick-slider", slider.id, delta < 0 ? "down" : "up"])
        writeState()

    }

    function navQuickSettings(direction) {
        var sliders = quickSettingsConfig.sliders || []
        var tiles = quickSettingsConfig.tiles || []
        var sliderCount = sliders.length
        var columns = Math.max(1, Number(quickSettingsConfig.columns) || 2)
        var total = sliderCount + tiles.length
        if (total === 0) return
        var focus = Math.max(0, Math.min(total - 1, quickSettingsFocus))
        if (focus < sliderCount) {
            if (direction === "up") focus = Math.max(0, focus - 1)
            if (direction === "down") focus = Math.min(sliderCount, focus + 1)
            if (direction === "left" || direction === "right") return
            quickSettingsFocus = focus
            return
        }
        var tileIndex = focus - sliderCount
        var row = Math.floor(tileIndex / columns)
        var column = tileIndex % columns
        var rows = Math.ceil(tiles.length / columns)
        if (direction === "left") column = Math.max(0, column - 1)
        if (direction === "right") column = Math.min(columns - 1, column + 1)
        if (direction === "up") {
            if (row === 0) {
                quickSettingsFocus = Math.max(0, sliderCount - 1)
                return
            }
            row -= 1
        }
        if (direction === "down") row = Math.min(rows - 1, row + 1)
        var nextTile = Math.min(tiles.length - 1, row * columns + column)
        quickSettingsFocus = sliderCount + Math.max(0, nextTile)
    }

    function navNotifications(direction) {
        var count = dndEnabled ? 0 : (notificationsConfig.items || []).length
        if (count === 0) {
            notificationsFocus = 0
            return
        }
        if (direction === "up")
            notificationsFocus = Math.max(0, notificationsFocus - 1)
        else if (direction === "down")
            notificationsFocus = Math.min(count - 1, notificationsFocus + 1)
    }

    function handleBack() {
        if (wifiPanelOpen || btPanelOpen) {
            closeNestedOverlay()
            return
        }
        if (radialOpen) {
            radialOpen = false
            releaseOverlayFocus()
            writeState()
            return
        }
        if (paletteOpen) {
            paletteOpen = false
            paletteQuery = ""
            osk.reset()
            releaseOverlayFocus()
            writeState()
            return
        }
        if (activePanel !== "") {
            closeAllOverlays()
            releaseOverlayFocus()
            writeState()
            return
        }
        if (activeScreen === "app" && launchedApp === "Files" &&
            fileEntries.length > 0 && fileEntries[0].name === "..") {
            parentFiles()
            return
        }
        if (activeScreen === "app") {
            activeScreen = "home"
            releaseOverlayFocus()
            writeState()
        }
    }

    function handleHome() {
        if (activeScreen === "lock") return
        closeAllOverlays()
        activeScreen = "home"
        homeFocus = 0
        releaseOverlayFocus()
        writeState()
    }

    function handlePalette() {
        if (activeScreen === "lock") return
        if (paletteOpen) {
            paletteOpen = false
            paletteQuery = ""
            osk.reset()
            releaseOverlayFocus()
            writeState()
            return
        }
        openExclusiveOverlay("palette")
        paletteOpen = true
        paletteQuery = ""
        paletteFocus = 0
        osk.reset()
        writeState()
    }

    function handleSwitcher() {
        if (activeScreen === "lock") return
        if (activePanel === "switcher") {
            closeAllOverlays()
            releaseOverlayFocus()
            writeState()
            return
        }
        openExclusiveOverlay("switcher")
        switcherFocus = switcherConfig.initialFocus || 0
        activePanel = "switcher"
        writeState()
    }

    function handleQS() {
        if (activeScreen === "lock") return
        if (activePanel === "qs" && !wifiPanelOpen && !btPanelOpen) {
            closeAllOverlays()
            releaseOverlayFocus()
            writeState()
            return
        }
        openExclusiveOverlay("quick-settings")
        activePanel = "qs"
        quickSettingsFocus = quickSettingsConfig.initialFocus || 0
        writeState()
    }

    function handleNotif() {
        if (activeScreen === "lock") return
        if (activePanel === "notif") {
            closeAllOverlays()
            releaseOverlayFocus()
            writeState()
            return
        }
        openExclusiveOverlay("notifications")
        activePanel = "notif"
        notificationsFocus = notificationsConfig.initialFocus || 0
        writeState()
    }

    function handleWifi() {
        if (activeScreen === "lock") return
        if (wifiPanelOpen) {
            closeNestedOverlay()
            return
        }
        focusReturnOwner = focusOwner
        btPanelOpen = false
        wifiPanelOpen = true
        wifiFocus = 0
        claimInputFocus("wifi")
        writeState()
    }

    function handleBluetooth() {
        if (activeScreen === "lock") return
        if (btPanelOpen) {
            closeNestedOverlay()
            return
        }
        focusReturnOwner = focusOwner
        wifiPanelOpen = false
        btPanelOpen = true
        btFocus = 0
        claimInputFocus("bluetooth")
        writeState()
    }

    // Any overlay open?  Used to keep navigation and keyboard focus in shell.
    readonly property bool anyOverlayOpen:
        radialOpen || paletteOpen || wifiPanelOpen || btPanelOpen ||
        activePanel !== ""

    // App surfaces are QML-rendered here, so controller navigation stays in
    // this process instead of disappearing into an external Wayland client.
    readonly property bool appMode: activeScreen === "app" && !anyOverlayOpen

    // OSK is visible whenever the palette is open (extends to WiFi passphrase in Phase 3).
    readonly property bool oskOpen: paletteOpen

    function handleRadial() {
        if (activeScreen === "lock") return
        if (radialOpen) {
            radialOpen = false
            releaseOverlayFocus()
            writeState()
            return
        }
        openExclusiveOverlay("radial")
        radialLayer = radialConfig.title || "system"
        radialOpen = true
        radialFocus = radialConfig.initialFocus || 0
        writeState()
    }


    function moveRadial(direction) {
        var items = radialConfig.items || []
        if (items.length === 0) return
        var navigation = radialConfig.navigation || {}
        var delta = Number(navigation[direction]) || 0
        radialFocus = ((radialFocus + delta) % items.length + items.length) % items.length
    }

    function navUp() {
        if (paletteOpen) {
            paletteFocus = Math.max(0, paletteFocus - 1)
            return
        }
        if (radialOpen)       { moveRadial("up"); return }
        if (wifiPanelOpen)    { wifiFocus = Math.max(0, wifiFocus - 1); return }
        if (btPanelOpen)      { btFocus = Math.max(0, btFocus - 1); return }
        if (activePanel === "qs") {
            navQuickSettings("up")
            return
        }
        if (activePanel === "notif") {
            navNotifications("up")
            return
        }
        if (activePanel === "switcher") return
        if (oskOpen)          { osk.navUp(); return }
        if (activeScreen === "app" && launchedApp === "Files") {
            fileFocus = Math.max(0, fileFocus - 1)
            return
        }
        if (activeScreen === "home" && homeFocus >= gridApps.length) {
            homeFocus = gridApps.length - 1
            return
        }
        if (activeScreen === "home" && homeFocus >= 4) homeFocus -= 4
    }

    function navDown() {
        if (paletteOpen) {
            paletteFocus = Math.min(Math.max(0, paletteFiltered.length - 1), paletteFocus + 1)
            return
        }
        if (radialOpen)       { moveRadial("down"); return }
        if (wifiPanelOpen)    { wifiFocus = Math.min(Math.max(0, wifiPanel.itemCount - 1), wifiFocus + 1); return }
        if (btPanelOpen)      { btFocus = Math.min(Math.max(0, btPanel.itemCount - 1), btFocus + 1); return }
        if (activePanel === "qs") {
            navQuickSettings("down")
            return
        }
        if (activePanel === "notif") {
            navNotifications("down")
            return
        }
        if (activePanel === "switcher") return
        if (oskOpen)          { osk.navDown(); return }
        if (activeScreen === "app" && launchedApp === "Files") {
            fileFocus = Math.min(Math.max(0, fileEntries.length - 1), fileFocus + 1)
            return
        }
        if (activeScreen === "home") {
            if (homeFocus + 4 < gridApps.length) homeFocus += 4
            else if (homeFocus < gridApps.length) homeFocus = gridApps.length
        }
    }

    function navLeft() {
        if (paletteOpen) {
            paletteFocus = Math.max(0, paletteFocus - 1)
            return
        }
        if (radialOpen)       { moveRadial("left"); return }
        if (wifiPanelOpen || btPanelOpen || activePanel === "notif") return
        if (activePanel === "qs") {
            if (quickSettingsFocus < quickSettingsConfig.sliders.length)
                adjustQuickSettings(-1)
            else
                navQuickSettings("left")
            return
        }
        if (activePanel === "switcher") {
            switcherFocus = Math.max(0, switcherFocus - 1)
            return
        }
        if (oskOpen)          { osk.navLeft(); return }
        if (activeScreen === "home") homeFocus = Math.max(0, homeFocus - 1)
    }

    function navRight() {
        if (paletteOpen) {
            paletteFocus = Math.min(Math.max(0, paletteFiltered.length - 1), paletteFocus + 1)
            return
        }
        if (radialOpen)       { moveRadial("right"); return }
        if (wifiPanelOpen || btPanelOpen || activePanel === "notif") return
        if (activePanel === "qs") {
            if (quickSettingsFocus < quickSettingsConfig.sliders.length)
                adjustQuickSettings(1)
            else
                navQuickSettings("right")
            return
        }
        if (activePanel === "switcher") {
            switcherFocus = Math.min(switcherApps.length - 1, switcherFocus + 1)
            return
        }
        if (oskOpen)          { osk.navRight(); return }
        if (activeScreen === "home") {
            var total = gridApps.length + dockApps.length
            homeFocus = Math.min(total - 1, homeFocus + 1)
        }
    }

    function launchCommand(id) {
        if (id === "nav.lock") {
            activeScreen = "lock"
            pinLen = 0
            writeState()
            return
        }
        if (id === "nav.home")      { handleHome(); return }
        if (id === "sys.wifi")      { paletteOpen = false; handleWifi(); return }
        if (id === "sys.bluetooth") { paletteOpen = false; handleBluetooth(); return }
        if (id === "sys.brightness") {
            runControl(launcherProc, ["brightness-step", "up"])
            return
        }
        if (id === "sys.volume") {
            runControl(launcherProc, ["volume-step", "up"])
            return
        }
        if (id === "sys.sleep" || id === "sys.power") {
            showBanner("Power action requires a physical confirmation")
            return
        }
        if (id === "sys.dnd") {
            showBanner("Do Not Disturb toggled")
            return
        }
        if (id.startsWith("sys.brightness.") || id.startsWith("sys.volume.")) {
            var direction = id.endsWith(".down") ? "down" : "up"
            var helper = id.indexOf("brightness") >= 0 ? "brightness-step" : "volume-step"
            runControl(launcherProc, [helper, direction])
            return
        }
        if (id.startsWith("launcher:")) {
            var launcherIndex = Number(id.slice("launcher:".length)) - 1
            var discovered = gridApps.filter(function(candidate) {
                return candidate.external && candidate.exec
            })
            var launcher = discovered[launcherIndex]
            if (launcher) {
                paletteOpen = false
                openApp(launcher)
            }
            return
        }

        if (id.startsWith("app.")) {
            var name = id.slice(4)
            var all = gridApps.concat(dockApps)
            var app = all.find(function(candidate) {
                return candidate.name.toLowerCase() === name
            }) || all.find(function(candidate) {
                return candidate.name.toLowerCase().startsWith(name)
            })
            if (app) {
                openApp(app)
                if (name === "browser") launchExternal(name)
            }
            return
        }
        showBanner("Unknown action: " + id)
    }

    // ─── Controller input (primary) ───────────────────────────────────────────
    // Global buttons escape app surfaces; navigation and confirm remain in the
    // QML app so the device works without a keyboard or external client.
    function onPadButton(name) {
        if (activeScreen === "lock") {
            if (name === "south") handleConfirm()
            return
        }
        switch (name) {
            case "start":  handleHome();     return
            case "mode":   handleHome();     return
            case "select": handleSwitcher(); return
            case "west":   handlePalette();  return
            case "north":  handleRadial();   return
            case "r1":     handleQS();       return
            case "l1":     handleNotif();    return
        }
        switch (name) {
            case "south":      handleConfirm(); break
            case "east":       handleBack();    break
            case "dpad_up":    navUp();         break
            case "dpad_down":  navDown();       break
            case "dpad_left":  navLeft();       break
            case "dpad_right": navRight();      break
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
        screen: shell.upperScreen

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: shell.anyOverlayOpen
                                  ? WlrKeyboardFocus.Exclusive
                                  : WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "torchform-upper"
        anchors { left: true; right: true; top: true; bottom: true }

        color: Tokens.bgBase

        Item {
            id: upperInput
            anchors.fill: parent
            focus: true

            Keys.onPressed: (ev) => {
                // Command palette owns controller navigation while open.  The
                // on-screen keyboard remains touch-driven; A/Enter activates
                // the selected command and ordinary character keys filter it.
                if (shell.paletteOpen) {
                    switch (ev.key) {
                        case Qt.Key_Escape:
                            ev.accepted = true
                            shell.handleBack()
                            return
                        case Qt.Key_A:
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            ev.accepted = true
                            shell.handleConfirm()
                            return
                        case Qt.Key_Up:
                            ev.accepted = true
                            shell.navUp()
                            return
                        case Qt.Key_Down:
                            ev.accepted = true
                            shell.navDown()
                            return
                        case Qt.Key_Left:
                            ev.accepted = true
                            shell.navLeft()
                            return
                        case Qt.Key_Right:
                            ev.accepted = true
                            shell.navRight()
                            return
                        case Qt.Key_Backspace:
                            ev.accepted = true
                            if (shell.paletteQuery.length > 0)
                                shell.paletteQuery = shell.paletteQuery.slice(0, -1)
                            return
                        default:
                            if (ev.text && ev.text.length === 1) {
                                ev.accepted = true
                                shell.paletteQuery += ev.text
                            } else {
                                ev.accepted = false
                            }
                            return
                    }
                }

                // Terminal text entry keeps ordinary keyboard characters,
                // spaces, and Enter for its TextInput.  Other app surfaces use
                // the controller-friendly global shortcuts below.  An overlay
                // always wins, even when Terminal was active underneath it.
                var terminalTextEntry = shell.activeScreen === "app" &&
                                        shell.launchedApp === "Terminal" &&
                                        !shell.anyOverlayOpen &&
                                        shell.focusOwner === "app"
                if (!terminalTextEntry) {
                    switch (ev.key) {
                        case Qt.Key_Space:  ev.accepted = true; shell.handleHome();        return
                        case Qt.Key_X:      ev.accepted = true; shell.handlePalette();     return
                        case Qt.Key_Enter:  ev.accepted = true; shell.handleSwitcher();    return
                        case Qt.Key_Z:      ev.accepted = true; shell.handleQS();          return
                        case Qt.Key_C:      ev.accepted = true; shell.handleNotif();       return
                        case Qt.Key_Tab:    ev.accepted = true; shell.handleRadial();      return
                        default: break
                    }
                }

                if (terminalTextEntry) {
                    if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
                        ev.accepted = true
                        appWindow.submitTerminalInput()
                    } else {
                        ev.accepted = false
                    }
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
                batteryKnown: shell.batteryKnown
                lowBattery:   shell.lowBattery
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
                    id: appWindow
                    anchors.fill: parent
                    visible:  shell.activeScreen === "app"
                    appName:  shell.launchedApp
                    appIcon:  shell.launchedIcon
                    appBg:    shell.launchedBg
                    fileEntries: shell.fileEntries
                    filePath: shell.filePath
                    fileFocus: shell.fileFocus
                    filesLoading: shell.filesLoading
                    filesStatus: shell.filesStatus
                    terminalLines: shell.terminalLines
                    terminalRunning: shell.terminalRunning
                    sysmonMetrics: shell.sysmonMetrics
                    sysmonUpdated: shell.sysmonUpdated
                    onHomeRequested: shell.handleHome()
                    onFileEntryActivated: (index) => shell.openFileEntry(index)
                    onFileParentRequested: shell.parentFiles()
                    onFileRefreshRequested: shell.refreshFiles()
                    onFileBookmarkRequested: (path) => shell.refreshFiles(path)
                    onTerminalCommandSubmitted: (command) => shell.submitTerminal(command)
                    onTerminalExternalRequested: shell.launchExternal("terminal")
                    onSysmonRefreshRequested: shell.sampleSysmon()
                }

                // Overlays (ordered back to front) ─────────────────────────

                QuickSettings {
                    anchors.fill: parent
                    open: shell.activePanel === "qs"
                    config: shell.quickSettingsConfig
                    sliderValues: shell.quickSettingsSliderValues
                    tileStates: shell.quickSettingsTileStates
                    focusIndex: shell.quickSettingsFocus
                    onClosed: shell.handleBack()
                    onItemActivated: (idx) => {
                        shell.quickSettingsFocus = idx
                        shell.handleConfirm()
                    }
                    onSliderAdjusted: (idx, delta) => {
                        shell.quickSettingsFocus = idx
                        shell.adjustQuickSettings(delta)
                    }
                }

                WiFiPanel {
                    id: wifiPanel
                    anchors.fill: parent
                    open:        shell.wifiPanelOpen
                    focusIndex:  shell.wifiFocus
                    onClosed:    shell.handleBack()
                    onNotice: (msg) => shell.showBanner(msg)
                }

                BluetoothPanel {
                    id: btPanel
                    anchors.fill: parent
                    open:        shell.btPanelOpen
                    focusIndex:  shell.btFocus
                    onClosed:    shell.handleBack()
                    onNotice: (msg) => shell.showBanner(msg)
                }

                Notifications {
                    anchors.fill: parent
                    open: shell.activePanel === "notif"
                    config: shell.notificationsConfig
                    suppressed: shell.dndEnabled
                    focusIndex: shell.notificationsFocus
                    onClosed: shell.handleBack()
                    onItemActivated: (idx) => {
                        shell.notificationsFocus = idx
                        shell.handleConfirm()
                    }
                }

                AppSwitcher {
                    anchors.fill: parent
                    open: shell.activePanel === "switcher"
                    config: shell.switcherConfig
                    focusIndex: shell.switcherFocus
                    onAppSelected: (idx) => {
                        shell.switcherFocus = idx
                        shell.handleConfirm()
                    }
                    onClosed: shell.handleBack()
                }

                CommandPalette {
                    anchors.fill: parent
                    open:       shell.paletteOpen
                    query:      shell.paletteQuery
                    commands:   shell.paletteFiltered
                    focusIndex: shell.paletteFocus
                    onCommandSelected: (idx) => {
                        shell.paletteFocus = idx
                        shell.handleConfirm()
                    }
                    onClosed: shell.handleBack()
                }

                RadialMenu {
                    anchors.fill: parent
                    open: shell.radialOpen
                    config: shell.radialConfig
                    activeLayer: shell.radialLayer
                    focusIndex: shell.radialFocus
                    onItemActivated: (idx) => {
                        shell.radialFocus = idx
                        shell.handleConfirm()
                    }
                    onDismissed: shell.handleBack()
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
                    onCloseRequested: shell.handleConfirm()
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
        screen:  shell.lowerScreen

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.namespace: "torchform-lower"
        anchors { left: true; right: true; top: true; bottom: true }

        LowerPanel {
            id: lowerPanel
            anchors.fill: parent
            timeStr:       shell.timeStr
            activeApp:     shell.launchedApp
            batteryPct:    shell.batteryPct
            batteryKnown:  shell.batteryKnown
            batteryStatus: shell.batteryStatus
            lowBattery:    shell.lowBattery
            paletteOpen:   shell.paletteOpen
            radialOpen:    shell.radialOpen
            actions:       Data.lowerActions
            onActionTriggered: (id) => shell.launchCommand(id)
        }
    }
}
