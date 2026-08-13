import QtQuick
import "."

Rectangle {
    id: root
    color: Tokens.bgBase

    property string appName: "Terminal"
    property string appIcon: "⬛"
    property string appBg:   "#0d1117"
    property string mode: appName.toLowerCase()
    property var fileEntries: []
    property string filePath: "~"
    property int fileFocus: 0
    property bool filesLoading: false
    property string filesStatus: ""
    property var terminalLines: []
    property bool terminalRunning: false
    property var sysmonMetrics: ({})
    property string sysmonUpdated: "waiting"
    property int sysmonFocus: 0
    property var sysmonHistory: []
    property int mediaFocus: 0

    property var    notes: []
    property int    notesFocus: 0
    property bool   notesLoading: false
    property string notesStatus: ""
    property bool   notesEditing: false
    property string notesTitle: ""
    property string notesBody: ""

    property var    logSources: []
    property int    logSourceIndex: 0
    property var    logLines: []
    property int    logFocus: 0
    property bool   logsLoading: false
    property string logsStatus: ""

    property var    packages: []
    property int    packageFocus: 0
    property string packageQuery: ""
    property bool   packagesLoading: false
    property string packagesStatus: ""
    property var    packageDetails: []
    property bool   packageDetailOpen: false

    property var    settingsSections: []
    property var    settingsRows: []
    property int    settingsSection: 0
    property int    settingsRow: 0
    property string settingsPane: "sidebar"
    property bool   settingsLoading: false
    property string settingsStatus: ""

    signal homeRequested()
    signal fileEntryActivated(int index)
    signal fileParentRequested()
    signal fileRefreshRequested()
    signal fileBookmarkRequested(string path)
    signal terminalCommandSubmitted(string command)
    signal terminalExternalRequested()
    signal sysmonRefreshRequested()
    signal mediaActionRequested(string action)
    signal noteFocusRequested(int index)
    signal noteActivated(int index)
    signal noteCreateRequested()
    signal noteDeleteRequested(int index)
    signal noteEditRequested()
    signal logSourceRequested(int index)
    signal logRefreshRequested()
    signal logFocusRequested(int index)
    signal packageFocusRequested(int index)
    signal packageActivated(int index)
    signal packageSearchRequested()
    signal packageRefreshRequested()
    signal settingsSectionRequested(int index)
    signal settingsRowRequested(int index)
    signal settingsRowActivated(int index)
    signal settingsRowAdjusted(int index, int delta)

    function activateMedia() {
        var item = mediaView.actions[root.mediaFocus]
        if (item) root.mediaActionRequested(item.action)
    }

    Rectangle {
        id: titleBar
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 42
        color: Tokens.bgSurface
        border.color: Tokens.borderSubtle
        border.width: 1

        Row {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: Tokens.sp3 }
            spacing: Tokens.sp2

            Rectangle {
                width: 26; height: 26; radius: Tokens.rSm
                color: root.appBg
                Text { anchors.centerIn: parent; text: root.appIcon; font.pixelSize: 15 }
            }
            Text {
                text: root.appName
                font.pixelSize: 15
                font.family: Tokens.fontDisplay
                font.weight: Font.DemiBold
                color: Tokens.textPrimary
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: Tokens.sp3 }
            spacing: Tokens.sp3

            GamepadGlyph {
                button: "B"
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: root.mode === "files" ? "Back" : "Home"
                font.pixelSize: 9
                font.family: Tokens.fontSans
                color: Tokens.textDisabled
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    TerminalView {
        id: terminalView
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        visible: root.mode === "terminal"
        lines: root.terminalLines
        running: root.terminalRunning
        onCommandSubmitted: root.terminalCommandSubmitted(command)
        onExternalRequested: root.terminalExternalRequested()
    }

    function focusTerminalInput() {
        if (root.mode === "terminal") terminalView.focusInput()
    }

    function submitTerminalInput() {
        if (root.mode === "terminal")
            terminalView.submitInput()
    }

    FilesView {
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        visible: root.mode === "files"
        path: root.filePath
        entries: root.fileEntries
        focusIndex: root.fileFocus
        loading: root.filesLoading
        statusText: root.filesStatus
        onEntryActivated: root.fileEntryActivated(index)
        onFocusRequested: root.fileFocus = index
        onParentRequested: root.fileParentRequested()
        onRefreshRequested: root.fileRefreshRequested()
        onBookmarkRequested: root.fileBookmarkRequested(path)
    }

    SysmonView {
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        visible: root.mode === "sysmon"
        metrics: root.sysmonMetrics
        history: root.sysmonHistory
        focusIndex: root.sysmonFocus
        updated: root.sysmonUpdated
        onRefreshRequested: root.sysmonRefreshRequested()
    }

    MediaView {
        id: mediaView
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        visible: root.mode === "media"
        focusIndex: root.mediaFocus
        onActionRequested: root.mediaActionRequested(action)
    }

    NotesView {
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        visible: root.mode === "notes"
        notes: root.notes
        focusIndex: root.notesFocus
        loading: root.notesLoading
        statusText: root.notesStatus
        editing: root.notesEditing
        title: root.notesTitle
        body: root.notesBody
        onFocusRequested: (index) => root.noteFocusRequested(index)
        onNoteActivated: (index) => root.noteActivated(index)
        onCreateRequested: root.noteCreateRequested()
        onDeleteRequested: (index) => root.noteDeleteRequested(index)
        onEditRequested: root.noteEditRequested()
    }

    LogView {
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        visible: root.mode === "logview"
        sources: root.logSources
        sourceIndex: root.logSourceIndex
        lines: root.logLines
        focusIndex: root.logFocus
        loading: root.logsLoading
        statusText: root.logsStatus
        onSourceRequested: (index) => root.logSourceRequested(index)
        onRefreshRequested: root.logRefreshRequested()
        onFocusRequested: (index) => root.logFocusRequested(index)
    }

    PkgmanView {
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        visible: root.mode === "pkgman"
        packages: root.packages
        focusIndex: root.packageFocus
        query: root.packageQuery
        loading: root.packagesLoading
        statusText: root.packagesStatus
        details: root.packageDetails
        detailOpen: root.packageDetailOpen
        onFocusRequested: (index) => root.packageFocusRequested(index)
        onPackageActivated: (index) => root.packageActivated(index)
        onSearchRequested: root.packageSearchRequested()
        onRefreshRequested: root.packageRefreshRequested()
    }

    SettingsView {
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        visible: root.mode === "settings"
        sections: root.settingsSections
        rows: root.settingsRows
        sectionIndex: root.settingsSection
        rowIndex: root.settingsRow
        pane: root.settingsPane
        loading: root.settingsLoading
        statusText: root.settingsStatus
        onSectionRequested: (index) => root.settingsSectionRequested(index)
        onRowRequested: (index) => root.settingsRowRequested(index)
        onRowActivated: (index) => root.settingsRowActivated(index)
        onRowAdjusted: (index, delta) => root.settingsRowAdjusted(index, delta)
    }

    Rectangle {
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        visible: ["terminal", "files", "sysmon", "media", "notes", "logview", "pkgman", "settings"].indexOf(root.mode) < 0
        color: root.appBg

        Column {
            anchors.centerIn: parent
            spacing: Tokens.sp3
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.appIcon
                font.pixelSize: 42
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.appName + " is ready"
                font.pixelSize: 18
                font.family: Tokens.fontDisplay
                color: Tokens.textPrimary
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "This app is not connected to a device backend yet."
                font.pixelSize: 11
                font.family: Tokens.fontMono
                color: Tokens.textDisabled
            }
        }
    }
}
