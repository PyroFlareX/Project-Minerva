import QtQuick
import "."

// Alpine runs OpenRC with BusyBox syslog, so the sources are /var/log/messages,
// dmesg, and the Torchform session logs — there is no journalctl on this image.
Item {
    id: root

    property var    sources: []
    property int    sourceIndex: 0
    property var    lines: []
    property int    focusIndex: 0
    property bool   loading: false
    property string statusText: ""

    signal sourceRequested(int index)
    signal refreshRequested()
    signal focusRequested(int index)

    onFocusIndexChanged: {
        if (list.currentIndex !== focusIndex)
            list.currentIndex = focusIndex
        if (list.count > 0)
            list.positionViewAtIndex(focusIndex, ListView.Contain)
    }
    onLinesChanged: if (list.count > 0) list.positionViewAtIndex(root.focusIndex, ListView.Contain)

    Column {
        anchors { fill: parent; margins: Tokens.sp4 }
        spacing: Tokens.sp2

        Row {
            width: parent.width
            height: 32
            spacing: Tokens.sp3

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "LOGS"
                font.pixelSize: 16
                font.family: Tokens.fontDisplay
                font.weight: Font.DemiBold
                color: Tokens.accent
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 400
                elide: Text.ElideRight
                text: root.loading ? "Reading…" : (root.statusText || (root.lines.length + " lines"))
                font.pixelSize: 10
                font.family: Tokens.fontMono
                color: Tokens.textDisabled
            }
            Rectangle {
                width: 76; height: 26; radius: Tokens.rSm
                color: Tokens.bgElevated
                border.color: Tokens.border
                Text { anchors.centerIn: parent; text: "Refresh"; font.pixelSize: 9; font.family: Tokens.fontMono; color: Tokens.accent }
                MouseArea { anchors.fill: parent; onClicked: root.refreshRequested() }
            }
        }

        // Source tabs — L1/R1 cycle them from the shell.
        Row {
            width: parent.width
            height: 26
            spacing: Tokens.sp1
            Repeater {
                model: root.sources
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: Math.max(80, (root.width - Tokens.sp4 * 2 - Tokens.sp1 * 3) / Math.max(1, root.sources.length))
                    height: 24
                    radius: Tokens.rSm
                    color: index === root.sourceIndex ? Tokens.accentGlow : Tokens.bgSurface
                    border.color: index === root.sourceIndex ? Tokens.accent : Tokens.borderSubtle
                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        font.pixelSize: 9
                        font.family: Tokens.fontMono
                        color: index === root.sourceIndex ? Tokens.accent : Tokens.textSecondary
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.sourceRequested(index) }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Tokens.borderSubtle }

        ListView {
            id: list
            width: parent.width
            height: parent.height - 78
            clip: true
            interactive: true
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 0
            model: root.lines
            currentIndex: root.focusIndex

            delegate: Rectangle {
                required property var modelData
                required property int index
                width: list.width
                height: 18
                color: index === root.focusIndex ? Tokens.accentGlow : "transparent"
                Text {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: Tokens.sp2; rightMargin: Tokens.sp2 }
                    text: modelData
                    elide: Text.ElideRight
                    font.pixelSize: 9
                    font.family: Tokens.fontMono
                    color: index === root.focusIndex ? Tokens.textPrimary : Tokens.textSecondary
                }
                MouseArea { anchors.fill: parent; onClicked: root.focusRequested(index) }
            }

            Text {
                anchors.centerIn: parent
                visible: !root.loading && root.lines.length === 0
                text: root.statusText || "No log lines available"
                font.pixelSize: 11
                font.family: Tokens.fontMono
                color: Tokens.textDisabled
            }
        }

    }
}
