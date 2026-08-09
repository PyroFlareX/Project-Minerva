import QtQuick
import "."

Item {
    id: root

    property var config: ({ title: "System", radius: 170, itemSize: 92, items: [] })
    property var items: root.config.items || []
    property int focusIndex: 0
    property string activeLayer: "system"  // app1 | app2 | system
    property bool open: false

    signal itemActivated(int idx)
    signal dismissed()

    visible: open
    opacity: open ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: Tokens.animNormal } }

    Rectangle {
        anchors.fill: parent
        color: Tokens.bgOverlay
        MouseArea { anchors.fill: parent; onClicked: root.dismissed() }
    }

    Item {
        id: radialCenter
        anchors.centerIn: parent
        width: (root.config.radius + root.config.itemSize) * 2
        height: width

        Text {
            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
            text: root.config.title || (root.activeLayer === "system" ? "System" : root.activeLayer)
            font.pixelSize: 13
            font.family: Tokens.fontSans
            font.weight: Font.DemiBold
            color: root.activeLayer === "system" ? Tokens.accent : Tokens.textSecondary
        }

        Rectangle {
            anchors.centerIn: parent
            width: 48
            height: 48
            radius: 24
            color: Tokens.bgElevated
            border.color: root.activeLayer === "system" ? Tokens.accent : Tokens.border
            border.width: 2
            Text {
                anchors.centerIn: parent
                text: root.activeLayer === "system" ? "⊕" : "◉"
                font.pixelSize: 18
                color: root.activeLayer === "system" ? Tokens.accent : Tokens.textSecondary
            }
        }

        Repeater {
            model: root.items

            delegate: Item {
                id: bubble
                property real angle: (index / Math.max(1, root.items.length)) * 2 * Math.PI - Math.PI / 2
                property bool focused: index === root.focusIndex
                property var entry: modelData

                x: radialCenter.width / 2
                   + root.config.radius * Math.cos(angle)
                   - root.config.itemSize / 2
                y: radialCenter.height / 2
                   + root.config.radius * Math.sin(angle)
                   - root.config.itemSize / 2
                width: root.config.itemSize
                height: root.config.itemSize

                Rectangle {
                    anchors.fill: parent
                    radius: root.config.itemSize / 2
                    color: bubble.focused ? Tokens.accent : Tokens.bgElevated
                    border.color: bubble.focused ? Tokens.accent
                                 : (bubble.entry.enabled ? Tokens.border : Tokens.borderSubtle)
                    border.width: bubble.focused ? 3 : 2
                    Behavior on color { ColorAnimation { duration: Tokens.animFast } }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: bubble.entry.icon
                            font.pixelSize: 22
                            color: bubble.focused ? Tokens.textOnAccent : Tokens.textPrimary
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: bubble.entry.label
                            font.pixelSize: 9
                            font.family: Tokens.fontSans
                            color: bubble.focused ? Tokens.textOnAccent : Tokens.textSecondary
                            width: root.config.itemSize - 4
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.itemActivated(index)
                    }
                }
            }
        }
    }
}
