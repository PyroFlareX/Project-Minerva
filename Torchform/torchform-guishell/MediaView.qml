import QtQuick
import "."

Rectangle {
    id: root
    color: Tokens.bgBase

    property int focusIndex: 0
    signal actionRequested(string action)

    readonly property var actions: [
        { action: "browser", label: "Web Browser", detail: "Chromium over Wayland", icon: "WEB" },
        { action: "files", label: "Choose Media File", detail: "Open Files and select a file", icon: "FILE" },
        { action: "video", label: "Videos / Shows / Movies", detail: "mpv handles video and audio", icon: "VID" },
        { action: "image", label: "Pictures", detail: "imv handles raster and SVG images", icon: "IMG" },
        { action: "ebook", label: "Books / PDFs", detail: "KOReader handles ebooks and documents", icon: "BOOK" }
    ]

    Column {
        anchors { fill: parent; margins: Tokens.sp4 }
        spacing: Tokens.sp3

        Text {
            text: "MEDIA CENTER"
            color: Tokens.accent
            font.family: Tokens.fontDisplay
            font.pixelSize: 18
            font.weight: Font.DemiBold
        }
        Text {
            text: "Choose a player, or open Files to select content."
            color: Tokens.textSecondary
            font.family: Tokens.fontSans
            font.pixelSize: 11
            wrapMode: Text.WordWrap
            width: parent.width
        }

        Column {
            width: parent.width
            spacing: Tokens.sp2
            Repeater {
                model: root.actions
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: 52
                    radius: Tokens.rSm
                    color: index === root.focusIndex ? Tokens.bgElevated : Tokens.bgSurface
                    border.color: index === root.focusIndex ? Tokens.accent : Tokens.borderSubtle
                    border.width: index === root.focusIndex ? 2 : 1

                    Row {
                        anchors { fill: parent; leftMargin: Tokens.sp3; rightMargin: Tokens.sp3 }
                        spacing: Tokens.sp3
                        Text {
                            width: 40
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.icon
                            color: index === root.focusIndex ? Tokens.accent : Tokens.textSecondary
                            font.family: Tokens.fontMono
                            font.pixelSize: 10
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                text: modelData.label
                                color: Tokens.textPrimary
                                font.family: Tokens.fontSans
                                font.pixelSize: 13
                            }
                            Text {
                                text: modelData.detail
                                color: Tokens.textSecondary
                                font.family: Tokens.fontMono
                                font.pixelSize: 9
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.actionRequested(modelData.action)
                    }
                }
            }
        }

        Text {
            width: parent.width
            text: "A Select    B Home    D-pad Navigate"
            color: Tokens.textDisabled
            font.family: Tokens.fontMono
            font.pixelSize: 9
        }
    }
}
