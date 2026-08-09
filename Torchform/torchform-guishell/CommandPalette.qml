import QtQuick
import "."

Item {
    id: root

    // commands: array of { id, label, category, icon, shortcut }
    property var    commands:   []
    property string query:      ""
    property int    focusIndex: 0
    property bool   open:       false

    signal commandSelected(int idx)
    signal closed()

    visible: open
    opacity: open ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: Tokens.animNormal } }

    // Backdrop
    Rectangle {
        anchors.fill: parent
        color: Tokens.bgOverlay
        MouseArea { anchors.fill: parent; onClicked: root.closed() }
    }

    // Panel
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 80
        width: Math.min(parent.width - 120, 700)
        height: Math.min(panelCol.implicitHeight + 2, 480)
        radius: Tokens.rLg
        color: Tokens.bgSurface
        border.color: Tokens.border
        border.width: 1

        // Thin accent top bar
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 2
            radius: Tokens.rLg
            color: Tokens.accent
        }

        Column {
            id: panelCol
            anchors { top: parent.top; left: parent.left; right: parent.right }
            topPadding: 2

            // Search row
            Rectangle {
                width: parent.width
                height: 50
                color: "transparent"
                border.color: Tokens.borderSubtle
                border.width: 0

                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 16 }
                    spacing: 10

                    Text {
                        text: "🔍"
                        font.pixelSize: 15
                        verticalAlignment: Text.AlignVCenter
                    }
                    Text {
                        text: root.query === "" ? "Search commands…" : root.query
                        font.pixelSize: 14
                        font.family: Tokens.fontMono
                        color: root.query === "" ? Tokens.textDisabled : Tokens.textPrimary
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                // Separator
                Rectangle {
                    anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                    height: 1
                    color: Tokens.borderSubtle
                }
            }

            // Results scroll with controller focus when the command registry exceeds the panel.
            Flickable {
                id: resultsViewport
                width: parent.width
                height: Math.min(430, Math.max(0, root.commands.length * 52))
                contentWidth: width
                contentHeight: resultsColumn.implicitHeight
                clip: true

                function ensureFocusVisible() {
                    var top = root.focusIndex * 52
                    var bottom = top + 52
                    if (top < contentY)
                        contentY = top
                    else if (bottom > contentY + height)
                        contentY = bottom - height
                }

                Connections {
                    target: root
                    function onFocusIndexChanged() {
                        resultsViewport.ensureFocusVisible()
                    }
                }

                Column {
                    id: resultsColumn
                    width: resultsViewport.width

                    Repeater {
                        model: root.commands

                        delegate: Rectangle {
                            property bool focused: index === root.focusIndex
                            width: parent.width
                            height: 52
                            color: focused ? Qt.rgba(
                                parseInt(Tokens.accent.toString().slice(1,3), 16)/255,
                                parseInt(Tokens.accent.toString().slice(3,5), 16)/255,
                                parseInt(Tokens.accent.toString().slice(5,7), 16)/255,
                                0.13) : "transparent"
                            Behavior on color { ColorAnimation { duration: Tokens.animFast } }

                            Rectangle {
                                visible: parent.focused
                                width: 3
                                height: parent.height - 12
                                anchors.verticalCenter: parent.verticalCenter
                                x: 0
                                radius: 2
                                color: Tokens.accent
                            }

                            Row {
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 16 }
                                spacing: 12

                                Rectangle {
                                    width: 32; height: 32; radius: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Tokens.bgElevated
                                    Text { anchors.centerIn: parent; text: modelData.icon; font.pixelSize: 16 }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    Text {
                                        text: modelData.label
                                        font.pixelSize: 13
                                        font.family: Tokens.fontSans
                                        color: Tokens.textPrimary
                                    }
                                    Text {
                                        text: modelData.category
                                        font.pixelSize: 10
                                        font.family: Tokens.fontMono
                                        color: Tokens.textDisabled
                                    }
                                }
                            }

                            GamepadGlyph {
                                visible: modelData.shortcut !== ""
                                button: modelData.shortcut
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 16 }
                            }

                            Rectangle {
                                anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: 16; rightMargin: 16 }
                                height: 1
                                color: Tokens.borderSubtle
                                visible: index < root.commands.length - 1
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.commandSelected(index)
                            }
                        }
                    }
                }
            }
        }
    }
}
