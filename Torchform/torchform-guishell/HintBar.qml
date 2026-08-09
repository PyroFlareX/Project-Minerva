import QtQuick
import "."

Rectangle {
    id: root
    height: 32

    // hints: array of { button: string, label: string }
    property var hints: []

    color: "#cc07070f"

    // Top hairline
    Rectangle {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 1
        color: Tokens.borderSubtle
    }

    ControlHints {
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
            leftMargin: Tokens.sp3
        }
        hints: root.hints
        spacing: 14
    }
}
