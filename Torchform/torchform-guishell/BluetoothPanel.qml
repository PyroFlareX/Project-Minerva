import QtQuick
import Quickshell.Io
import "."

// Bluetooth panel — controller-friendly wrapper around BlueZ bluetoothctl.
Item {
    id: root
    property bool open: false
    property int  focusIndex: 0
    property bool scanning: false
    property var  btDevices: []
    property string statusText: "Loading Bluetooth…"

    readonly property int itemCount: btDevices.length

    signal closed()
    signal notice(string message)

    onOpenChanged: if (open) refresh()

    function refresh() {
        btListProc.running = true
    }

    function toggleScan() {
        scanning = !scanning
        btScanProc.command = ["sh", "-lc", "cd \"$HOME/projects/torchform-guishell\" && sh ./torchform-control.sh " + (scanning ? "bluetooth-scan" : "bluetooth-stop-scan")]
        btScanProc.running = true
    }

    function activateFocused() {
        if (btDevices.length === 0) {
            refresh()
            return
        }
        var dev = btDevices[Math.max(0, Math.min(focusIndex, btDevices.length - 1))]
        statusText = (dev.paired ? "Connecting to " : "Pairing ") + dev.name + "…"
        btConnectProc.command = ["sh", "-lc", "cd \"$HOME/projects/torchform-guishell\" && sh ./torchform-control.sh bluetooth-connect \"$1\"", "torchform-bt", dev.address]
        btConnectProc.running = true
    }

    Process {
        id: btListProc
        command: ["sh", "-lc", "cd \"$HOME/projects/torchform-guishell\" && sh ./torchform-control.sh bluetooth-list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var rows = []
                var status = "No Bluetooth devices found."
                for (var line of text.trim().split("\n")) {
                    if (line.length === 0) continue
                    var parts = line.split("|")
                    if (parts[0] === "status") {
                        status = parts.slice(1).join("|")
                    } else if (parts[0] === "device") {
                        rows.push({
                            address: parts[1],
                            name: parts[2] || parts[1],
                            paired: (parts[3] || "no") === "yes",
                            connected: (parts[4] || "no") === "yes",
                            icon: parts[5] || "📱",
                            type: ((parts[3] || "no") === "yes" ? "Paired" : "Nearby")
                        })
                    }
                }
                root.btDevices = rows
                root.focusIndex = Math.max(0, Math.min(root.focusIndex, Math.max(0, rows.length - 1)))
                root.statusText = rows.length > 0 ? "A pair/connect  •  D-PAD choose  •  Scan refreshes" : status
            }
        }
    }

    Process {
        id: btScanProc
        stdout: StdioCollector {
            onStreamFinished: {
                var msg = text.trim().split("|").slice(1).join("|")
                if (msg.length === 0) msg = text.trim()
                root.statusText = msg
                root.notice(msg)
                root.refresh()
            }
        }
    }

    Process {
        id: btConnectProc
        stdout: StdioCollector {
            onStreamFinished: {
                var msg = text.trim().split("|").slice(1).join("|")
                if (msg.length === 0) msg = text.trim()
                root.statusText = msg
                root.notice(msg)
                root.refresh()
            }
        }
    }

    Rectangle {
        id: panel
        anchors { top: parent.top; bottom: parent.bottom }
        width: 300
        x: root.open ? 0 : -width
        color: Tokens.bgSurface
        border.color: Tokens.border
        border.width: 1

        Behavior on x { NumberAnimation { duration: Tokens.animNormal; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors { top: parent.top; right: parent.right; bottom: parent.bottom }
            width: 2
            color: Tokens.primary
        }

        Column {
            anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 16 }
            leftPadding: 16
            rightPadding: 16
            spacing: 0

            Item {
                width: parent.width - 32
                height: 32
                Text {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: "Bluetooth"
                    font.pixelSize: 15
                    font.family: Tokens.fontDisplay
                    font.weight: Font.DemiBold
                    color: Tokens.textPrimary
                }
                Rectangle {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: 52; height: 22; radius: Tokens.rSm
                    color: root.scanning ? Tokens.accentGlow : Tokens.bgElevated
                    border.color: Tokens.primary; border.width: 1
                    Text { anchors.centerIn: parent; text: root.scanning ? "Stop" : "Scan"; font.pixelSize: 9; font.family: Tokens.fontMono; color: Tokens.primary }
                    MouseArea { anchors.fill: parent; onClicked: root.toggleScan() }
                }
            }

            Text {
                width: panel.width - 32
                topPadding: 10
                bottomPadding: 8
                text: root.statusText
                wrapMode: Text.WordWrap
                font.pixelSize: 9
                font.family: Tokens.fontMono
                color: root.btDevices.length > 0 ? Tokens.textDisabled : Tokens.warning
            }

            Repeater {
                model: root.btDevices
                delegate: Rectangle {
                    width: panel.width - 32
                    height: 52
                    radius: Tokens.rMd
                    color: root.open && index === root.focusIndex ? "#1a1a3a" : Tokens.bgElevated
                    border.color: root.open && index === root.focusIndex ? Tokens.primary : (modelData.connected ? Tokens.primary : Tokens.borderSubtle)
                    border.width: 1

                    Item {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }

                        Text {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            text: modelData.icon
                            font.pixelSize: 20
                        }
                        Column {
                            anchors { left: parent.left; leftMargin: 36; verticalCenter: parent.verticalCenter }
                            spacing: 2
                            Row {
                                spacing: 6
                                Text { text: modelData.name; font.pixelSize: 12; font.family: Tokens.fontSans; color: Tokens.textPrimary }
                                Rectangle {
                                    visible: modelData.connected
                                    width: 36; height: 14; radius: 7
                                    color: "#1a1a3a"
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text { anchors.centerIn: parent; text: "on"; font.pixelSize: 8; font.family: Tokens.fontMono; color: Tokens.primary }
                                }
                            }
                            Text { text: modelData.type + "  " + modelData.address; font.pixelSize: 9; font.family: Tokens.fontMono; color: Tokens.textDisabled }
                        }
                        Rectangle {
                            visible: !modelData.connected && root.open && index === root.focusIndex
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: modelData.paired ? 56 : 46
                            height: 22; radius: Tokens.rSm
                            color: Tokens.bgBase
                            border.color: Tokens.primary; border.width: 1
                            Text { anchors.centerIn: parent; text: modelData.paired ? "Connect" : "Pair"; font.pixelSize: 9; font.family: Tokens.fontMono; color: Tokens.primary }
                            MouseArea { anchors.fill: parent; onClicked: root.activateFocused() }
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: 20; height: 60
            color: Tokens.bgElevated
            border.color: Tokens.border; border.width: 1; radius: 4
            Text { anchors.centerIn: parent; text: "‹"; font.pixelSize: 14; color: Tokens.textSecondary }
            MouseArea { anchors.fill: parent; onClicked: root.closed() }
        }
    }

    MouseArea {
        anchors { left: panel.right; top: parent.top; bottom: parent.bottom; right: parent.right }
        enabled: root.open
        onClicked: root.closed()
    }
}
