import QtQuick
import "."

Item {
    id: root

    property bool open: false
    property var config: ({ side: "left", width: 300, title: "Notifications",
                            closeGlyph: "‹", items: [] })
    property int focusIndex: -1
    property bool suppressed: false
    property int notifCount: root.suppressed ? 0 : (root.config.items || []).length

    signal closed()
    signal itemActivated(int index)

    visible: open
    opacity: open ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: Tokens.animNormal } }

    MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: root.closed()
    }

    Rectangle {
        id: panel
        anchors {
            top: parent.top
            bottom: parent.bottom
        }
        width: root.config.width || 300
        x: root.open
           ? (root.config.side === "right" ? parent.width - width : 0)
           : (root.config.side === "right" ? parent.width : -width)
        color: Tokens.bgSurface
        border.color: Tokens.border
        border.width: 1

        Behavior on x { NumberAnimation { duration: Tokens.animNormal; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: root.config.side === "right" ? parent.left : undefined
                right: root.config.side === "right" ? undefined : parent.right
            }
            width: 2
            color: Tokens.primary
        }

        Column {
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                topMargin: 16
            }
            leftPadding: 16
            rightPadding: 16
            spacing: 8

            Row {
                spacing: 8
                Text {
                    text: root.config.title || "Notifications"
                    font.pixelSize: 15
                    font.family: Tokens.fontDisplay
                    font.weight: Font.DemiBold
                    color: Tokens.textPrimary
                    bottomPadding: 14
                }
                Rectangle {
                    visible: root.notifCount > 0
                    width: 18
                    height: 18
                    radius: 9
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
                model: root.suppressed ? [] : (root.config.items || [])

                delegate: Rectangle {
                    width: parent.width - 32
                    height: 70
                    radius: Tokens.rMd
                    color: Tokens.bgElevated
                    border.color: root.focusIndex === index ? Tokens.accent : Tokens.borderSubtle
                    border.width: root.focusIndex === index ? 2 : 1

                    Row {
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: 12
                        }
                        spacing: 10

                        Text {
                            text: modelData.icon
                            font.pixelSize: 22
                            anchors.verticalCenter: parent.verticalCenter
                        }

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

                    Rectangle {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                        height: 1
                        color: Tokens.borderSubtle
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.itemActivated(index)
                    }
                }
            }

            Text {
                visible: root.suppressed || (root.config.items || []).length === 0
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.suppressed ? "Do Not Disturb enabled" : "No notifications"
                font.pixelSize: 12
                font.family: Tokens.fontMono
                color: Tokens.textDisabled
                topPadding: 20
            }
        }

        Rectangle {
            anchors {
                verticalCenter: parent.verticalCenter
                left: root.config.side === "right" ? parent.right : undefined
                right: root.config.side === "right" ? undefined : parent.left
            }
            width: 20
            height: 60
            color: Tokens.bgElevated
            border.color: Tokens.border
            border.width: 1
            radius: 4
            Text {
                anchors.centerIn: parent
                text: root.config.closeGlyph || "‹"
                font.pixelSize: 14
                color: Tokens.textSecondary
            }
            MouseArea { anchors.fill: parent; onClicked: root.closed() }
        }
    }
}
