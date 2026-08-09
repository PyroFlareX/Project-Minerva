import QtQuick
import "."

Item {
    id: root

    property var config: ({ title: "App Switcher", cardWidth: 200, cardHeight: 140,
                            spacing: 20, apps: [] })
    property var apps: root.config.apps || []
    property int focusIndex: 0
    property bool open: false

    signal appSelected(int idx)
    signal closed()

    visible: open
    opacity: open ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: Tokens.animNormal } }

    Rectangle {
        anchors.fill: parent
        color: Tokens.bgOverlay
        MouseArea { anchors.fill: parent; onClicked: root.closed() }
    }

    Text {
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
            topMargin: 60
        }
        text: root.config.title || "App Switcher"
        font.pixelSize: 18
        font.family: Tokens.fontDisplay
        font.weight: Font.DemiBold
        color: Tokens.textSecondary
    }

    Row {
        anchors.centerIn: parent
        spacing: root.config.spacing || 20

        Repeater {
            model: root.apps

            delegate: Rectangle {
                property bool focused: index === root.focusIndex
                width: root.config.cardWidth || 200
                height: root.config.cardHeight || 140
                radius: Tokens.rLg
                color: modelData.bg
                border.color: focused ? Tokens.accent : Tokens.border
                border.width: focused ? 2 : 1
                Behavior on border.color { ColorAnimation { duration: Tokens.animFast } }

                layer.enabled: focused
                layer.effect: null

                Column {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.icon
                        font.pixelSize: 42
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.name
                        font.pixelSize: 13
                        font.family: Tokens.fontSans
                        color: Tokens.textPrimary
                    }
                }

                Rectangle {
                    anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                    height: 32
                    color: "#66000000"
                    Text {
                        anchors.centerIn: parent
                        text: focused ? "[ Launch ]" : modelData.name
                        font.pixelSize: 11
                        font.family: Tokens.fontMono
                        color: focused ? Tokens.accent : Tokens.textSecondary
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.appSelected(index)
                }
            }
        }
    }

    ControlHints {
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            bottomMargin: 40
        }
        hints: [
            {button: "D-PAD", label: "Select"},
            {button: "A", label: "Switch"},
            {button: "B", label: "Close"}
        ]
        spacing: 16
    }
}
