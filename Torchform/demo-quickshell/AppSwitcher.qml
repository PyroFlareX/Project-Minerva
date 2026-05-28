import QtQuick
import "."

Item {
    id: root

    // apps: array of { name, icon, bg }
    property var apps:       []
    property int focusIndex: 0
    property bool open:      false

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

    // Header label
    Text {
        anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 60 }
        text: "App Switcher"
        font.pixelSize: 18
        font.family: Tokens.fontDisplay
        font.weight: Font.SemiBold
        color: Tokens.textSecondary
    }

    // Card row
    Row {
        anchors.centerIn: parent
        spacing: 20

        Repeater {
            model: root.apps

            delegate: Rectangle {
                property bool focused: index === root.focusIndex
                width: 200; height: 140
                radius: Tokens.rLg
                color: modelData.bg
                border.color: focused ? Tokens.accent : Tokens.border
                border.width: focused ? 2 : 1
                Behavior on border.color { ColorAnimation { duration: Tokens.animFast } }

                // Drop shadow glow
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

                // Bottom title bar
                Rectangle {
                    anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                    height: 32
                    radius: 0
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

    // Hint
    Text {
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 40 }
        text: "← → Navigate   A Launch   B Close"
        font.pixelSize: 11
        font.family: Tokens.fontMono
        color: Tokens.textDisabled
    }
}
