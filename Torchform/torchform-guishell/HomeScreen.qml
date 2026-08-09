import QtQuick
import "."

Rectangle {
    id: root
    color: Tokens.bgBase

    // gridApps / dockApps: array of { name, icon, bg, idx, running? }
    property var gridApps: []
    property var dockApps: []
    property int homeFocus: 0

    signal tileActivated(int idx)

    // Ambient radial wash
    Rectangle {
        anchors.fill: parent
        color: "#112a64"
        opacity: 0.18
    }

    Column {
        anchors.fill: parent
        anchors.topMargin: Tokens.sp3
        anchors.bottomMargin: Tokens.sp3
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        spacing: 10

        // Search bar
        Rectangle {
            width: parent.width
            height: 30
            radius: 15
            color: Tokens.bgSurface
            border.color: Tokens.border
            border.width: 1

            Row {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 14 }
                spacing: 8

                Text { text: "🔍"; font.pixelSize: 11; verticalAlignment: Text.AlignVCenter }
                Text {
                    text: "Search apps, files, settings…"
                    font.pixelSize: 11
                    font.family: Tokens.fontMono
                    color: Tokens.textDisabled
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 14 }
                spacing: 4
                GamepadGlyph {
                    button: "X"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "Palette"
                    font.pixelSize: 9
                    font.family: Tokens.fontSans
                    color: Tokens.textDisabled
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // App grid (4 columns)
        Item {
            width: parent.width
            height: 250

            property real gap: 12
            property real cellW: (width - 3 * gap) / 4
            property real cellH: 115

            Repeater {
                model: root.gridApps
                delegate: Rectangle {
                    property bool focused: modelData.idx === root.homeFocus
                    x: (modelData.idx % 4) * (parent.cellW + parent.gap)
                    y: Math.floor(modelData.idx / 4) * (parent.cellH + parent.gap)
                    width: parent.cellW
                    height: parent.cellH
                    radius: Tokens.rMd
                    color: "transparent"
                    border.color: focused ? Tokens.accent : "transparent"
                    border.width: focused ? 1 : 0
                    Behavior on border.color { ColorAnimation { duration: Tokens.animFast } }

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: parent.focused ? Tokens.accentGlow : "transparent"
                        Behavior on color { ColorAnimation { duration: Tokens.animFast } }
                    }

                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 8
                        spacing: 5

                        Rectangle {
                            width: 48; height: 48
                            radius: 12
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: modelData.bg
                            border.color: "#ffffff10"
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: modelData.icon
                                font.pixelSize: 22
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.name
                            font.pixelSize: 9
                            font.family: Tokens.fontSans
                            color: Tokens.textSecondary
                            elide: Text.ElideRight
                            width: parent.parent.width - 8
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.tileActivated(modelData.idx)
                    }
                }
            }
        }

        // Dock
        Item {
            width: parent.width
            height: 72

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                height: 72
                width: dockRow.implicitWidth + 24
                radius: 20
                color: '#bd7a16'
                border.color: Tokens.border
                border.width: 1

                Row {
                    id: dockRow
                    anchors.centerIn: parent
                    spacing: 12

                    Repeater {
                        model: root.dockApps
                        delegate: Rectangle {
                            property bool focused: modelData.idx === root.homeFocus
                            width: 56; height: 56
                            radius: 12
                            color: focused ? Tokens.accentGlow : modelData.bg
                            border.color: focused ? Tokens.accent
                                        : (modelData.running ?? false) ? Tokens.success
                                        : "transparent"
                            border.width: (focused || (modelData.running ?? false)) ? 1 : 0
                            Behavior on color { ColorAnimation { duration: Tokens.animFast } }
                            Behavior on border.color { ColorAnimation { duration: Tokens.animFast } }

                            Text {
                                anchors.centerIn: parent
                                text: modelData.icon
                                font.pixelSize: 24
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.tileActivated(modelData.idx)
                            }
                        }
                    }
                }
            }
        }
    }
}
