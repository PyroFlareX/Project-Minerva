import QtQuick
import "."

Rectangle {
    id: root
    height: 36

    // Inputs
    required property string timeStr
    property int    workspaceIndex: 0
    property int    workspaceCount: 3
    property string appName:        ""
    property string nowPlaying:     ""
    property bool   wifiOn:         true
    property bool   btOn:           true
    property bool   dnd:            false
    property int    notifCount:     0
    property int    batteryPct:     87

    color: "#cc07070f"

    // Bottom hairline
    Rectangle {
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: 1
        color: Tokens.borderSubtle
    }

    Row {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: Tokens.sp3 }
        spacing: Tokens.sp1

        Repeater {
            model: root.workspaceCount
            delegate: Rectangle {
                width: 6; height: 6
                radius: 3
                anchors.verticalCenter: parent.verticalCenter
                color: index === root.workspaceIndex ? Tokens.accent : Tokens.border
                Behavior on color { ColorAnimation { duration: Tokens.animFast } }
            }
        }
    }

    // App name
    Text {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 44 }
        width: 140
        text: root.appName
        font.pixelSize: 12
        font.family: Tokens.fontMono
        color: Tokens.textSecondary
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }

    // Clock (centered)
    Text {
        anchors.centerIn: parent
        text: root.timeStr
        font.pixelSize: 15
        font.family: Tokens.fontMono
        font.weight: Font.Medium
        color: Tokens.textPrimary
    }

    // Right cluster
    Row {
        anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: Tokens.sp3 }
        spacing: Tokens.sp3

        Text {
            visible: root.nowPlaying !== ""
            text: "♫ " + root.nowPlaying
            font.pixelSize: 11
            font.family: Tokens.fontMono
            color: Tokens.accent
            verticalAlignment: Text.AlignVCenter
        }
        Text {
            text: root.wifiOn ? "📶" : "📵"
            font.pixelSize: 13
            verticalAlignment: Text.AlignVCenter
        }
        Text {
            visible: root.btOn
            text: "📡"
            font.pixelSize: 13
            verticalAlignment: Text.AlignVCenter
        }
        Text {
            visible: root.dnd
            text: "🔕"
            font.pixelSize: 13
            verticalAlignment: Text.AlignVCenter
        }
        Rectangle {
            visible: root.notifCount > 0
            width: 8; height: 8; radius: 4
            anchors.verticalCenter: parent.verticalCenter
            color: Tokens.error
        }
        Text {
            text: "🔋 " + root.batteryPct + "%"
            font.pixelSize: 12
            font.family: Tokens.fontMono
            color: root.batteryPct > 20 ? Tokens.textSecondary : Tokens.error
            verticalAlignment: Text.AlignVCenter
        }
    }
}
