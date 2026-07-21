import QtQuick
import "."

Rectangle {
    id: root
    height: 32

    // hints: array of { key: string, label: string }
    property var hints: []

    color: "#cc07070f"

    // Top hairline
    Rectangle {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 1
        color: Tokens.borderSubtle
    }

    Row {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: Tokens.sp3 }
        spacing: 14

        Repeater {
            model: root.hints

            delegate: Row {
                spacing: 4
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    width: Math.max(26, keyLabel.implicitWidth + 8)
                    height: 17
                    radius: Tokens.rSm
                    anchors.verticalCenter: parent.verticalCenter
                    color: Tokens.bgElevated
                    border.color: Tokens.border
                    border.width: 1

                    Text {
                        id: keyLabel
                        anchors.centerIn: parent
                        text: modelData.key
                        font.pixelSize: 9
                        font.family: Tokens.fontMono
                        color: Tokens.textSecondary
                    }
                }

                Text {
                    text: modelData.label
                    font.pixelSize: 11
                    font.family: Tokens.fontSans
                    color: Tokens.textDisabled
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
