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

    signal homeRequested()
    signal fileEntryActivated(int index)
    signal fileParentRequested()
    signal fileRefreshRequested()
    signal fileBookmarkRequested(string path)
    signal terminalCommandSubmitted(string command)
    signal terminalExternalRequested()
    signal sysmonRefreshRequested()

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
                text: "Home"
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
        onParentRequested: root.fileParentRequested()
        onRefreshRequested: root.fileRefreshRequested()
        onBookmarkRequested: root.fileBookmarkRequested(path)
    }

    SysmonView {
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        visible: root.mode === "sysmon"
        metrics: root.sysmonMetrics
        updated: root.sysmonUpdated
        onRefreshRequested: root.sysmonRefreshRequested()
    }

    Rectangle {
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        visible: root.mode !== "terminal" && root.mode !== "files" && root.mode !== "sysmon"
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
