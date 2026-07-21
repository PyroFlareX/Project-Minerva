import QtQuick
import "."

Item {
    id: root
    property bool open: false

    signal closed()

    // Slide in from right
    Rectangle {
        id: panel
        anchors { top: parent.top; bottom: parent.bottom }
        width: 280
        x: root.open ? parent.width - width : parent.width
        color: Tokens.bgSurface
        border.color: Tokens.border
        border.width: 1

        Behavior on x { NumberAnimation { duration: Tokens.animNormal; easing.type: Easing.OutCubic } }

        // Accent strip
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

            // Header
            Text {
                text: "Quick Settings"
                font.pixelSize: 15
                font.family: Tokens.fontDisplay
                font.weight: Font.SemiBold
                color: Tokens.textPrimary
                bottomPadding: 14
                leftPadding: 2
            }

            // Sliders
            SliderRow { label: "Volume";     icon: "🔉"; value: 72 }
            Item { width: 1; height: 10 }
            SliderRow { label: "Brightness"; icon: "🔆"; value: 85 }
            Item { width: 1; height: 16 }

            // Tile grid (2 cols)
            Grid {
                width: parent.width - 32
                columns: 2
                spacing: 8

                Repeater {
                    model: qsTiles
                    delegate: Rectangle {
                        width: (parent.width - 8) / 2
                        height: 60
                        radius: Tokens.rMd
                        color: modelData.on ? Tokens.accentGlow : Tokens.bgElevated
                        border.color: modelData.on ? Tokens.accent : Tokens.border
                        border.width: 1

                        Column {
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.icon
                                font.pixelSize: 20
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.name
                                font.pixelSize: 10
                                font.family: Tokens.fontSans
                                color: modelData.on ? Tokens.accent : Tokens.textSecondary
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                qsTiles[index].on = !qsTiles[index].on
                                qsTilesChanged()
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
            border.color: Tokens.border
            border.width: 1
            radius: 4
            Text {
                anchors.centerIn: parent
                text: "›"
                font.pixelSize: 14
                color: Tokens.textSecondary
            }
            MouseArea { anchors.fill: parent; onClicked: root.closed() }
        }
    }

    // Backdrop click-through
    MouseArea {
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: panel.left }
        enabled: root.open
        onClicked: root.closed()
    }

    property var qsTiles: [
        { icon: "📶", name: "Wi-Fi",       on: true  },
        { icon: "📡", name: "Bluetooth",   on: true  },
        { icon: "✈", name: "Airplane",    on: false },
        { icon: "🔕", name: "DND",         on: false },
        { icon: "🌙", name: "Dark Mode",   on: true  },
        { icon: "🔄", name: "Auto-rotate", on: false },
    ]

    component SliderRow: Item {
        width: parent.width - 32
        height: 40
        property string label: ""
        property string icon: ""
        property int value: 50

        Column {
            anchors.fill: parent
            spacing: 4
            Item {
                anchors { left: parent.left; right: parent.right }
                height: labelText.implicitHeight
                Text {
                    id: labelText
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: icon + " " + label
                    font.pixelSize: 11
                    font.family: Tokens.fontSans
                    color: Tokens.textSecondary
                }
                Text {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: value + "%"
                    font.pixelSize: 11
                    font.family: Tokens.fontMono
                    color: Tokens.textSecondary
                }
            }
            Rectangle {
                width: parent.width; height: 4; radius: 2
                color: Tokens.bgElevated
                Rectangle {
                    width: parent.width * (value / 100); height: 4; radius: 2
                    color: Tokens.accent
                }
            }
        }
    }
}
