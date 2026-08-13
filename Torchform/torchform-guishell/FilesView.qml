import QtQuick
import "."

Item {
    id: root

    property string path: "~"
    property var entries: []
    property int focusIndex: 0
    property bool loading: false
    property string statusText: ""

    signal entryActivated(int index)
    signal focusRequested(int index)
    signal parentRequested()
    signal refreshRequested()
    signal bookmarkRequested(string path)

    function entryIcon(kind) {
        if (kind === "dir") return "▣"
        if (kind === "link") return "↗"
        return "□"
    }

    onEntriesChanged: {
        var clamped = Math.max(0, Math.min(focusIndex, Math.max(0, entries.length - 1)))
        if (clamped !== focusIndex)
            focusRequested(clamped)
    }
    onFocusIndexChanged: {
        if (list.currentIndex !== focusIndex)
            list.currentIndex = focusIndex
        if (list.count > 0)
            list.positionViewAtIndex(focusIndex, ListView.Contain)
    }

    Column {
        anchors.fill: parent
        anchors.margins: Tokens.sp4
        spacing: Tokens.sp2

        Row {
            width: parent.width
            height: 34
            spacing: Tokens.sp2

            Rectangle {
                width: 38; height: 30; radius: Tokens.rSm
                color: Tokens.bgElevated
                border.color: Tokens.border
                Text { anchors.centerIn: parent; text: "‹"; font.pixelSize: 18; color: Tokens.accent }
                MouseArea { anchors.fill: parent; onClicked: root.parentRequested() }
            }

            Column {
                width: parent.width - 112
                height: parent.height
                Text {
                    width: parent.width
                    text: "FILES"
                    font.pixelSize: 15
                    font.family: Tokens.fontDisplay
                    color: Tokens.textPrimary
                }
                Text {
                    width: parent.width
                    text: root.path
                    elide: Text.ElideMiddle
                    font.pixelSize: 10
                    font.family: Tokens.fontMono
                    color: Tokens.textDisabled
                }
            }

            Rectangle {
                width: 62; height: 30; radius: Tokens.rSm
                color: Tokens.bgElevated
                border.color: Tokens.border
                Text { anchors.centerIn: parent; text: root.loading ? "…" : "Refresh"; font.pixelSize: 9; font.family: Tokens.fontMono; color: Tokens.accent }
                MouseArea { anchors.fill: parent; onClicked: root.refreshRequested() }
            }
        }

        Row {
            width: parent.width
            height: 28
            spacing: Tokens.sp1
            Repeater {
                model: ["~", "~/Downloads", "~/Documents", "/tmp"]
                delegate: Rectangle {
                    width: Math.max(60, (parent.width - 3 * Tokens.sp1) / 4)
                    height: 26
                    radius: Tokens.rSm
                    color: Tokens.bgSurface
                    border.color: Tokens.borderSubtle
                    Text { anchors.centerIn: parent; text: modelData; font.pixelSize: 8; font.family: Tokens.fontMono; color: Tokens.textSecondary; elide: Text.ElideMiddle }
                    MouseArea { anchors.fill: parent; onClicked: root.bookmarkRequested(modelData) }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Tokens.borderSubtle
        }

        ListView {
            id: list
            width: parent.width
            height: parent.height - 104
            clip: true
            focus: true

            interactive: true
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 0

            model: root.entries
            spacing: Tokens.sp1
            currentIndex: root.focusIndex

            delegate: Rectangle {
                width: list.width
                height: 46
                radius: Tokens.rSm
                color: index === root.focusIndex ? Tokens.accentGlow : Tokens.bgSurface
                border.color: index === root.focusIndex ? Tokens.accent : Tokens.borderSubtle
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.sp3
                    anchors.rightMargin: Tokens.sp3
                    spacing: Tokens.sp2
                    Text {
                        width: 24
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.entryIcon(modelData.kind)
                        font.pixelSize: 16
                        color: modelData.kind === "dir" ? Tokens.accent : Tokens.textSecondary
                    }
                    Column {
                        width: parent.width - 100
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            width: parent.width
                            text: modelData.name
                            elide: Text.ElideRight
                            font.pixelSize: 11
                            font.family: Tokens.fontSans
                            color: Tokens.textPrimary
                        }
                        Text {
                            width: parent.width
                            text: modelData.kind + (modelData.size ? "  " + modelData.size : "")
                            font.pixelSize: 8
                            font.family: Tokens.fontMono
                            color: Tokens.textDisabled
                        }
                    }
                    Text {
                        width: 58
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: modelData.kind === "dir" ? "OPEN" : "VIEW"
                        font.pixelSize: 8
                        font.family: Tokens.fontMono
                        color: index === root.focusIndex ? Tokens.accent : Tokens.textDisabled
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onPressed: root.focusRequested(index)
                    onClicked: root.entryActivated(index)
                }
            }

            Text {
                anchors.centerIn: parent
                visible: root.loading || root.entries.length === 0
                text: root.loading ? "Reading directory…" : (root.statusText || "Directory is empty")
                font.pixelSize: 11
                font.family: Tokens.fontMono
                color: Tokens.textDisabled
            }
        }

        ControlHints {
            width: parent.width
            hints: [
                {button: "D-PAD", label: "Choose"},
                {button: "A", label: "Open"},
                {button: "B", label: "Parent"}
            ]
        }
    }
}
