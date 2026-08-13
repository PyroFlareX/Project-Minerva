import QtQuick
import "."

// Two-pane settings editor driven entirely by settings-schema.toml: the left
// pane lists sections, the right pane shows only the rows of the active
// section. The shell owns focus and value state; this component renders it.
Item {
    id: root

    property var    sections: []
    property var    rows: []
    property int    sectionIndex: 0
    property int    rowIndex: 0
    property string pane: "sidebar"      // "sidebar" | "rows"
    property bool   loading: false
    property string statusText: ""

    signal sectionRequested(int index)
    signal rowRequested(int index)
    signal rowActivated(int index)
    signal rowAdjusted(int index, int delta)

    function widgetValue(row) {
        if (row.widget === "toggle")
            return (row.value === "true" || row.value === "on" || row.value === "1") ? "ON" : "OFF"
        if (row.value === undefined || row.value === "")
            return row.widget === "action" ? "▶" : "—"
        if (row.widget === "slider")
            return row.value + "%"
        return row.value
    }

    onSectionIndexChanged: if (sectionList.count > 0) sectionList.positionViewAtIndex(sectionIndex, ListView.Contain)
    onRowIndexChanged: if (rowList.count > 0) rowList.positionViewAtIndex(rowIndex, ListView.Contain)

    Row {
        anchors { fill: parent; margins: Tokens.sp4 }
        spacing: Tokens.sp4

        // ── Sidebar ──────────────────────────────────────────────────────────
        Rectangle {
            width: 260
            height: parent.height
            radius: Tokens.rSm
            color: Tokens.bgSurface
            border.color: root.pane === "sidebar" ? Tokens.accent : Tokens.borderSubtle
            border.width: 1

            Column {
                anchors { fill: parent; margins: Tokens.sp2 }
                spacing: Tokens.sp2

                Text {
                    text: "SETTINGS"
                    font.pixelSize: 14
                    font.family: Tokens.fontDisplay
                    font.weight: Font.DemiBold
                    color: Tokens.accent
                }

                ListView {
                    id: sectionList
                    width: parent.width
                    height: parent.height - 30
                    clip: true
                    interactive: true
                    boundsBehavior: Flickable.StopAtBounds
                    spacing: 2
                    model: root.sections
                    currentIndex: root.sectionIndex

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: sectionList.width
                        height: 30
                        radius: Tokens.rSm
                        color: index === root.sectionIndex ? Tokens.accentGlow : "transparent"
                        border.color: index === root.sectionIndex && root.pane === "sidebar"
                                      ? Tokens.accent : "transparent"
                        border.width: 1
                        Text {
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: Tokens.sp2; rightMargin: Tokens.sp2 }
                            text: modelData.title
                            elide: Text.ElideRight
                            font.pixelSize: 10
                            font.family: Tokens.fontMono
                            color: index === root.sectionIndex ? Tokens.accent : Tokens.textSecondary
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.sectionRequested(index) }
                    }
                }
            }
        }

        // ── Rows ─────────────────────────────────────────────────────────────
        Rectangle {
            width: parent.width - 260 - Tokens.sp4
            height: parent.height
            radius: Tokens.rSm
            color: Tokens.bgSurface
            border.color: root.pane === "rows" ? Tokens.accent : Tokens.borderSubtle
            border.width: 1

            Column {
                anchors { fill: parent; margins: Tokens.sp3 }
                spacing: Tokens.sp2

                Text {
                    text: root.sections.length > 0 && root.sections[root.sectionIndex]
                          ? root.sections[root.sectionIndex].title
                          : "SETTINGS"
                    font.pixelSize: 15
                    font.family: Tokens.fontDisplay
                    font.weight: Font.DemiBold
                    color: Tokens.textPrimary
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.loading ? "Reading schema…"
                                       : (root.statusText || (root.rows.length + " settings  ·  A edits, L/R adjusts"))
                    font.pixelSize: 9
                    font.family: Tokens.fontMono
                    color: Tokens.textDisabled
                }

                ListView {
                    id: rowList
                    width: parent.width
                    height: parent.height - 46
                    clip: true
                    interactive: true
                    boundsBehavior: Flickable.StopAtBounds
                    spacing: Tokens.sp1
                    model: root.rows
                    currentIndex: root.rowIndex

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: rowList.width
                        height: 46
                        radius: Tokens.rSm
                        color: index === root.rowIndex && root.pane === "rows"
                               ? Tokens.accentGlow : Tokens.bgElevated
                        border.color: index === root.rowIndex
                                      ? (root.pane === "rows" ? Tokens.accent : Tokens.border)
                                      : Tokens.borderSubtle
                        border.width: 1

                        Row {
                            anchors { fill: parent; leftMargin: Tokens.sp3; rightMargin: Tokens.sp3 }
                            spacing: Tokens.sp3

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 24
                                text: modelData.icon
                                font.pixelSize: 14
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 220
                                Text {
                                    width: parent.width
                                    text: modelData.label
                                    elide: Text.ElideRight
                                    font.pixelSize: 11
                                    font.family: Tokens.fontSans
                                    color: Tokens.textPrimary
                                }
                                Text {
                                    width: parent.width
                                    text: modelData.desc
                                    elide: Text.ElideRight
                                    font.pixelSize: 8
                                    font.family: Tokens.fontMono
                                    color: Tokens.textDisabled
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 150
                                horizontalAlignment: Text.AlignRight
                                text: root.widgetValue(modelData)
                                elide: Text.ElideRight
                                font.pixelSize: 10
                                font.family: Tokens.fontMono
                                color: modelData.widget === "text" ? Tokens.textSecondary : Tokens.accent
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onPressed: root.rowRequested(index)
                            onClicked: root.rowActivated(index)
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !root.loading && root.rows.length === 0
                        text: root.statusText || "This section has no rows"
                        font.pixelSize: 11
                        font.family: Tokens.fontMono
                        color: Tokens.textDisabled
                    }
                }
            }
        }
    }
}
