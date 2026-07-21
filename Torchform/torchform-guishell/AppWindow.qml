import QtQuick
import "."

Rectangle {
    id: root
    color: Tokens.bgBase

    property string appName: "Terminal"
    property string appIcon: "⬛"
    property string appBg:   "#0d1117"

    // Title bar
    Rectangle {
        id: titleBar
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 40
        color: Tokens.bgSurface
        border.color: Tokens.borderSubtle
        border.width: 1

        Row {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 12 }
            spacing: 8

            Rectangle {
                width: 24; height: 24; radius: 6
                color: root.appBg
                anchors.verticalCenter: parent.verticalCenter
                Text { anchors.centerIn: parent; text: root.appIcon; font.pixelSize: 14 }
            }
            Text {
                text: root.appName
                font.pixelSize: 14
                font.family: Tokens.fontDisplay
                font.weight: Font.SemiBold
                color: Tokens.textPrimary
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 12 }
            spacing: 12

            Text { text: "⌂"; font.pixelSize: 14; color: Tokens.textSecondary }
            Text { text: "⧉"; font.pixelSize: 14; color: Tokens.textSecondary }
        }
    }

    // App content area — fake terminal
    Rectangle {
        anchors {
            top: titleBar.bottom; bottom: parent.bottom
            left: parent.left; right: parent.right
        }
        color: root.appBg

        Column {
            anchors { top: parent.top; left: parent.left; topMargin: 12; leftMargin: 16 }
            spacing: 3

            Repeater {
                model: termLines
                delegate: Text {
                    text: modelData
                    font.pixelSize: 12
                    font.family: Tokens.fontMono
                    color: index === termLines.length - 1 ? Tokens.accent : Tokens.textSecondary
                }
            }

            // Blinking cursor
            Row {
                spacing: 0
                Text {
                    text: "torchform@minerva:~$ "
                    font.pixelSize: 12
                    font.family: Tokens.fontMono
                    color: Tokens.success
                }
                Rectangle {
                    width: 8; height: 14
                    color: Tokens.textPrimary
                    anchors.verticalCenter: parent.verticalCenter
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        NumberAnimation { to: 0; duration: 500 }
                        NumberAnimation { to: 1; duration: 500 }
                    }
                }
            }
        }
    }

    property var termLines: [
        "Torchform OS — " + root.appName + " v1.0",
        "Type 'help' for available commands.",
        "",
        "torchform@minerva:~$ uname -a",
        "Linux minerva 6.6.0-rpi #1 SMP PREEMPT aarch64 GNU/Linux",
        "torchform@minerva:~$ neofetch --off",
        "OS: Torchform OS (Alpine Linux aarch64)",
        "Host: Project Minerva (Prototype)",
        "Kernel: 6.6.0-rpi",
        "Shell: torchform-shell (Slint + Smithay)",
        "WM: torchform-compositor",
        "Resolution: 1920x1080, 640x480",
        "CPU: Raspberry Pi CM5 @ 2.4GHz",
        "",
    ]
}
