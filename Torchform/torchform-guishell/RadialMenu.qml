import QtQuick
import "."

Item {
    id: root

    // items: array of { icon, label, enabled }
    property var    items:      []
    property int    focusIndex: 0
    property string activeLayer: "system"  // app1 | app2 | system
    property bool   open:       false

    signal itemActivated(int idx)
    signal dismissed()

    visible: open
    opacity: open ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: Tokens.animNormal } }

    // Dim backdrop
    Rectangle {
        anchors.fill: parent
        color: Tokens.bgOverlay
        MouseArea { anchors.fill: parent; onClicked: root.dismissed() }
    }

    // Radial layout centre
    Item {
        id: radialCenter
        anchors.centerIn: parent
        width: (Tokens.radialRadius + Tokens.radialItemSize) * 2
        height: width

        // Layer label
        Text {
            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
            text: root.activeLayer === "system" ? "System"
                : root.activeLayer === "app1"   ? "L2"
                :                           "R2"
            font.pixelSize: 13
            font.family: Tokens.fontSans
            font.weight: Font.SemiBold
            color: root.activeLayer === "system" ? Tokens.accent : Tokens.textSecondary
        }

        // Centre ring
        Rectangle {
            anchors.centerIn: parent
            width: 48; height: 48; radius: 24
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

        // Item bubbles — computed with Math.cos/sin
        Repeater {
            model: root.items.length

            delegate: Item {
                id: bubble
                property real angle: (index / root.items.length) * 2 * Math.PI - Math.PI / 2
                property bool focused: index === root.focusIndex
                property var  entry: root.items[index]

                x: radialCenter.width / 2
                   + Tokens.radialRadius * Math.cos(angle)
                   - Tokens.radialItemSize / 2
                y: radialCenter.height / 2
                   + Tokens.radialRadius * Math.sin(angle)
                   - Tokens.radialItemSize / 2

                width: Tokens.radialItemSize
                height: Tokens.radialItemSize

                Rectangle {
                    anchors.fill: parent
                    radius: Tokens.radialItemSize / 2
                    color: bubble.focused ? Tokens.accent : Tokens.bgElevated
                    border.color: bubble.focused ? Tokens.accent
                                 : (bubble.entry.enabled ? Tokens.border : Tokens.borderSubtle)
                    border.width: 2
                    Behavior on color { ColorAnimation { duration: Tokens.animFast } }

                    // Glow when focused
                    layer.enabled: bubble.focused
                    layer.effect: null

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
                            width: Tokens.radialItemSize - 4
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
