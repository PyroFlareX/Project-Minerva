import QtQuick
import "."

Rectangle {
    id: root
    color: Tokens.lowerBg

    required property string timeStr
    property string activeApp:   ""
    property int    batteryPct:  100
    property bool   paletteOpen: false
    property bool   radialOpen:  false

    // Status bar (top 28px)
    Rectangle {
        id: lowerBar
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 28
        color: "#cc0a0c11"
        border.color: Tokens.borderSubtle
        border.width: 0

        // Bottom hairline
        Rectangle {
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 1; color: Tokens.borderSubtle
        }

        Text {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 10 }
            text: "MINERVA"
            font.pixelSize: 9
            font.family: Tokens.fontDisplay
            font.weight: Font.Bold
            color: Tokens.accentDim
            font.letterSpacing: 2
        }

        Text {
            anchors.centerIn: parent
            text: root.timeStr
            font.pixelSize: 12
            font.family: Tokens.fontMono
            color: Tokens.textPrimary
        }

        Text {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 10 }
            text: "🔋 " + root.batteryPct + "%"
            font.pixelSize: 10
            font.family: Tokens.fontMono
            color: Tokens.textSecondary
        }
    }

    // Main content area
    Item {
        anchors { top: lowerBar.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }

        // Default: idle status
        Column {
            visible: !root.paletteOpen && !root.radialOpen
            anchors.centerIn: parent
            spacing: 16

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "◎"
                font.pixelSize: 36
                color: Tokens.accentDim
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.4; duration: 1800; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 1800; easing.type: Easing.InOutSine }
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.activeApp !== "" ? root.activeApp : "Home"
                    font.pixelSize: 14
                    font.family: Tokens.fontDisplay
                    font.weight: Font.SemiBold
                    color: Tokens.textPrimary
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Project Minerva · Companion"
                    font.pixelSize: 9
                    font.family: Tokens.fontMono
                    color: Tokens.textDisabled
                }
            }

            // Quick button hint grid
            Grid {
                anchors.horizontalCenter: parent.horizontalCenter
                columns: 3
                spacing: 8

                Repeater {
                    model: [
                        { key: "Space", label: "Home"    },
                        { key: "X",     label: "Search"  },
                        { key: "Tab",   label: "Radial"  },
                        { key: "Z",     label: "QS"      },
                        { key: "C",     label: "Notifs"  },
                        { key: "Enter", label: "Apps"    },
                    ]
                    delegate: Rectangle {
                        width: 72; height: 26
                        radius: Tokens.rSm
                        color: Tokens.lowerSurface
                        border.color: Tokens.borderSubtle
                        border.width: 1

                        Row {
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                text: modelData.key
                                font.pixelSize: 8
                                font.family: Tokens.fontMono
                                color: Tokens.accent
                                verticalAlignment: Text.AlignVCenter
                            }
                            Text {
                                text: modelData.label
                                font.pixelSize: 8
                                font.family: Tokens.fontSans
                                color: Tokens.textDisabled
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }
            }
        }

        // Palette mode indicator
        Column {
            visible: root.paletteOpen
            anchors.centerIn: parent
            spacing: 12

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "🔍"
                font.pixelSize: 32
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Command Search"
                font.pixelSize: 13
                font.family: Tokens.fontDisplay
                color: Tokens.textPrimary
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "↑↓ navigate  ·  A select  ·  B close"
                font.pixelSize: 10
                font.family: Tokens.fontMono
                color: Tokens.textDisabled
            }
        }

        // Radial mode indicator
        Column {
            visible: root.radialOpen
            anchors.centerIn: parent
            spacing: 12

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "⊕"
                font.pixelSize: 32
                color: Tokens.accent
                SequentialAnimation on rotation {
                    loops: Animation.Infinite
                    NumberAnimation { to: 360; duration: 8000 }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Radial Menu"
                font.pixelSize: 13
                font.family: Tokens.fontDisplay
                color: Tokens.accent
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "← → ↑ ↓ navigate  ·  A activate"
                font.pixelSize: 10
                font.family: Tokens.fontMono
                color: Tokens.textDisabled
            }
        }
    }
}
