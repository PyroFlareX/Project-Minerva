import QtQuick
import "."

Row {
    id: root

    property var hints: []


    Repeater {
        model: root.hints

        delegate: Row {
            spacing: 4
            anchors.verticalCenter: parent.verticalCenter

            GamepadGlyph {
                button: modelData.button || modelData.key || "A"
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: modelData.label || ""
                font.pixelSize: 9
                font.family: Tokens.fontSans
                color: Tokens.textDisabled
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
