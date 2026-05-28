import QtQuick
import "."

// WiFi panel — slides in from right (same side as QuickSettings).
// Static network list for now; extend with `iwd` D-Bus calls once QS_DBUS is built in.
//
// iwd D-Bus path: org.freedesktop.NetworkManager or fi.w1.wpa_supplicant1
// Alpine prefers iwd: `iwctl station wlan0 scan && iwctl station wlan0 get-networks`
Item {
    id: root
    property bool open: false
    property int  focusIndex: 0
    property bool scanning: false

    signal closed()
    signal connectRequested(string ssid)

    Rectangle {
        id: panel
        anchors { top: parent.top; bottom: parent.bottom }
        width: 300
        x: root.open ? parent.width - width : parent.width
        color: Tokens.bgSurface
        border.color: Tokens.border
        border.width: 1

        Behavior on x { NumberAnimation { duration: Tokens.animNormal; easing.type: Easing.OutCubic } }

        // Accent strip (left edge)
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

            // Header row
            Item {
                width: parent.width - 32
                height: 32
                Text {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: "Wi-Fi"
                    font.pixelSize: 15
                    font.family: Tokens.fontDisplay
                    font.weight: Font.SemiBold
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
                    MouseArea { anchors.fill: parent; onClicked: root.scanning = !root.scanning }
                }
            }

            Item { width: 1; height: 12 }

            // Network list
            Repeater {
                model: wifiNetworks
                delegate: Rectangle {
                    width: panel.width - 32
                    height: 56
                    radius: Tokens.rMd
                    color: root.open && index === root.focusIndex
                           ? Tokens.accentGlow : Tokens.bgElevated
                    border.color: root.open && index === root.focusIndex
                                  ? Tokens.accent : Tokens.borderSubtle
                    border.width: 1

                    Item {
                        anchors { left: parent.left; right: parent.right
                                  verticalCenter: parent.verticalCenter
                                  leftMargin: 12; rightMargin: 12 }
                        height: 36

                        Column {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            spacing: 2
                            Row {
                                spacing: 6
                                Text { text: modelData.secured ? "🔒" : "📶"
                                       font.pixelSize: 11 }
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
                                    Text {
                                        anchors.centerIn: parent
                                        text: "active"
                                        font.pixelSize: 8; font.family: Tokens.fontMono
                                        color: Tokens.accent
                                    }
                                }
                            }
                            Text {
                                text: signalBar(modelData.rssi) + "  " + modelData.band
                                font.pixelSize: 9
                                font.family: Tokens.fontMono
                                color: Tokens.textDisabled
                            }
                        }

                        // Connect button (shown when focused)
                        Rectangle {
                            visible: root.open && index === root.focusIndex && !modelData.connected
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: 56; height: 22; radius: Tokens.rSm
                            color: Tokens.accent
                            Text {
                                anchors.centerIn: parent
                                text: "Connect"
                                font.pixelSize: 9; font.family: Tokens.fontMono
                                color: "#000000"
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.connectRequested(modelData.ssid)
                            }
                        }
                    }
                }
            }
        }

        // Close handle
        Rectangle {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: 20; height: 60
            color: Tokens.bgElevated
            border.color: Tokens.border; border.width: 1; radius: 4
            Text { anchors.centerIn: parent; text: "›"; font.pixelSize: 14; color: Tokens.textSecondary }
            MouseArea { anchors.fill: parent; onClicked: root.closed() }
        }
    }

    // Backdrop
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

    property var wifiNetworks: [
        { ssid: "Minerva-AP",   rssi: -42, band: "5GHz", secured: true,  connected: true  },
        { ssid: "HomeNet",      rssi: -61, band: "2.4GHz",secured: true,  connected: false },
        { ssid: "OpenWifi",     rssi: -70, band: "2.4GHz",secured: false, connected: false },
        { ssid: "iPhone (Zack)",rssi: -78, band: "2.4GHz",secured: true,  connected: false },
    ]
}
