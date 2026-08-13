import QtQuick
import "."

// Power/session overlay. Content and geometry come from data.js so the menu can
// change without recompiling QML. Destructive entries require a confirm step.
Item {
    id: root

    property var  config: ({ title: "Power", width: 360, items: [] })
    property var  items: root.config.items || []
    property int  focusIndex: 0
    property bool open: false
    property bool confirming: false

    signal itemActivated(int index)
    signal dismissed()

    visible: opacity > 0
    opacity: open ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: Tokens.animNormal } }

    Rectangle {
        anchors.fill: parent
        color: Tokens.bgOverlay
        MouseArea { anchors.fill: parent; onClicked: root.dismissed() }
    }

    Rectangle {
        anchors.centerIn: parent
        width: root.config.width || 360
        height: card.implicitHeight + Tokens.sp4 * 2
        radius: Tokens.rLg
        color: Tokens.bgSurface
        border.color: Tokens.border
        border.width: 1

        Column {
            id: card
            anchors { fill: parent; margins: Tokens.sp4 }
            spacing: Tokens.sp2

            Text {
                text: root.config.title || "Power"
                font.pixelSize: 15
                font.family: Tokens.fontDisplay
                font.weight: Font.DemiBold
                color: Tokens.textPrimary
            }
            Text {
                width: parent.width
                text: root.confirming
                      ? "Press A again to confirm"
                      : "D-pad to choose · A to select · B to close"
                font.pixelSize: 9
                font.family: Tokens.fontMono
                color: root.confirming ? Tokens.accent : Tokens.textDisabled
            }

            Repeater {
                model: root.items
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: card.width
                    height: 44
                    radius: Tokens.rSm
                    color: index === root.focusIndex ? Tokens.accentGlow : Tokens.bgElevated
                    border.color: index === root.focusIndex ? Tokens.accent : Tokens.borderSubtle
                    border.width: 1

                    Row {
                        anchors { fill: parent; leftMargin: Tokens.sp3; rightMargin: Tokens.sp3 }
                        spacing: Tokens.sp3
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26
                            text: modelData.icon
                            font.pixelSize: 15
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 60
                            Text {
                                text: modelData.label
                                font.pixelSize: 12
                                font.family: Tokens.fontSans
                                color: Tokens.textPrimary
                            }
                            Text {
                                width: parent.width
                                text: (root.confirming && index === root.focusIndex && modelData.confirm)
                                      ? "Confirm: " + modelData.description
                                      : modelData.description
                                elide: Text.ElideRight
                                font.pixelSize: 8
                                font.family: Tokens.fontMono
                                color: (root.confirming && index === root.focusIndex && modelData.confirm)
                                       ? Tokens.accent : Tokens.textDisabled
                            }
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.itemActivated(index) }
                }
            }
        }
    }
}
