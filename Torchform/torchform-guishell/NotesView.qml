import QtQuick
import "."

// Notes are plain Markdown files under ~/.local/share/torchform/notes.
// The shell owns all state; this component only renders and reports intent.
Item {
    id: root

    property var    notes: []
    property int    focusIndex: 0
    property bool   editing: false
    property string body: ""
    property string title: ""
    property string statusText: ""
    property bool   loading: false

    signal focusRequested(int index)
    signal noteActivated(int index)
    signal createRequested()
    signal deleteRequested(int index)
    signal editRequested()

    onFocusIndexChanged: {
        if (list.currentIndex !== focusIndex)
            list.currentIndex = focusIndex
        if (list.count > 0)
            list.positionViewAtIndex(focusIndex, ListView.Contain)
    }

    Column {
        anchors { fill: parent; margins: Tokens.sp4 }
        spacing: Tokens.sp2

        Row {
            width: parent.width
            height: 32
            spacing: Tokens.sp3

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "NOTES"
                font.pixelSize: 16
                font.family: Tokens.fontDisplay
                font.weight: Font.DemiBold
                color: Tokens.accent
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 320
                elide: Text.ElideMiddle
                text: root.editing
                      ? root.title
                      : (root.loading ? "Reading notes…"
                                      : root.notes.length + " note" + (root.notes.length === 1 ? "" : "s"))
                font.pixelSize: 10
                font.family: Tokens.fontMono
                color: Tokens.textDisabled
            }
            Rectangle {
                width: 72; height: 26; radius: Tokens.rSm
                color: Tokens.bgElevated
                border.color: Tokens.border
                Text { anchors.centerIn: parent; text: "New"; font.pixelSize: 9; font.family: Tokens.fontMono; color: Tokens.accent }
                MouseArea { anchors.fill: parent; onClicked: root.createRequested() }
            }
            Rectangle {
                width: 72; height: 26; radius: Tokens.rSm
                color: Tokens.bgElevated
                border.color: Tokens.border
                Text { anchors.centerIn: parent; text: root.editing ? "Type" : "Delete"; font.pixelSize: 9; font.family: Tokens.fontMono; color: Tokens.accent }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.editing ? root.editRequested() : root.deleteRequested(root.focusIndex)
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Tokens.borderSubtle }

        // ── List mode ────────────────────────────────────────────────────────
        ListView {
            id: list
            visible: !root.editing
            width: parent.width
            height: parent.height - 52
            clip: true
            interactive: true
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 0
            spacing: Tokens.sp1
            model: root.notes
            currentIndex: root.focusIndex

            delegate: Rectangle {
                required property var modelData
                required property int index
                width: list.width
                height: 44
                radius: Tokens.rSm
                color: index === root.focusIndex ? Tokens.accentGlow : Tokens.bgSurface
                border.color: index === root.focusIndex ? Tokens.accent : Tokens.borderSubtle
                border.width: 1

                Row {
                    anchors { fill: parent; leftMargin: Tokens.sp3; rightMargin: Tokens.sp3 }
                    spacing: Tokens.sp3
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20
                        text: "▤"
                        font.pixelSize: 14
                        color: index === root.focusIndex ? Tokens.accent : Tokens.textSecondary
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 140
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
                            text: modelData.modified + "  ·  " + modelData.size + " B"
                            font.pixelSize: 8
                            font.family: Tokens.fontMono
                            color: Tokens.textDisabled
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 56
                        horizontalAlignment: Text.AlignRight
                        text: "OPEN"
                        font.pixelSize: 8
                        font.family: Tokens.fontMono
                        color: index === root.focusIndex ? Tokens.accent : Tokens.textDisabled
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onPressed: root.focusRequested(index)
                    onClicked: root.noteActivated(index)
                }
            }

            Text {
                anchors.centerIn: parent
                visible: !root.loading && root.notes.length === 0
                text: root.statusText || "No notes yet — press X to create one"
                font.pixelSize: 11
                font.family: Tokens.fontMono
                color: Tokens.textDisabled
            }
        }

        // ── Editor mode ──────────────────────────────────────────────────────
        Rectangle {
            visible: root.editing
            width: parent.width
            height: parent.height - 52
            radius: Tokens.rSm
            color: Tokens.bgSurface
            border.color: Tokens.accent
            border.width: 1

            Flickable {
                anchors { fill: parent; margins: Tokens.sp3 }
                contentHeight: bodyText.implicitHeight
                clip: true
                Text {
                    id: bodyText
                    width: parent.width
                    text: root.body.length > 0 ? root.body + "▌" : "▌"
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    font.pixelSize: 12
                    font.family: Tokens.fontMono
                    color: Tokens.textPrimary
                }
            }
            MouseArea { anchors.fill: parent; onClicked: root.editRequested() }
        }

    }
}
