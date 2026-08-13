import QtQuick
import "."

// Alpine package manager view. Installed packages come from `apk info -v`;
// details come from `apk info -a`. Install/remove needs root and is therefore
// reported as an authorization requirement instead of being faked.
Item {
    id: root

    property var    packages: []
    property int    focusIndex: 0
    property string query: ""
    property bool   loading: false
    property string statusText: ""
    property var    details: []
    property bool   detailOpen: false

    signal focusRequested(int index)
    signal packageActivated(int index)
    signal searchRequested()
    signal refreshRequested()

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
                text: "PACKAGES"
                font.pixelSize: 16
                font.family: Tokens.fontDisplay
                font.weight: Font.DemiBold
                color: Tokens.accent
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 340
                height: 26
                radius: Tokens.rSm
                color: Tokens.bgSurface
                border.color: root.query.length > 0 ? Tokens.accent : Tokens.borderSubtle
                Text {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: Tokens.sp2; rightMargin: Tokens.sp2 }
                    elide: Text.ElideRight
                    text: root.query.length > 0 ? "search: " + root.query : "X — search installed packages"
                    font.pixelSize: 9
                    font.family: Tokens.fontMono
                    color: root.query.length > 0 ? Tokens.textPrimary : Tokens.textDisabled
                }
                MouseArea { anchors.fill: parent; onClicked: root.searchRequested() }
            }
            Rectangle {
                width: 76; height: 26; radius: Tokens.rSm
                color: Tokens.bgElevated
                border.color: Tokens.border
                Text { anchors.centerIn: parent; text: "Refresh"; font.pixelSize: 9; font.family: Tokens.fontMono; color: Tokens.accent }
                MouseArea { anchors.fill: parent; onClicked: root.refreshRequested() }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Tokens.borderSubtle }

        ListView {
            id: list
            visible: !root.detailOpen
            width: parent.width
            height: parent.height - 52
            clip: true
            interactive: true
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 0
            spacing: Tokens.sp1
            model: root.packages
            currentIndex: root.focusIndex

            delegate: Rectangle {
                required property var modelData
                required property int index
                width: list.width
                height: 34
                radius: Tokens.rSm
                color: index === root.focusIndex ? Tokens.accentGlow : Tokens.bgSurface
                border.color: index === root.focusIndex ? Tokens.accent : Tokens.borderSubtle
                border.width: 1

                Row {
                    anchors { fill: parent; leftMargin: Tokens.sp3; rightMargin: Tokens.sp3 }
                    spacing: Tokens.sp3
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 200
                        text: modelData.name
                        elide: Text.ElideRight
                        font.pixelSize: 11
                        font.family: Tokens.fontSans
                        color: Tokens.textPrimary
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 160
                        horizontalAlignment: Text.AlignRight
                        text: modelData.version
                        font.pixelSize: 9
                        font.family: Tokens.fontMono
                        color: index === root.focusIndex ? Tokens.accent : Tokens.textDisabled
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onPressed: root.focusRequested(index)
                    onClicked: root.packageActivated(index)
                }
            }

            Text {
                anchors.centerIn: parent
                visible: !root.loading && root.packages.length === 0
                text: root.statusText || "No packages matched"
                font.pixelSize: 11
                font.family: Tokens.fontMono
                color: Tokens.textDisabled
            }
        }

        Rectangle {
            visible: root.detailOpen
            width: parent.width
            height: parent.height - 52
            radius: Tokens.rSm
            color: Tokens.bgSurface
            border.color: Tokens.accent
            border.width: 1

            Flickable {
                anchors { fill: parent; margins: Tokens.sp3 }
                contentHeight: detailCol.implicitHeight
                clip: true
                Column {
                    id: detailCol
                    width: parent.width
                    spacing: 2
                    Repeater {
                        model: root.details
                        delegate: Text {
                            required property var modelData
                            width: detailCol.width
                            text: modelData
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            font.pixelSize: 10
                            font.family: Tokens.fontMono
                            color: Tokens.textSecondary
                        }
                    }
                }
            }
        }

    }
}
