import QtQuick
import Quickshell.Io
import "."

// Wi-Fi panel — controller-friendly wrapper around iwd's iwctl.
Item {
    id: root
    property bool open: false
    property int  focusIndex: 0
    property bool scanning: false
    property var  wifiNetworks: []
    property string statusText: "Loading Wi-Fi…"

    readonly property int itemCount: wifiNetworks.length

    signal closed()
    signal notice(string message)

    onOpenChanged: if (open) refresh()

    function refresh() {
        scanning = true
        wifiListProc.running = true
    }

    function activateFocused() {
        if (wifiNetworks.length === 0) {
            refresh()
            return
        }
        var net = wifiNetworks[Math.max(0, Math.min(focusIndex, wifiNetworks.length - 1))]
        statusText = "Connecting to " + net.ssid + "…"
        wifiConnectProc.command = ["sh", "-lc", "cd \"$HOME/projects/torchform-guishell\" && sh ./torchform-control.sh wifi-connect \"$1\"", "torchform-wifi", net.ssid]
        wifiConnectProc.running = true
    }

    Process {
        id: wifiListProc
        command: ["sh", "-lc", "cd \"$HOME/projects/torchform-guishell\" && sh ./torchform-control.sh wifi-list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var rows = []
                var status = "No networks found."
                for (var line of text.trim().split("\n")) {
                    if (line.length === 0) continue
                    var parts = line.split("|")
                    if (parts[0] === "status") {
                        status = parts.slice(1).join("|")
                    } else if (parts[0] === "network") {
                        rows.push({
                            ssid: parts[1] || "<hidden>",
                            rssi: Number(parts[2] || 0),
                            band: parts[3] || "secured",
                            secured: (parts[3] || "").toLowerCase() !== "open",
                            connected: parts[4] === "1"
                        })
                    }
                }
                root.wifiNetworks = rows
                root.statusText = rows.length > 0 ? "A connect  •  D-PAD choose  •  Scan refreshes" : status
                root.scanning = false
            }
        }
    }

    Process {
        id: wifiConnectProc
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
        x: root.open ? parent.width - width : parent.width
        color: Tokens.bgSurface
        border.color: Tokens.border
        border.width: 1

        Behavior on x { NumberAnimation { duration: Tokens.animNormal; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors { top: parent.top; left: parent.left; bottom: parent.bottom }
            width: 2
            color: Tokens.accent
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
                    text: "Wi-Fi"
                    font.pixelSize: 15
                    font.family: Tokens.fontDisplay
                    font.weight: Font.DemiBold
                    color: Tokens.textPrimary
                }
                Rectangle {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: 52; height: 22; radius: Tokens.rSm
                    color: root.scanning ? Tokens.accentGlow : Tokens.bgElevated
                    border.color: Tokens.accent; border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: root.scanning ? "Scan…" : "Scan"
                        font.pixelSize: 9
                        font.family: Tokens.fontMono
                        color: Tokens.accent
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.refresh() }
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
                color: root.wifiNetworks.length > 0 ? Tokens.textDisabled : Tokens.warning
            }

            Repeater {
                model: root.wifiNetworks
                delegate: Rectangle {
                    width: panel.width - 32
                    height: 56
                    radius: Tokens.rMd
                    color: root.open && index === root.focusIndex ? Tokens.accentGlow : Tokens.bgElevated
                    border.color: root.open && index === root.focusIndex ? Tokens.accent : Tokens.borderSubtle
                    border.width: 1

                    Item {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 12 }
                        height: 36

                        Column {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            spacing: 2
                            Row {
                                spacing: 6
                                Text { text: modelData.secured ? "🔒" : "📶"; font.pixelSize: 11 }
                                Text {
                                    text: modelData.ssid
                                    font.pixelSize: 12
                                    font.family: Tokens.fontSans
                                    color: modelData.connected ? Tokens.accent : Tokens.textPrimary
                                }
                                Rectangle {
                                    visible: modelData.connected
                                    width: 36; height: 14; radius: 7
                                    color: Tokens.accentGlow
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text { anchors.centerIn: parent; text: "active"; font.pixelSize: 8; font.family: Tokens.fontMono; color: Tokens.accent }
                                }
                            }
                            Text {
                                text: signalBar(modelData.rssi) + "  " + modelData.band
                                font.pixelSize: 9
                                font.family: Tokens.fontMono
                                color: Tokens.textDisabled
                            }
                        }

                        Rectangle {
                            visible: root.open && index === root.focusIndex && !modelData.connected
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: 56; height: 22; radius: Tokens.rSm
                            color: Tokens.accent
                            Text { anchors.centerIn: parent; text: "Connect"; font.pixelSize: 9; font.family: Tokens.fontMono; color: "#000000" }
                            MouseArea { anchors.fill: parent; onClicked: root.activateFocused() }
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: 20; height: 60
            color: Tokens.bgElevated
            border.color: Tokens.border; border.width: 1; radius: 4
            Text { anchors.centerIn: parent; text: "›"; font.pixelSize: 14; color: Tokens.textSecondary }
            MouseArea { anchors.fill: parent; onClicked: root.closed() }
        }
    }

    MouseArea {
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: panel.left }
        enabled: root.open
        onClicked: root.closed()
    }

    function signalBar(rssi) {
        if (rssi >= -50) return "▂▄▆█"
        if (rssi >= -65) return "▂▄▆░"
        if (rssi >= -75) return "▂▄░░"
        return "▂░░░"
    }
}
