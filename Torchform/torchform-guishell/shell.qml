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
    property bool lowerOskOpen: false
    property bool wifiCredentialOpen: false
    property string wifiCredentialSsid: ""
    property string wifiCredential: ""
    property bool btCredentialOpen: false
    property string btCredentialAddress: ""
    property string btCredentialName: ""
    property string btCredential: ""

    // Runtime values are separate from the data-only layout registry.  Nothing
    // here is seeded from data.js: Quick Settings availability and values are
    // facts the `qs-state` probe read back from the device, so a control is
    // never painted as working before the backend confirmed it.
    property var quickSettingsSliderValues: []
    property var quickSettingsTileStates:   []
    property var quickSettingsSliderAvailability: []
    property var quickSettingsSliderReasons:      []
    property var quickSettingsTileAvailability:   []
    property var quickSettingsTileReasons:        []
    property bool dndEnabled: false
    property string quickActionPendingId: ""

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
    property int    sysmonFocus: 0
    property int    mediaFocus:  0

    property var    sysmonHistory: []

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

    // Notes — plain files under ~/.local/share/torchform/notes.
    property var    notes: []
    property int    notesFocus: 0
    property bool   notesLoading: false
    property string notesStatus: ""
    property bool   notesEditing: false
    property string notesTitle: ""
    property string notesBody: ""

    // Logview — BusyBox syslog, dmesg, and the session logs.
    property var    logSources: Data.logSources
    property int    logSourceIndex: 0
    property var    logLines: []
    property int    logFocus: 0
    property bool   logsLoading: false
    property string logsStatus: ""

    // Pkgman — apk installed packages.
    property var    packages: []
    property int    packageFocus: 0
    property string packageQuery: ""
    property bool   packagesLoading: false
    property string packagesStatus: ""
    property var    packageDetails: []
    property bool   packageDetailOpen: false

    // Quick menu (power/session overlay).
    property bool   quickMenuOpen: false
    property int    quickMenuFocus: 0
    property bool   quickMenuConfirming: false

    // Apps opened in this session, newest first — the switcher shows these.
    property var    sessionApps: []

    // Active free-text sink for the lower on-screen keyboard.
    // One of: "palette", "wifi", "bluetooth", "note", "note-title", "package".
    property string textTarget: "palette"

    // Notifications posted by local programs through torchform-notify.
    property var    liveNotifications: []
    property var    seenNotificationIds: []
    property bool   notificationsPrimed: false

    // Settings — schema-driven editor over settings-schema.toml.
    property var    settingsSections: []
    property var    settingsRows: []
    property int    settingsSection: 0
    property int    settingsRow: 0
    property string settingsPane: "sidebar"
    property bool   settingsLoading: false
    property string settingsStatus: ""

    // Name of the external Wayland client currently mapped over the shell.
    property string externalApp: ""
    readonly property bool externalRunning: externalProc.running

    // The [apps.<key>] entry the backend resolved for the running client, and
    // that app's controller map.  Nothing about either is known to this file:
    // both come from config so no program is hardcoded in the shell.
    property string externalAppKey: ""
    property var    externalControls: []

    Process {
        id: externalControlsProc
        stdout: StdioCollector {
            onStreamFinished: {
                var rows = []
                String(text).trim().split("\n").forEach(function(line) {
                    if (line.length === 0) return
                    var parts = line.split("\t")
                    if (parts.length < 3) return
                    rows.push({ button: parts[0], keys: parts[1], label: parts[2] })
                })
                shell.externalControls = rows
                shell.writeState()
            }
        }
    }

    Process {
        id: externalKeyProc
        stdout: StdioCollector {
            onStreamFinished: {
                var first = String(text).trim().split("\n")[0] || ""
                if (first.indexOf("error|") === 0)
                    shell.showBanner(first.slice(6))
            }
        }
    }

    function loadExternalControls(key) {
        externalControls = []
        if (!key || key.length === 0) return
        runControl(externalControlsProc, ["app-controls", key])
    }

    // Buttons the running client understands are translated into its own real
    // keyboard shortcuts by the backend.  east/start/mode never reach here:
    // they stay Torchform's guaranteed way out of any external app.
    function sendExternalKey(name) {
        if (externalAppKey.length === 0) return false
        for (var i = 0; i < externalControls.length; ++i) {
            if (externalControls[i].button === name) {
                runControl(externalKeyProc, ["app-key", externalAppKey, name])
                return true
            }
        }
        return false
    }

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
                   c.description.toLowerCase().indexOf(q) >= 0 ||
                   c.category.toLowerCase().indexOf(q) >= 0 ||
                   c.keywords.toLowerCase().indexOf(q) >= 0 ||
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
                if (kind === "state" && parts.length >= 2 &&
                    shell.quickActionPendingId === "sys.dnd")
                    shell.dndEnabled = parts[1] === "on"
                shell.quickActionPendingId = ""
                shell.showBanner(message || raw)
                shell.refreshQuickSettings()
                shell.writeState()
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

    // External Wayland apps (media handlers, browser, terminal) run in the
    // foreground of torchform-control.sh so this Process owns their lifetime.
    // While one is mapped the shell drops its overlay layer, otherwise the
    // layer-shell surface would cover the app on both outputs.
    Process {
        id: externalProc
        // The backend prints "ok|<appkey>|<label>" before it blocks in the
        // foreground, so this must be parsed line by line.  StdioCollector only
        // yields at stream end, which is after the client has already exited.
        stdout: SplitParser {
            onRead: (line) => {
                var parts = String(line).trim().split("|")
                if (parts[0] === "error") {
                    shell.showBanner(parts.slice(1).join("|"))
                    return
                }
                if (parts[0] !== "ok" || parts.length < 2) return
                shell.externalAppKey = parts[1]
                if (parts.length >= 3 && parts[2].length > 0)
                    shell.externalApp = parts[2]
                shell.loadExternalControls(parts[1])
                shell.writeState()
            }
        }
        onExited: (exitCode, exitStatus) => {
            var closed = shell.externalApp
            shell.externalApp = ""
            shell.externalAppKey = ""
            shell.externalControls = []
            if (closed.length > 0) {
                if (shell.externalClosing || exitCode === 0)
                    shell.showBanner(closed + " closed")
                else
                    shell.showBanner(closed + " exited unexpectedly (code " + exitCode + ")")
            }
            shell.externalClosing = false
            // Sway leaves keyboard focus on the dead toplevel's workspace, so
            // an on-demand layer surface never gets it back.  Claim it briefly.
            shell.focusReclaim = true
            focusReclaimTimer.restart()
            shell.writeState()
        }
    }

    // Set while the shell takes keyboard focus back from a closed external app.
    property bool focusReclaim: false

    // True while the shell itself is terminating the external app, so its
    // non-zero exit is a normal close rather than a crash.
    property bool externalClosing: false

    Timer {
        id: focusReclaimTimer
        interval: 400
        onTriggered: shell.focusReclaim = false
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
        id: notesProc
        stdout: StdioCollector {
            onStreamFinished: {
                var rows = []
                var status = ""
                text.trim().split("\n").forEach(function(line) {
                    if (line.length === 0) return
                    var parts = line.split("\t")
                    if (parts[0] === "note" && parts.length >= 5) {
                        rows.push({
                            name: parts[1],
                            size: parts[2],
                            modified: parts[3],
                            path: parts.slice(4).join("\t")
                        })
                    } else if (parts[0] === "status" || parts[0].indexOf("error|") === 0) {
                        status = line.replace(/^(status\t|error\|)/, "")
                    }
                })
                shell.notes = rows
                shell.notesFocus = Math.max(0, Math.min(shell.notesFocus, Math.max(0, rows.length - 1)))
                shell.notesStatus = status
                shell.notesLoading = false
                shell.writeState()
            }
        }
    }

    Process {
        id: noteReadProc
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.split("\n")
                if (lines.length > 0 && lines[0].indexOf("body\t") === 0) {
                    lines.shift()
                } else if (lines.length > 0 && lines[0].indexOf("error|") === 0) {
                    shell.showBanner(lines[0].slice(6))
                    return
                }
                // Drop the single trailing newline the writer adds.
                if (lines.length > 0 && lines[lines.length - 1] === "") lines.pop()
                shell.notesBody = lines.join("\n")
                shell.notesEditing = true
                shell.textTarget = "note"
                shell.writeState()
            }
        }
    }

    Process {
        id: noteWriteProc
        stdout: StdioCollector {
            onStreamFinished: {
                var first = text.trim().split("\n")[0] || ""
                var parts = first.split("|")
                if (parts.length > 1) shell.showBanner(parts.slice(1).join("|"))
                shell.refreshNotes()
            }
        }
    }

    Process {
        id: logsProc
        stdout: StdioCollector {
            onStreamFinished: {
                var raw = text.replace(/\n+$/, "")
                var lines = raw.length > 0 ? raw.split("\n") : []
                var status = ""
                if (lines.length === 1 && lines[0].indexOf("status|") === 0) {
                    status = lines[0].slice(7)
                    lines = []
                }
                shell.logLines = lines
                shell.logsStatus = status
                shell.logFocus = Math.max(0, lines.length - 1)
                shell.logsLoading = false
                shell.writeState()
            }
        }
    }

    Process {
        id: packagesProc
        stdout: StdioCollector {
            onStreamFinished: {
                var rows = []
                var status = ""
                text.trim().split("\n").forEach(function(line) {
                    if (line.length === 0) return
                    var parts = line.split("\t")
                    if (parts[0] === "pkg" && parts.length >= 3) {
                        rows.push({ name: parts[1], version: parts[2] })
                    } else if (line.indexOf("status|") === 0) {
                        status = line.slice(7)
                    }
                })
                shell.packages = rows
                shell.packageFocus = Math.max(0, Math.min(shell.packageFocus, Math.max(0, rows.length - 1)))
                shell.packagesStatus = status
                shell.packagesLoading = false
                shell.writeState()
            }
        }
    }

    Process {
        id: packageInfoProc
        stdout: StdioCollector {
            onStreamFinished: {
                var raw = text.replace(/\n+$/, "")
                shell.packageDetails = raw.length > 0 ? raw.split("\n") : ["No details available."]
                shell.packageDetailOpen = true
                shell.writeState()
            }
        }
    }

    Process {
        id: settingsProc
        stdout: StdioCollector {
            onStreamFinished: {
                var sections = []
                var rows = []
                var status = ""
                text.trim().split("\n").forEach(function(line) {
                    if (line.length === 0) return
                    var parts = line.split("\t")
                    if (parts[0] === "section" && parts.length >= 3) {
                        sections.push({ id: parts[1], title: parts[2] })
                    } else if (parts[0] === "row" && parts.length >= 11) {
                        rows.push({
                            section: parts[1],
                            key: parts[2],
                            label: parts[3],
                            icon: parts[4],
                            desc: parts[5],
                            widget: parts[6],
                            min: parts[7],
                            max: parts[8],
                            step: parts[9],
                            options: parts[10].length > 0 ? parts[10].split("|") : [],
                            value: parts.length > 11 ? parts[11] : ""
                        })
                    } else if (line.indexOf("error|") === 0 || line.indexOf("status|") === 0) {
                        status = line.slice(line.indexOf("|") + 1)
                    }
                })
                shell.settingsSections = sections
                shell.settingsRows = rows
                shell.settingsStatus = status
                shell.settingsSection = Math.max(0, Math.min(shell.settingsSection, Math.max(0, sections.length - 1)))
                // Reloading after a write must not move the operator's cursor.
                var active = sections[shell.settingsSection]
                var visible = active
                    ? rows.filter(function(row) { return row.section === active.id }).length
                    : 0
                shell.settingsRow = Math.max(0, Math.min(shell.settingsRow, Math.max(0, visible - 1)))
                shell.settingsLoading = false
                shell.writeState()
            }
        }
    }

    Process {
        id: notifyProc
        stdout: StdioCollector {
            onStreamFinished: {
                var items = []
                text.trim().split("\n").forEach(function(line) {
                    if (line.length === 0) return
                    var parts = line.split("\t")
                    if (parts.length < 4) return
                    items.push({
                        id: parts[0],
                        time: parts[1],
                        app: parts[2],
                        title: parts[3],
                        body: parts.length > 4 ? parts.slice(4).join("\t") : "",
                        icon: "\u2691"
                    })
                })
                // Announce ids never seen before; a dismissal changes the newest
                // entry without anything new having arrived.
                var seen = shell.seenNotificationIds
                var fresh = items.filter(function(entry) { return seen.indexOf(entry.id) < 0 })
                if (fresh.length > 0 && shell.notificationsPrimed)
                    shell.showBanner(fresh[0].app + ": " + fresh[0].title)
                shell.seenNotificationIds = items.map(function(entry) { return entry.id })
                shell.notificationsPrimed = true
                shell.liveNotifications = items
                shell.notifCount = items.length + (Data.overlayConfig.notifications.items || []).length
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!notifyProc.running) shell.runControl(notifyProc, ["notify-list"])
    }

    Process {
        id: notifyClearProc
        stdout: StdioCollector {
            onStreamFinished: shell.runControl(notifyProc, ["notify-list"])
        }
    }

    Process {
        id: settingsWriteProc
        stdout: StdioCollector {
            onStreamFinished: {
                var first = text.trim().split("\n")[0] || ""
                var parts = first.split("|")
                if (parts.length > 1) shell.showBanner(parts.slice(1).join("|"))
                shell.refreshSettings()
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
                var history = shell.sysmonHistory.slice()
                history.push(metrics)
                while (history.length > 60) history.shift()
                shell.sysmonHistory = history

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

    // A dropped write would leave the exported state stale until the next
    // timer tick, so a skipped write is retried as soon as the writer frees up.
    property bool statePending: false

    Process {
        id: stateProc
        onExited: {
            if (!shell.statePending) return
            shell.statePending = false
            shell.writeState()
        }
    }

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
        if (stateProc.running) {
            statePending = true
            return
        }
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
            notesReady: notes.length > 0,
            notesFocus: notesFocus,
            notesEditing: notesEditing,
            notesTitle: notesTitle,
            logSource: (logSources[logSourceIndex] || {}).id || "",
            logLines: logLines.length,
            logFocus: logFocus,
            packageCount: packages.length,
            packageFocus: packageFocus,
            packageQuery: packageQuery,
            packageDetail: packageDetailOpen,
            settingsSections: settingsSections.length,
            settingsSection: settingsSection,
            settingsRow: settingsRow,
            settingsPane: settingsPane,
            settingsRows: settingsSectionRows.length,
            quickMenu: quickMenuOpen,
            quickMenuFocus: quickMenuFocus,
            quickMenuConfirming: quickMenuConfirming,
            sessionApps: sessionApps.length,
            notifCount: notifCount,
            liveNotifications: liveNotifications.length,
            textTarget: textTarget,
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
            notificationsFocus: notificationsFocus,
            quickSettingsSliderValues: quickSettingsSliderValues,
            quickSettingsTileStates: quickSettingsTileStates,
            quickSettingsSliderAvailability: quickSettingsSliderAvailability,
            quickSettingsTileAvailability: quickSettingsTileAvailability,
            sysmonFocus: sysmonFocus,
            mediaFocus: mediaFocus,
            externalApp: externalApp,
            externalAppKey: externalAppKey,
            externalControls: externalControls.length,
            externalRunning: externalRunning,

            dndEnabled: dndEnabled,
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
            openMediaFile(entry.path)
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

    function baseName(path) {
        var trimmed = String(path).replace(/\/+$/, "")
        var cut = trimmed.lastIndexOf("/")
        return cut >= 0 ? trimmed.slice(cut + 1) : trimmed
    }

    // Runs an external Wayland client and yields the upper display to it.
    function runExternal(label, args) {
        if (externalProc.running) {
            showBanner(externalApp + " is already open")
            return
        }
        externalApp = label
        externalClosing = false
        runControl(externalProc, args)
        showBanner("Opening " + label + "  •  B closes it")
        writeState()
    }

    function closeExternal() {
        if (!externalProc.running) return
        externalClosing = true
        externalProc.running = false
    }

    function launchExternal(app) {
        runExternal(app, ["launch", app])
    }

    function launchExternalExec(label, command) {
        runExternal(label, ["launch-exec", command, label])
    }

    function refreshApplications() {
        if (applicationsProc.running) return
        runControl(applicationsProc, ["applications-list"])
    }

    function openMediaFile(path) {
        runExternal(baseName(path), ["media-open", path])
    }

    function handleMediaAction(action) {
        if (action === "files") {
            var filesApp = gridApps.concat(dockApps).find(function(candidate) {
                return candidate.name === "Files"
            })
            openApp(filesApp)
            return
        }
        if (action === "browser") {
            runExternal("browser", ["media-launch", "browser"])
            return
        }
        runControl(launcherProc, ["media-launch", action])
    }

    // ─── Notes ───────────────────────────────────────────────────────────────
    function refreshNotes() {
        notesLoading = true
        runControl(notesProc, ["notes-list"])
    }

    function openNote(index) {
        var note = notes[index]
        if (!note) return
        notesTitle = note.name
        runControl(noteReadProc, ["notes-read", note.path])
    }

    function createNote() {
        // The title is free text, so the lower keyboard owns it until submit.
        notesEditing = true
        notesTitle = "note-" + Qt.formatDateTime(new Date(), "yyyyMMdd-hhmmss")
        notesBody = ""
        textTarget = "note"
        openLowerOskFor("note")
        writeState()
    }

    function saveNote() {
        if (!notesEditing) return
        var title = notesTitle.length > 0 ? notesTitle : "untitled"
        runControl(noteWriteProc, ["notes-write", title, notesBody])
        notesEditing = false
        notesBody = ""
        textTarget = "palette"
        writeState()
    }

    function deleteNote(index) {
        var note = notes[index]
        if (!note) return
        runControl(noteWriteProc, ["notes-delete", note.name])
    }

    // ─── Logview ─────────────────────────────────────────────────────────────
    function refreshLogs() {
        var source = logSources[logSourceIndex]
        if (!source) return
        logsLoading = true
        runControl(logsProc, ["logs-read", source.id])
    }

    function cycleLogSource(delta) {
        var count = logSources.length
        if (count === 0) return
        logSourceIndex = ((logSourceIndex + delta) % count + count) % count
        refreshLogs()
        writeState()
    }

    // ─── Pkgman ──────────────────────────────────────────────────────────────
    function refreshPackages() {
        packagesLoading = true
        packageDetailOpen = false
        runControl(packagesProc, ["pkg-list", packageQuery])
    }

    function openPackage(index) {
        var entry = packages[index]
        if (!entry) return
        runControl(packageInfoProc, ["pkg-info", entry.name])
    }

    // ─── Session app tracking (switcher) ─────────────────────────────────────
    function rememberApp(app) {
        if (!app) return
        var kept = []
        ;(sessionApps || []).forEach(function(entry) {
            if (entry.name !== app.name) kept.push(entry)
        })
        kept.unshift({
            name: app.name,
            icon: app.icon,
            bg: app.bg,
            openedAt: Qt.formatTime(new Date(), "hh:mm")
        })
        sessionApps = kept.slice(0, 8)
    }

    function forgetApp(index) {
        var entry = sessionApps[index]
        if (!entry) return
        var kept = []
        ;(sessionApps || []).forEach(function(candidate) {
            if (candidate.name !== entry.name) kept.push(candidate)
        })
        sessionApps = kept
        switcherFocus = Math.max(0, Math.min(switcherFocus, Math.max(0, kept.length - 1)))
        if (activeScreen === "app" && launchedApp === entry.name) handleHome()
        showBanner(entry.name + " closed")
        writeState()
    }

    // ─── Settings ────────────────────────────────────────────────────────────
    function refreshSettings() {
        settingsLoading = true
        runControl(settingsProc, ["settings-schema"])
    }

    readonly property var settingsSectionRows: {
        var section = settingsSections[settingsSection]
        if (!section) return []
        return settingsRows.filter(function(row) { return row.section === section.id })
    }

    function settingsEnterRows() {
        if (settingsSectionRows.length === 0) return
        settingsPane = "rows"
        settingsRow = 0
        writeState()
    }

    function settingsBackToSidebar() {
        settingsPane = "sidebar"
        writeState()
    }

    function setSetting(row, value) {
        runControl(settingsWriteProc, ["settings-set", row.key, String(value)])
    }

    function activateSetting() {
        var row = settingsSectionRows[settingsRow]
        if (!row) return
        if (row.widget === "toggle") {
            var on = row.value === "true" || row.value === "on" || row.value === "1"
            setSetting(row, on ? "false" : "true")
        } else if (row.widget === "action") {
            runControl(settingsWriteProc, ["settings-action", row.key])
        } else if (row.widget === "text") {
            showBanner(row.label + ": " + (row.value.length > 0 ? row.value : "not reported"))
        } else {
            showBanner(row.label + " — use Left/Right to adjust")
        }
    }

    function adjustSetting(delta) {
        var row = settingsSectionRows[settingsRow]
        if (!row) return
        if (row.widget === "slider") {
            var step = Number(row.step) || 1
            var min = Number(row.min) || 0
            var max = Number(row.max) || 100
            var current = Number(row.value)
            if (isNaN(current)) current = min
            setSetting(row, Math.max(min, Math.min(max, current + delta * step)))
        } else if (row.widget === "select" && row.options.length > 0) {
            var index = row.options.indexOf(row.value)
            if (index < 0) index = 0
            index = ((index + delta) % row.options.length + row.options.length) % row.options.length
            setSetting(row, row.options[index])
        } else if (row.widget === "toggle") {
            setSetting(row, delta > 0 ? "true" : "false")
        }
    }

    // ─── Quick menu ──────────────────────────────────────────────────────────
    function handleQuickMenu() {
        if (activeScreen === "lock") return
        if (quickMenuOpen) {
            quickMenuOpen = false
            quickMenuConfirming = false
            releaseOverlayFocus()
            writeState()
            return
        }
        openExclusiveOverlay("quick-menu")
        quickMenuOpen = true
        quickMenuFocus = quickMenuConfig.initialFocus || 0
        quickMenuConfirming = false
        writeState()
    }

    function activateQuickMenu() {
        var item = (quickMenuConfig.items || [])[quickMenuFocus]
        if (!item) return
        if (item.confirm && !quickMenuConfirming) {
            quickMenuConfirming = true
            writeState()
            return
        }
        quickMenuConfirming = false
        quickMenuOpen = false
        releaseOverlayFocus()
        if (item.id === "power.lock") {
            launchCommand("nav.lock")
        } else if (item.id === "power.session") {
            showBanner("End session: stop Torchform from a terminal or OpenRC")
        } else if (item.id === "power.reboot") {
            runControl(launcherProc, ["power", "reboot"])
        } else if (item.id === "power.poweroff") {
            runControl(launcherProc, ["power", "poweroff"])
        }
        writeState()
    }
    function refreshQuickSettingsState() {
        runControl(quickStateProc, ["quick-state", "dnd"])
    }


    // ─── Data-driven UI registry (edit data.js; no QML rebuild required) ─────
    readonly property var overlayConfig:       Data.overlayConfig
    readonly property var radialConfig:        overlayConfig.radial
    readonly property var quickSettingsConfig:  overlayConfig.quickSettings
    readonly property var notificationsConfig: ({
        side: overlayConfig.notifications.side,
        width: overlayConfig.notifications.width,
        title: overlayConfig.notifications.title,
        closeGlyph: overlayConfig.notifications.closeGlyph,
        initialFocus: overlayConfig.notifications.initialFocus,
        items: liveNotifications.concat(overlayConfig.notifications.items || [])
    })
    readonly property var switcherConfig:      overlayConfig.switcher
    property var gridApps:                     Data.gridApps
    property var dockApps:                     Data.dockApps
    property var paletteCommands:              Data.paletteCommands
    readonly property var quickMenuConfig:     overlayConfig.quickMenu
    readonly property var switcherApps:        sessionApps

    function resetOverlayRuntime() {
        // Quick Settings starts empty and therefore unavailable; refreshQuickSettings()
        // fills it from the device probe.  Seeding from data.js would paint dead
        // controls as working.
        quickSettingsSliderValues       = []
        quickSettingsSliderAvailability = []
        quickSettingsSliderReasons      = []
        quickSettingsTileStates         = []
        quickSettingsTileAvailability   = []
        quickSettingsTileReasons        = []
        quickSettingsFocus = quickSettingsConfig.initialFocus || 0
        notificationsFocus = notificationsConfig.initialFocus || 0
        switcherFocus = switcherConfig.initialFocus || 0
        notifCount = (notificationsConfig.items || []).length
    }

    // ─── Quick Settings device probe ─────────────────────────────────────────
    Process {
        id: qsStateProc
        stdout: StdioCollector {
            onStreamFinished: shell.applyQuickSettingsState(text)
        }
    }

    // ─── Background services ─────────────────────────────────────────────────
    // Quick Settings can only be honest if what backs each control is running.
    // Services are declared in config.toml and brought up asynchronously: the
    // shell never blocks on them, and re-probes once they have had a moment to
    // come up so the panel reflects the live system rather than boot order.
    property var serviceReport: []

    Process {
        id: servicesProc
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = []
                String(text).trim().split("\n").forEach(function(line) {
                    if (line.length === 0) return
                    lines.push(line)
                    if (line.indexOf("error|") === 0)
                        shell.showBanner(line.slice(6))
                })
                shell.serviceReport = lines
                shell.writeState()
                // Give a freshly spawned daemon a moment to register before the
                // probe decides a control is dead.
                servicesSettleTimer.restart()
            }
        }
    }

    Timer {
        id: servicesSettleTimer
        interval: 1500
        onTriggered: shell.refreshQuickSettings()
    }

    function startServices() {
        if (servicesProc.running) return
        runControl(servicesProc, ["services-start"])
    }

    // Re-probe shortly after a control is stepped, so the level shown is the one
    // the device reports rather than the one we hoped for.
    Timer {
        id: qsRefreshTimer
        interval: 400
        onTriggered: shell.refreshQuickSettings()
    }

    function refreshQuickSettings() {
        if (qsStateProc.running) return
        runControl(qsStateProc, ["qs-state"])
    }

    function applyQuickSettingsState(text) {
        var probe = {}
        String(text).trim().split("\n").forEach(function(line) {
            var parts = line.split("|")
            if (parts.length < 4) return
            probe[parts[0] + ":" + parts[1]] = {
                available: parts[2] === "available",
                detail: parts.slice(3).join("|")
            }
        })
        var values = [], sliderOk = [], sliderWhy = []
        ;(quickSettingsConfig.sliders || []).forEach(function(slider) {
            var entry = probe["slider:" + slider.id]
            var ok = !!entry && entry.available
            sliderOk.push(ok)
            sliderWhy.push(ok ? "" : (entry ? entry.detail : "The device did not report this control."))
            values.push(ok ? (Number(entry.detail) || 0) : 0)
        })
        var states = [], tileOk = [], tileWhy = []
        ;(quickSettingsConfig.tiles || []).forEach(function(tile) {
            var entry = probe["tile:" + tile.id]
            var ok = !!entry && entry.available
            tileOk.push(ok)
            tileWhy.push(ok ? "" : (entry ? entry.detail : "The device did not report this control."))
            states.push(ok && entry.detail === "on")
            if (tile.id === "dnd")
                dndEnabled = ok && entry.detail === "on"
        })
        quickSettingsSliderValues       = values
        quickSettingsSliderAvailability = sliderOk
        quickSettingsSliderReasons      = sliderWhy
        quickSettingsTileStates         = states
        quickSettingsTileAvailability   = tileOk
        quickSettingsTileReasons        = tileWhy
        if (!quickSettingAvailable(quickSettingsFocus))
            quickSettingsFocus = firstAvailableQuickSetting()
        writeState()
    }

    function quickSettingAvailable(index) {
        var sliderCount = (quickSettingsConfig.sliders || []).length
        if (index < 0) return false
        if (index < sliderCount) return quickSettingsSliderAvailability[index] === true
        return quickSettingsTileAvailability[index - sliderCount] === true
    }

    function quickSettingReason(index) {
        var sliderCount = (quickSettingsConfig.sliders || []).length
        var reason = index < sliderCount
                   ? quickSettingsSliderReasons[index]
                   : quickSettingsTileReasons[index - sliderCount]
        return reason ? String(reason) : "unavailable"
    }

    function quickSettingsTotal() {
        return (quickSettingsConfig.sliders || []).length +
               (quickSettingsConfig.tiles || []).length
    }

    function firstAvailableQuickSetting() {
        var total = quickSettingsTotal()
        for (var i = 0; i < total; ++i)
            if (quickSettingAvailable(i)) return i
        return 0
    }

    // Controller navigation must never park on a dead control, so a candidate
    // that the device reported unavailable is stepped over in the direction of
    // travel.  If nothing in that direction is usable the focus simply stays.
    function commitQuickSettingsFocus(candidate, direction) {
        var total = quickSettingsTotal()
        if (total === 0) return
        candidate = Math.max(0, Math.min(total - 1, candidate))
        if (quickSettingAvailable(candidate)) {
            quickSettingsFocus = candidate
            return
        }
        var step = (direction === "up" || direction === "left") ? -1 : 1
        for (var i = candidate; i >= 0 && i < total; i += step) {
            if (quickSettingAvailable(i)) {
                quickSettingsFocus = i
                return
            }
        }
    }

    Component.onCompleted: {
        resetOverlayRuntime()
        // Bring configured services up first, then probe without blocking startup.
        startServices()
        refreshQuickSettings()
        refreshApplications()
    }

    // ─── Hint bar content ────────────────────────────────────────────────────
    property var currentHints: {
        if (activeScreen === "lock")
            return [{button:"A", label:"Unlock"}]
        if (lowerOskOpen)
            return [{button:"D-PAD", label:"Type"}, {button:"A", label:"Key"}, {button:"B", label:"Close"}]
        if (wifiPanelOpen)
            return [{button:"Y", label:"Scan"}, {button:"D-PAD", label:"Navigate"}, {button:"A", label:"Connect"}, {button:"B", label:"Close"}]
        if (btPanelOpen)
            return [{button:"Y", label:"Scan"}, {button:"D-PAD", label:"Navigate"}, {button:"A", label:"Pair / Connect"}, {button:"B", label:"Close"}]
        if (quickMenuOpen)
            return [{button:"D-PAD", label:"Select"}, {button:"A", label: quickMenuConfirming ? "Confirm" : "Activate"}, {button:"B", label:"Close"}]
        if (radialOpen)
            return [{button:"D-PAD", label:"Select"}, {button:"A", label:"Activate"}, {button:"B", label:"Close"}]
        if (paletteOpen)
            return [{button:"D-PAD", label:"Navigate"}, {button:"A", label:"Type / Launch"}, {button:"B", label:"Close"}]
        if (activePanel === "switcher")
            return [{button:"D-PAD", label:"Select"}, {button:"A", label:"Switch"}, {button:"X", label:"Close app"}, {button:"B", label:"Close"}]
        if (activePanel === "notif")
            return [{button:"D-PAD", label:"Navigate"}, {button:"A", label:"Open"}, {button:"X", label:"Dismiss"}, {button:"B", label:"Close"}]
        if (activePanel === "qs")
            return [{button:"D-PAD", label:"Navigate"},
                    {button:"L/R", label:"Adjust"},
                    {button:"A", label:"Toggle"},
                    {button:"B", label:"Close"}]
        if (activePanel !== "")
            return [{button:"D-PAD", label:"Navigate"}, {button:"B", label:"Close"}]
        if (activeScreen === "home")
            return [{button:"D-PAD", label:"Navigate"}, {button:"A", label:"Launch"}, {button:"X", label:"Palette"}, {button:"SELECT", label:"Apps"}]
        if (activeScreen === "app" && launchedApp === "Notes")
            return notesEditing
                   ? [{button:"A", label:"Keyboard"}, {button:"B", label:"Save & close"}]
                   : [{button:"D-PAD", label:"Choose"}, {button:"A", label:"Open"}, {button:"X", label:"New"}, {button:"Y", label:"Delete"}]
        if (activeScreen === "app" && launchedApp === "Logview")
            return [{button:"D-PAD", label:"Scroll"}, {button:"L1", label:"Prev log"}, {button:"R1", label:"Next log"}, {button:"A", label:"Refresh"}]
        if (activeScreen === "app" && launchedApp === "Settings")
            return settingsPane === "sidebar"
                   ? [{button:"D-PAD", label:"Section"}, {button:"A", label:"Open section"}, {button:"START", label:"Home"}]
                   : [{button:"D-PAD", label:"Row"}, {button:"L/R", label:"Adjust"}, {button:"A", label:"Toggle / Run"}, {button:"B", label:"Sections"}]
        if (activeScreen === "app" && launchedApp === "Pkgman")
            return packageDetailOpen
                   ? [{button:"B", label:"Back"}, {button:"Y", label:"Refresh"}]
                   : [{button:"D-PAD", label:"Choose"}, {button:"A", label:"Details"}, {button:"X", label:"Search"}, {button:"Y", label:"Refresh"}]
        if (activeScreen === "app")
            return [{button:"START", label:"Home"}, {button:"X", label:"Palette"}, {button:"L1", label:"Notifications"}, {button:"R1", label:"Quick Settings"}]
        return []
    }

    // Companion-screen context line for the active app (TODO 11C).
    readonly property string lowerAppContext: {
        // The companion panel already names the running client, so repeating it
        // as the context line would just print it twice.
        if (externalRunning) return ""
        if (activeScreen !== "app") return ""
        if (launchedApp === "Files") return filePath
        if (launchedApp === "Terminal") return terminalLast.length > 0 ? terminalLast : "no command yet"
        if (launchedApp === "Notes")
            return notesEditing ? notesTitle : notes.length + " notes"
        if (launchedApp === "Logview")
            return ((logSources[logSourceIndex] || {}).label || "") + " · " + logLines.length + " lines"
        if (launchedApp === "Pkgman")
            return packages.length + " packages" + (packageQuery.length > 0 ? " · " + packageQuery : "")
        if (launchedApp === "Sysmon")
            return "load " + cpuLoad + " · mem " + memoryUse
        if (launchedApp === "Settings") {
            var section = settingsSections[settingsSection]
            return section ? section.title : ""
        }
        return ""
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
        lowerOskOpen = false
        quickMenuOpen = false
        quickMenuConfirming = false
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
        mediaFocus = 0

        if (app.name === "Files") {
            filePath = "~"
            refreshFiles()
        } else if (app.name === "Sysmon") {
            sysmonFocus = 0
            sampleSysmon()
        } else if (app.name === "Media") {
            mediaFocus = 0
        } else if (app.name === "Terminal") {
            appWindow.focusTerminalInput()
        } else if (app.name === "Notes") {
            notesEditing = false
            notesBody = ""
            notesFocus = 0
            refreshNotes()
        } else if (app.name === "Logview") {
            logFocus = 0
            refreshLogs()
        } else if (app.name === "Pkgman") {
            packageFocus = 0
            packageDetailOpen = false
            refreshPackages()
        } else if (app.name === "Settings") {
            settingsPane = "sidebar"
            settingsSection = 0
            settingsRow = 0
            refreshSettings()
        } else if (app.external && app.exec) {
            launchExternalExec(app.name, app.exec)
        }
        rememberApp(app)
        writeState()
    }

    function handleConfirm() {
        if (lowerOskOpen) {
            lowerOsk.activateKey()
            return
        }
        if (wifiPanelOpen) {
            wifiPanel.activateFocused()
            return
        }
        if (btPanelOpen) {
            btPanel.activateFocused()
            return
        }
        if (quickMenuOpen) {
            activateQuickMenu()
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
        } else if (activeScreen === "app" && launchedApp === "Media") {
            appWindow.activateMedia()
        } else if (activeScreen === "app" && launchedApp === "Notes") {
            if (notesEditing) openLowerOskFor("note")
            else openNote(notesFocus)
        } else if (activeScreen === "app" && launchedApp === "Logview") {
            refreshLogs()
        } else if (activeScreen === "app" && launchedApp === "Pkgman") {
            if (!packageDetailOpen) openPackage(packageFocus)
        } else if (activeScreen === "app" && launchedApp === "Settings") {
            if (settingsPane === "sidebar") settingsEnterRows()
            else activateSetting()
        }
    }

    function activateQuickSettings() {
        var sliderCount = quickSettingsConfig.sliders.length
        if (!quickSettingAvailable(quickSettingsFocus)) {
            var dead = quickSettingsFocus < sliderCount
                     ? quickSettingsConfig.sliders[quickSettingsFocus]
                     : quickSettingsConfig.tiles[quickSettingsFocus - sliderCount]
            if (dead)
                showBanner((dead.label || dead.name) + ": " + quickSettingReason(quickSettingsFocus))
            return
        }
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
        quickActionPendingId = tile.action
        runControl(quickActionProc, ["quick-action", tile.action, target])
        qsRefreshTimer.restart()
        writeState()
    }

    function dismissNotification(index) {
        var item = (notificationsConfig.items || [])[index]
        if (!item || item.id === undefined) return
        // Only live entries can be dismissed; the data.js samples are static.
        var live = liveNotifications.some(function(entry) { return entry.id === item.id })
        if (!live) {
            showBanner("Sample notification — nothing to dismiss")
            return
        }
        runControl(notifyClearProc, ["notify-clear", String(item.id)])
        notificationsFocus = Math.max(0, index - 1)
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
        if (!quickSettingAvailable(index)) {
            showBanner(slider.label + ": " + quickSettingReason(index))
            return
        }
        // The device owns the level: step it, then re-probe.  Painting the new
        // value here would show a number the hardware never confirmed.
        var helper = slider.id === "brightness" ? "brightness-step" : "volume-step"
        runControl(launcherProc, [helper, delta > 0 ? "up" : "down"])
        qsRefreshTimer.restart()
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
            commitQuickSettingsFocus(focus, direction)
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
                commitQuickSettingsFocus(Math.max(0, sliderCount - 1), "up")
                return
            }
            row -= 1
        }
        if (direction === "down") row = Math.min(rows - 1, row + 1)
        var nextTile = Math.min(tiles.length - 1, row * columns + column)
        commitQuickSettingsFocus(sliderCount + Math.max(0, nextTile), direction)
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
        if (externalRunning) {
            closeExternal()
            return
        }
        if (lowerOskOpen) {
            lowerOskOpen = false
            wifiCredentialOpen = false
            wifiCredentialSsid = ""
            wifiCredential = ""
            btCredentialOpen = false
            btCredentialAddress = ""
            btCredentialName = ""
            btCredential = ""
            if (textTarget !== "note") textTarget = "palette"
            lowerOsk.reset()
            writeState()
            return
        }
        if (quickMenuOpen) {
            quickMenuOpen = false
            quickMenuConfirming = false
            releaseOverlayFocus()
            writeState()
            return
        }
        if (activeScreen === "app" && launchedApp === "Notes" && notesEditing) {
            saveNote()
            return
        }
        if (activeScreen === "app" && launchedApp === "Pkgman" && packageDetailOpen) {
            packageDetailOpen = false
            writeState()
            return
        }
        if (activeScreen === "app" && launchedApp === "Settings" && settingsPane === "rows") {
            settingsBackToSidebar()
            return
        }
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
    function openWifiCredential(ssid) {
        wifiCredentialOpen = true
        wifiCredentialSsid = ssid
        wifiCredential = ""
        btCredentialOpen = false
        textTarget = "wifi"
        lowerOskOpen = true
        lowerOsk.reset()
        wifiPanel.statusText = "Password for " + ssid + "  •  Type below  •  ✓ connect"
        writeState()
    }

    function openBluetoothCredential(address, name) {
        btCredentialOpen = true
        btCredentialAddress = address
        btCredentialName = name
        btCredential = ""
        wifiCredentialOpen = false
        textTarget = "bluetooth"
        lowerOskOpen = true
        lowerOsk.reset()
        btPanel.statusText = "PIN for " + name + "  •  Type below  •  ✓ pair"
        writeState()
    }

    // The lower keyboard is the only free-text device, so every text sink goes
    // through one target selector instead of a per-panel special case.
    function openLowerOskFor(target) {
        textTarget = target
        lowerOskOpen = true
        lowerOsk.reset()
        writeState()
    }

    function activeText() {
        if (textTarget === "wifi") return wifiCredential
        if (textTarget === "bluetooth") return btCredential
        if (textTarget === "note") return notesBody
        if (textTarget === "note-title") return notesTitle
        if (textTarget === "package") return packageQuery
        return paletteQuery
    }

    function applyText(value) {
        if (textTarget === "wifi") {
            wifiCredential = value
            wifiPanel.statusText = "Password for " + wifiCredentialSsid + "  •  " +
                                    Array(value.length + 1).join("•") + "  •  ✓ connect"
        } else if (textTarget === "bluetooth") {
            btCredential = value
            btPanel.statusText = "PIN for " + btCredentialName + "  •  " +
                                 Array(value.length + 1).join("•") + "  •  ✓ pair"
        } else if (textTarget === "note") {
            notesBody = value
        } else if (textTarget === "note-title") {
            notesTitle = value
        } else if (textTarget === "package") {
            packageQuery = value
        } else {
            paletteQuery = value
        }
    }

    function handleLowerOskKey(key) {
        var value = activeText()
        if (key === "\b")
            value = value.length > 0 ? value.slice(0, -1) : ""
        else
            value += key
        applyText(value)
    }

    function handleLowerOskSubmit() {
        if (textTarget === "wifi") {
            if (wifiCredential.length === 0) {
                wifiPanel.statusText = "Enter a Wi-Fi password, then press ✓."
                return
            }
            wifiPanel.connect(wifiCredentialSsid, wifiCredential)
            wifiCredentialOpen = false
        } else if (textTarget === "bluetooth") {
            if (btCredential.length === 0) {
                btPanel.statusText = "Enter a Bluetooth PIN, then press ✓."
                return
            }
            btPanel.pair(btCredentialAddress, btCredential)
            btCredentialOpen = false
        } else if (textTarget === "package") {
            refreshPackages()
        } else if (textTarget === "note" || textTarget === "note-title") {
            // Keep editing; the note is written when the editor closes.
        } else {
            handleBack()
            return
        }
        lowerOskOpen = false
        if (textTarget !== "note") textTarget = "palette"
        lowerOsk.reset()
        writeState()
    }

    function handleLowerOsk() {
        if (activeScreen === "lock") return
        if (lowerOskOpen) {
            handleBack()
            return
        }
        if (!paletteOpen) {
            openExclusiveOverlay("palette")
            paletteOpen = true
            paletteQuery = ""
            paletteFocus = 0
            osk.reset()
        }
        textTarget = "palette"
        lowerOskOpen = true
        lowerOsk.reset()
        writeState()
    }

    function handlePalette() {
        if (lowerOskOpen) return
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
        // initialFocus is layout data, not a claim that the control works.  Park
        // on the first control the device actually reported as available, so the
        // controller never opens the panel on a dead row.
        quickSettingsFocus = quickSettingsConfig.initialFocus || 0
        if (!quickSettingAvailable(quickSettingsFocus))
            quickSettingsFocus = firstAvailableQuickSetting()
        refreshQuickSettings()
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
        if (lowerOskOpen) { lowerOsk.navUp(); return }
        if (paletteOpen) {
            paletteFocus = Math.max(0, paletteFocus - 1)
            return
        }
        if (radialOpen)       { moveRadial("up"); return }
        if (quickMenuOpen) {
            var menuCount = (quickMenuConfig.items || []).length
            quickMenuFocus = Math.max(0, quickMenuFocus - 1)
            quickMenuConfirming = false
            return
        }
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
        if (activeScreen === "app" && launchedApp === "Sysmon") {
            sysmonFocus = Math.max(0, sysmonFocus - 1)
            return
        }
        if (activeScreen === "app" && launchedApp === "Media") {
            mediaFocus = Math.max(0, mediaFocus - 1)
            return
        }

        if (activeScreen === "app" && launchedApp === "Files") {
            fileFocus = Math.max(0, fileFocus - 1)
            writeState()
            return
        }
        if (activeScreen === "app" && launchedApp === "Notes" && !notesEditing) {
            notesFocus = Math.max(0, notesFocus - 1)
            writeState()
            return
        }
        if (activeScreen === "app" && launchedApp === "Logview") {
            logFocus = Math.max(0, logFocus - 1)
            writeState()
            return
        }
        if (activeScreen === "app" && launchedApp === "Pkgman" && !packageDetailOpen) {
            packageFocus = Math.max(0, packageFocus - 1)
            writeState()
            return
        }
        if (activeScreen === "app" && launchedApp === "Settings") {
            if (settingsPane === "sidebar") settingsSection = Math.max(0, settingsSection - 1)
            else settingsRow = Math.max(0, settingsRow - 1)
            writeState()
            return
        }
        if (activeScreen === "home" && homeFocus >= gridApps.length) {
            homeFocus = gridApps.length - 1
            return
        }
        if (activeScreen === "home" && homeFocus >= 4) homeFocus -= 4
    }

    function navDown() {
        if (lowerOskOpen) { lowerOsk.navDown(); return }
        if (paletteOpen) {
            paletteFocus = Math.min(Math.max(0, paletteFiltered.length - 1), paletteFocus + 1)
            return
        }
        if (radialOpen)       { moveRadial("down"); return }
        if (quickMenuOpen) {
            var menuMax = Math.max(0, (quickMenuConfig.items || []).length - 1)
            quickMenuFocus = Math.min(menuMax, quickMenuFocus + 1)
            quickMenuConfirming = false
            return
        }
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
        if (activeScreen === "app" && launchedApp === "Media") {
            mediaFocus = Math.min(4, mediaFocus + 1)
            return
        }

        if (activeScreen === "app" && launchedApp === "Sysmon") {
            sysmonFocus = Math.min(5, sysmonFocus + 1)
            return
        }
        if (activePanel === "switcher") return
        if (oskOpen)          { osk.navDown(); return }
        if (activeScreen === "app" && launchedApp === "Files") {
            fileFocus = Math.min(Math.max(0, fileEntries.length - 1), fileFocus + 1)
            writeState()
            return
        }
        if (activeScreen === "app" && launchedApp === "Notes" && !notesEditing) {
            notesFocus = Math.min(Math.max(0, notes.length - 1), notesFocus + 1)
            writeState()
            return
        }
        if (activeScreen === "app" && launchedApp === "Logview") {
            logFocus = Math.min(Math.max(0, logLines.length - 1), logFocus + 1)
            writeState()
            return
        }
        if (activeScreen === "app" && launchedApp === "Pkgman" && !packageDetailOpen) {
            packageFocus = Math.min(Math.max(0, packages.length - 1), packageFocus + 1)
            writeState()
            return
        }
        if (activeScreen === "app" && launchedApp === "Settings") {
            if (settingsPane === "sidebar")
                settingsSection = Math.min(Math.max(0, settingsSections.length - 1), settingsSection + 1)
            else
                settingsRow = Math.min(Math.max(0, settingsSectionRows.length - 1), settingsRow + 1)
            writeState()
            return
        }
        if (activeScreen === "home") {
            if (homeFocus + 4 < gridApps.length) homeFocus += 4
            else if (homeFocus < gridApps.length) homeFocus = gridApps.length
        }
    }

    function navLeft() {
        if (lowerOskOpen) { lowerOsk.navLeft(); return }
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
        if (activeScreen === "app" && launchedApp === "Settings") {
            if (settingsPane === "rows") adjustSetting(-1)
            else settingsBackToSidebar()
            return
        }
        if (activeScreen === "home") homeFocus = Math.max(0, homeFocus - 1)
    }

    function navRight() {
        if (lowerOskOpen) { lowerOsk.navRight(); return }
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
        if (activeScreen === "app" && launchedApp === "Settings") {
            if (settingsPane === "rows") adjustSetting(1)
            else settingsEnterRows()
            return
        }
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
        if (id === "sys.lower-osk") { handleLowerOsk(); return }
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
        if (id === "sys.power") {
            handleQuickMenu()
            return
        }
        if (id === "sys.sleep") {
            runControl(launcherProc, ["power", "suspend"])
            return
        }
        if (id === "sys.dnd") {
            quickActionPendingId = id
            runControl(quickActionProc, ["quick-action", id, dndEnabled ? "off" : "on"])
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
        if (wifiPanelOpen && name === "north") {
            wifiPanel.scan()
            return
        }
        if (btPanelOpen && name === "north") {
            btPanel.toggleScan()
            return
        }
        if (activePanel === "notif" && name === "west") {
            dismissNotification(notificationsFocus)
            return
        }
        if (activePanel === "switcher" && name === "west") {
            forgetApp(switcherFocus)
            return
        }
        // App-local buttons. These override the global palette/radial bindings
        // only inside the apps whose hint bar advertises them.
        if (activeScreen === "app" && !anyOverlayOpen && !externalRunning) {
            if (launchedApp === "Notes") {
                if (name === "west")  { createNote(); return }
                if (name === "north") { deleteNote(notesFocus); return }
            } else if (launchedApp === "Logview") {
                if (name === "l1") { cycleLogSource(-1); return }
                if (name === "r1") { cycleLogSource(1); return }
                if (name === "north") { refreshLogs(); return }
            } else if (launchedApp === "Pkgman") {
                if (name === "west")  { openLowerOskFor("package"); return }
                if (name === "north") { packageQuery = ""; refreshPackages(); return }
            }
        }
        // An external client owns the screen.  east/start/mode stay Torchform's
        // guaranteed way out; every other button is forwarded to the client
        // through its configured control map.
        if (externalRunning) {
            if (name === "east") {
                closeExternal()
            } else if (name === "start" || name === "mode") {
                closeExternal()
                handleHome()
            } else {
                sendExternalKey(name)
            }
            return
        }
        if (lowerOskOpen) {
            switch (name) {
                case "south":      handleConfirm(); break
                case "east":       handleBack();    break
                case "dpad_up":    navUp();         break
                case "dpad_down":  navDown();       break
                case "dpad_left":  navLeft();       break
                case "dpad_right": navRight();      break
            }
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
            case "dpad_up":    navigateDirection("up");    break
            case "dpad_down":  navigateDirection("down");  break
            case "dpad_left":  navigateDirection("left");  break
            case "dpad_right": navigateDirection("right"); break
        }
    }

    // Chord / multiclick actions from input.toml (resolved by the plugin manifest).
    function onPadAction(name) {
        if (activeScreen === "lock") return
        switch (name) {
            case "switcher":   handleSwitcher(); break
            case "home":       handleHome();     break
            case "power_menu": handleQuickMenu(); break
            default:           showBanner("Action: " + name)
        }
    }

    // D-pad auto-repeat lives here (not in the daemon — the virtual pad keeps true
    // physical state for games). Held direction repeats after a delay, then faster.
    property string heldDir:      ""
    property int    repeatDelayMs: 350
    property int    repeatRateMs:  90
    property string analogDir:     ""
    property int    analogRepeatDelayMs: 350
    property int    analogRepeatRateMs:  90

    function navigateDirection(direction) {
        switch (direction) {
            case "up":    navUp();    break
            case "down":  navDown();  break
            case "left":  navLeft();  break
            case "right": navRight(); break
            default: return
        }
        writeState()
    }

    function handleAnalogAxes() {
        var x = Number(Gamepad.leftX)
        var y = Number(Gamepad.leftY)
        var threshold = 0.55
        var direction = ""
        if (Math.abs(x) >= threshold || Math.abs(y) >= threshold) {
            if (Math.abs(x) >= Math.abs(y))
                direction = x < 0 ? "left" : "right"
            else
                direction = y < 0 ? "up" : "down"
        }
        if (direction === analogDir) return
        analogDir = direction
        if (direction === "") {
            analogRepeat.stop()
            return
        }
        navigateDirection(direction)
        analogRepeat.interval = analogRepeatDelayMs
        analogRepeat.restart()
    }

    Timer {
        id: analogRepeat
        repeat: true
        interval: shell.analogRepeatDelayMs
        onTriggered: {
            interval = shell.analogRepeatRateMs
            if (shell.analogDir === "" || shell.externalRunning)
                stop()
            else
                shell.navigateDirection(shell.analogDir)
        }
    }


    Timer {
        id: navRepeat
        repeat: true
        onTriggered: {
            interval = shell.repeatRateMs   // first tick was the delay; speed up after
            // A held d-pad must repeat inside the client that owns the screen —
            // seeking or turning pages — not navigate the hidden shell behind it.
            if (shell.externalRunning)
                shell.sendExternalKey(shell.dpadButtonFor(shell.heldDir))
            else
                shell.navigateDirection(shell.heldDir)
        }
    }

    function dpadButtonFor(direction) {
        return ({ up: "dpad_up", down: "dpad_down",
                  left: "dpad_left", right: "dpad_right" })[direction] || ""
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
        function onAxesChanged() { shell.handleAnalogAxes() }
        function onActionTriggered(name) { shell.onPadAction(name) }
    }

    // ─── Upper display — 1920×1080 ────────────────────────────────────────────
    PanelWindow {
        id: upperWin
        screen: shell.upperScreen

        // Bottom keeps the shell below XDG toplevels so an external app is
        // actually visible; Overlay restores the shell chrome when it exits.
        WlrLayershell.layer: shell.externalRunning ? WlrLayer.Bottom : WlrLayer.Overlay
        WlrLayershell.keyboardFocus: shell.externalRunning
                                  ? WlrKeyboardFocus.None
                                  : (shell.anyOverlayOpen || shell.focusReclaim
                                     ? WlrKeyboardFocus.Exclusive
                                     : WlrKeyboardFocus.OnDemand)
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
                    case Qt.Key_Up:     shell.navigateDirection("up");    break
                    case Qt.Key_Down:   shell.navigateDirection("down");  break
                    case Qt.Key_Left:   shell.navigateDirection("left");  break
                    case Qt.Key_Right:  shell.navigateDirection("right"); break
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
                    sysmonFocus: shell.sysmonFocus
                    sysmonHistory: shell.sysmonHistory
                    mediaFocus: shell.mediaFocus
                    notes: shell.notes
                    notesFocus: shell.notesFocus
                    notesLoading: shell.notesLoading
                    notesStatus: shell.notesStatus
                    notesEditing: shell.notesEditing
                    notesTitle: shell.notesTitle
                    notesBody: shell.notesBody
                    logSources: shell.logSources
                    logSourceIndex: shell.logSourceIndex
                    logLines: shell.logLines
                    logFocus: shell.logFocus
                    logsLoading: shell.logsLoading
                    logsStatus: shell.logsStatus
                    packages: shell.packages
                    packageFocus: shell.packageFocus
                    packageQuery: shell.packageQuery
                    packagesLoading: shell.packagesLoading
                    packagesStatus: shell.packagesStatus
                    packageDetails: shell.packageDetails
                    packageDetailOpen: shell.packageDetailOpen
                    settingsSections: shell.settingsSections
                    settingsRows: shell.settingsSectionRows
                    settingsSection: shell.settingsSection
                    settingsRow: shell.settingsRow
                    settingsPane: shell.settingsPane
                    settingsLoading: shell.settingsLoading
                    settingsStatus: shell.settingsStatus

                    onHomeRequested: shell.handleHome()
                    onFileEntryActivated: (index) => shell.openFileEntry(index)
                    onFileParentRequested: shell.parentFiles()
                    onFileRefreshRequested: shell.refreshFiles()
                    onFileBookmarkRequested: (path) => shell.refreshFiles(path)
                    onTerminalCommandSubmitted: (command) => shell.submitTerminal(command)
                    onMediaActionRequested: (action) => shell.handleMediaAction(action)

                    onTerminalExternalRequested: shell.launchExternal("terminal")
                    onSysmonRefreshRequested: shell.sampleSysmon()
                    onNoteFocusRequested: (index) => shell.notesFocus = index
                    onNoteActivated: (index) => shell.openNote(index)
                    onNoteCreateRequested: shell.createNote()
                    onNoteDeleteRequested: (index) => shell.deleteNote(index)
                    onNoteEditRequested: shell.openLowerOskFor("note")
                    onLogSourceRequested: (index) => {
                        shell.logSourceIndex = index
                        shell.refreshLogs()
                    }
                    onLogRefreshRequested: shell.refreshLogs()
                    onLogFocusRequested: (index) => shell.logFocus = index
                    onPackageFocusRequested: (index) => shell.packageFocus = index
                    onPackageActivated: (index) => shell.openPackage(index)
                    onPackageSearchRequested: shell.openLowerOskFor("package")
                    onPackageRefreshRequested: {
                        shell.packageQuery = ""
                        shell.refreshPackages()
                    }
                    onSettingsSectionRequested: (index) => {
                        shell.settingsSection = index
                        shell.settingsRow = 0
                        shell.settingsPane = "sidebar"
                    }
                    onSettingsRowRequested: (index) => {
                        shell.settingsPane = "rows"
                        shell.settingsRow = index
                    }
                    onSettingsRowActivated: (index) => {
                        shell.settingsPane = "rows"
                        shell.settingsRow = index
                        shell.activateSetting()
                    }
                    onSettingsRowAdjusted: (index, delta) => {
                        shell.settingsPane = "rows"
                        shell.settingsRow = index
                        shell.adjustSetting(delta)
                    }
                }


                // Overlays (ordered back to front) ─────────────────────────

                QuickSettings {
                    anchors.fill: parent
                    open: shell.activePanel === "qs"
                    config: shell.quickSettingsConfig
                    sliderValues: shell.quickSettingsSliderValues
                    tileStates: shell.quickSettingsTileStates
                    sliderAvailability: shell.quickSettingsSliderAvailability
                    sliderReasons: shell.quickSettingsSliderReasons
                    tileAvailability: shell.quickSettingsTileAvailability
                    tileReasons: shell.quickSettingsTileReasons
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
                    onConnectRequested: (ssid, secured) => {
                        if (secured)
                            shell.openWifiCredential(ssid)
                        else
                            wifiPanel.connect(ssid, "")
                    }
                }

                BluetoothPanel {
                    id: btPanel
                    anchors.fill: parent
                    open:        shell.btPanelOpen
                    focusIndex:  shell.btFocus
                    onClosed:    shell.handleBack()
                    onNotice: (msg) => shell.showBanner(msg)
                    onPairingRequested: (address, name) => shell.openBluetoothCredential(address, name)
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
                    config: ({ title: shell.switcherConfig.title,
                               cardWidth: shell.switcherConfig.cardWidth,
                               cardHeight: shell.switcherConfig.cardHeight,
                               spacing: shell.switcherConfig.spacing,
                               apps: shell.sessionApps })
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

                QuickMenu {
                    anchors.fill: parent
                    open: shell.quickMenuOpen
                    config: shell.quickMenuConfig
                    focusIndex: shell.quickMenuFocus
                    confirming: shell.quickMenuConfirming
                    onItemActivated: (idx) => {
                        shell.quickMenuFocus = idx
                        shell.activateQuickMenu()
                    }
                    onDismissed: shell.handleBack()
                }

                // OSK — sits at the bottom, visible when palette is open.
                OnScreenKeyboard {
                    id: osk
                    anchors.fill: parent
                    open: shell.paletteOpen && !shell.lowerOskOpen
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
            activeApp:     shell.externalRunning
                           ? shell.externalApp
                           : (shell.activeScreen === "app" ? shell.launchedApp : "")
            batteryPct:    shell.batteryPct
            batteryKnown:  shell.batteryKnown
            batteryStatus: shell.batteryStatus
            lowBattery:    shell.lowBattery
            paletteOpen:   shell.paletteOpen
            radialOpen:    shell.radialOpen
            oskOpen:       shell.lowerOskOpen
            externalApp:     shell.externalApp
            externalRunning: shell.externalRunning
            appContext:      shell.lowerAppContext
            externalControls: shell.externalControls
            actions:       Data.lowerActions
            onActionTriggered: (id) => shell.launchCommand(id)
            onOskRequested: shell.handleLowerOsk()
        }

        OnScreenKeyboard {
            id: lowerOsk
            anchors.fill: parent
            open: shell.lowerOskOpen
            compact: true
            onKeyEmitted: (key) => shell.handleLowerOskKey(key)
            onCloseRequested: shell.handleLowerOskSubmit()
        }
    }
}
