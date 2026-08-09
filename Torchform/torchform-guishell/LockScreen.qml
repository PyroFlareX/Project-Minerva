import QtQuick
import "."

Rectangle {
    id: root
    color: Tokens.bgBase

    required property string timeStr
    required property string dateStr
    property int pinLen: 0

    // Ambient radial wash
    Rectangle {
        anchors.fill: parent
        color: "#142a64"
        opacity: 0.18
    }

    Column {
        anchors.centerIn: parent
        spacing: 0

        // Big clock
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.timeStr
            font.pixelSize: 88
            font.family: Tokens.fontDisplay
            font.weight: Font.Bold
            color: Tokens.textPrimary
        }

        // Date
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.dateStr
            font.pixelSize: 12
            font.family: Tokens.fontMono
            color: Tokens.textSecondary
            topPadding: 4
        }

        // PIN dots
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10
            topPadding: 20

            Repeater {
                model: 4
                delegate: Rectangle {
                    width: 12; height: 12; radius: 6
                    border.width: 1
                    border.color: index < root.pinLen ? Tokens.accent : Tokens.border
                    color: index < root.pinLen ? Tokens.accent : "transparent"
                    Behavior on color { ColorAnimation { duration: Tokens.animFast } }
                    Behavior on border.color { ColorAnimation { duration: Tokens.animFast } }
                }
            }
        }

        ControlHints {
            anchors.horizontalCenter: parent.horizontalCenter
            hints: [{button: "A", label: "Unlock"}]
            y: 14
        }
    }
}
