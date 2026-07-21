import QtQuick
import "."

Item {
    id: root
    property bool open:       false
    property int  notifCount: 0

    signal closed()

    // Slide in from left
    Rectangle {
        id: panel
        anchors { top: parent.top; bottom: parent.bottom }
        width: 300
        x: root.open ? 0 : -width
        color: Tokens.bgSurface
        border.color: Tokens.border
        border.width: 1

        Behavior on x { NumberAnimation { duration: Tokens.animNormal; easing.type: Easing.OutCubic } }

        // Accent strip (right side)
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

            Row {
                spacing: 8
                Text {
                    text: "Notifications"
                    font.pixelSize: 15
                    font.family: Tokens.fontDisplay
                    font.weight: Font.SemiBold
                    color: Tokens.textPrimary
                    bottomPadding: 14
                }
                Rectangle {
                    visible: root.notifCount > 0
                    width: 18; height: 18; radius: 9
                    color: Tokens.error
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        anchors.centerIn: parent
                        text: root.notifCount
                        font.pixelSize: 9
                        color: "white"
                    }
                }
            }

            Repeater {
                model: notifItems

                delegate: Rectangle {
                    width: parent.width - 32
                    height: 70
                    radius: Tokens.rMd
                    color: Tokens.bgElevated
                    border.color: Tokens.borderSubtle
                    border.width: 1

                    Row {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 12 }
                        spacing: 10

                        Text { text: modelData.icon; font.pixelSize: 22; anchors.verticalCenter: parent.verticalCenter }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            Row {
                                spacing: 6
                                Text {
                                    text: modelData.app
                                    font.pixelSize: 10
                                    font.family: Tokens.fontMono
                                    color: Tokens.accent
                                }
                                Text {
                                    text: modelData.time
                                    font.pixelSize: 10
                                    font.family: Tokens.fontMono
                                    color: Tokens.textDisabled
                                }
                            }
                            Text {
                                text: modelData.title
                                font.pixelSize: 12
                                font.family: Tokens.fontSans
                                color: Tokens.textPrimary
                            }
                            Text {
                                text: modelData.body
                                font.pixelSize: 10
                                font.family: Tokens.fontSans
                                color: Tokens.textSecondary
                                elide: Text.ElideRight
                                width: 200
                            }
                        }
                    }

                    // Bottom divider
                    Rectangle {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                        height: 1; color: Tokens.borderSubtle
                    }
                }
            }

            // Empty state
            Text {
                visible: notifItems.length === 0
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No notifications"
                font.pixelSize: 12
                font.family: Tokens.fontMono
                color: Tokens.textDisabled
                topPadding: 20
            }
        }

        // Close handle
        Rectangle {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: 20; height: 60
            color: Tokens.bgElevated
            border.color: Tokens.border
            border.width: 1
            radius: 4
            Text {
                anchors.centerIn: parent
                text: "‹"
                font.pixelSize: 14
                color: Tokens.textSecondary
            }
            MouseArea { anchors.fill: parent; onClicked: root.closed() }
        }
    }

    MouseArea {
        anchors { left: panel.right; top: parent.top; bottom: parent.bottom; right: parent.right }
        enabled: root.open
        onClicked: root.closed()
    }

    property var notifItems: [
        { icon: "📧", app: "Email",   time: "2m ago", title: "New message from Alice",   body: "Hey, did you see the latest Minerva prototype?" },
        { icon: "⚙️", app: "System",  time: "5m ago", title: "Update available",         body: "torchform-shell 0.9.2 is ready to install."    },
    ]
}
