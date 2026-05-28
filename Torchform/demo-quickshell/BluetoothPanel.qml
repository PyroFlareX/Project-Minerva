import QtQuick
import "."

// Bluetooth panel — slides in from left (same side as Notifications).
// Static device list for now; extend with bluetoothctl/BlueZ D-Bus once QS_DBUS is built.
//
// BlueZ D-Bus: org.bluez  /  adapter path: /org/bluez/hci0
// Scan: org.bluez.Adapter1.StartDiscovery()
// Pair: org.bluez.Device1.Pair() + Trust() + Connect()
Item {
    id: root
    property bool open: false
    property int  focusIndex: 0
    property bool scanning: false

    signal closed()
    signal pairRequested(string address)

    Rectangle {
        id: panel
        anchors { top: parent.top; bottom: parent.bottom }
        width: 300
        x: root.open ? 0 : -width
        color: Tokens.bgSurface
        border.color: Tokens.border
        border.width: 1

        Behavior on x { NumberAnimation { duration: Tokens.animNormal; easing.type: Easing.OutCubic } }

        // Accent strip (right edge)
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

            // Header row
            Item {
                width: parent.width - 32
                height: 32
                Text {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: "Bluetooth"
                    font.pixelSize: 15
                    font.family: Tokens.fontDisplay
                    font.weight: Font.SemiBold
                    color: Tokens.textPrimary
                }
                Rectangle {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: 52; height: 22; radius: Tokens.rSm
                    color: root.scanning ? Tokens.accentGlow : Tokens.bgElevated
                    border.color: Tokens.primary; border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: root.scanning ? "Stop" : "Scan"
                        font.pixelSize: 9
                        font.family: Tokens.fontMono
                        color: Tokens.primary
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.scanning = !root.scanning }
                }
            }

            Text {
                text: "Paired"
                font.pixelSize: 10
                font.family: Tokens.fontMono
                color: Tokens.textDisabled
                topPadding: 10
                bottomPadding: 6
            }

            Repeater {
                model: btDevices.filter(d => d.paired)
                delegate: btDeviceRow
            }

            Text {
                visible: root.scanning
                text: "Nearby"
                font.pixelSize: 10
                font.family: Tokens.fontMono
                color: Tokens.textDisabled
                topPadding: 10
                bottomPadding: 6
            }

            Repeater {
                visible: root.scanning
                model: root.scanning ? btDevices.filter(d => !d.paired) : []
                delegate: btDeviceRow
            }
        }

        // Close handle
        Rectangle {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: 20; height: 60
            color: Tokens.bgElevated
            border.color: Tokens.border; border.width: 1; radius: 4
            Text { anchors.centerIn: parent; text: "‹"; font.pixelSize: 14; color: Tokens.textSecondary }
            MouseArea { anchors.fill: parent; onClicked: root.closed() }
        }
    }

    // Backdrop
    MouseArea {
        anchors { left: panel.right; top: parent.top; bottom: parent.bottom; right: parent.right }
        enabled: root.open
        onClicked: root.closed()
    }

    component btDeviceRow: Rectangle {
        width: panel.width - 32
        height: 52
        radius: Tokens.rMd
        color: Tokens.bgElevated
        border.color: modelData.connected ? Tokens.primary : Tokens.borderSubtle
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
                    Text {
                        text: modelData.name
                        font.pixelSize: 12; font.family: Tokens.fontSans
                        color: Tokens.textPrimary
                    }
                    Rectangle {
                        visible: modelData.connected
                        width: 36; height: 14; radius: 7
                        color: "#1a1a3a"
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.centerIn: parent
                            text: "on"
                            font.pixelSize: 8; font.family: Tokens.fontMono
                            color: Tokens.primary
                        }
                    }
                }
                Text {
                    text: modelData.type
                    font.pixelSize: 9; font.family: Tokens.fontMono
                    color: Tokens.textDisabled
                }
            }
            Rectangle {
                visible: !modelData.connected
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: modelData.paired ? 56 : 46
                height: 22; radius: Tokens.rSm
                color: Tokens.bgBase
                border.color: Tokens.primary; border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: modelData.paired ? "Connect" : "Pair"
                    font.pixelSize: 9; font.family: Tokens.fontMono
                    color: Tokens.primary
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.pairRequested(modelData.address)
                }
            }
        }
    }

    property var btDevices: [
        { name: "Gamepad",        address: "00:1A:7D:DA:71:01", type: "HID · Controller",   icon: "🎮", paired: true,  connected: true  },
        { name: "JBL Clip 4",     address: "AC:12:2F:B1:44:22", type: "Audio · Speaker",     icon: "🔊", paired: true,  connected: false },
        { name: "MX Keys Mini",   address: "34:88:5D:6E:CC:03", type: "HID · Keyboard",      icon: "⌨️", paired: false, connected: false },
        { name: "Pixel 8",        address: "FC:1C:AE:22:B0:77", type: "Phone",               icon: "📱", paired: false, connected: false },
    ]
}
