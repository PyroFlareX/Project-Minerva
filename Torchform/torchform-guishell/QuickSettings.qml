import QtQuick
import "."

Item {
    id: root

    property bool open: false
    property var config: ({ side: "right", width: 280, title: "Quick Settings",
                            closeGlyph: "›", columns: 2, sliders: [], tiles: [] })
    property var sliderValues: []
    property var tileStates: []
    property int focusIndex: -1

    readonly property int sliderCount: (root.config.sliders || []).length
    readonly property int tileCount: (root.config.tiles || []).length

    signal closed()
    signal itemActivated(int index)
    signal sliderAdjusted(int index, int delta)

    visible: open
    opacity: open ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: Tokens.animNormal } }

    // The full-screen backdrop consumes pointer focus outside the panel.
    MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: root.closed()
    }

    Rectangle {
        id: panel
        anchors {
            top: parent.top
            bottom: parent.bottom
        }
        width: root.config.width || 280
        x: root.open
           ? (root.config.side === "left" ? 0 : parent.width - width)
           : (root.config.side === "left" ? -width : parent.width)
        color: Tokens.bgSurface
        border.color: Tokens.border
        border.width: 1

        Behavior on x { NumberAnimation { duration: Tokens.animNormal; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: root.config.side === "left" ? parent.left : undefined
                right: root.config.side === "left" ? undefined : parent.right
            }
            width: 2
            color: Tokens.accent
        }

        Column {
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                topMargin: 16
            }
            leftPadding: 16
            rightPadding: 16
            spacing: 0

            Text {
                text: root.config.title || "Quick Settings"
                font.pixelSize: 15
                font.family: Tokens.fontDisplay
                font.weight: Font.DemiBold
                color: Tokens.textPrimary
                bottomPadding: 14
                leftPadding: 2
            }

            Repeater {
                model: root.config.sliders || []

                delegate: Item {
                    width: parent.width
                    height: 48

                    SliderRow {
                        anchors.fill: parent
                        label: modelData.label
                        icon: modelData.icon
                        value: root.sliderValues[index] !== undefined
                               ? root.sliderValues[index] : modelData.value
                        focused: root.open && root.focusIndex === index
                        onActivated: root.itemActivated(index)
                        onAdjustRequested: (delta) => root.sliderAdjusted(index, delta)
                    }
                }
            }

            Item { width: 1; height: 12 }

            Grid {
                width: parent.width - 32
                columns: root.config.columns || 2
                spacing: 8

                Repeater {
                    model: root.config.tiles || []

                    delegate: Rectangle {
                        width: (parent.width - (root.config.columns - 1) * 8) /
                               (root.config.columns || 2)
                        height: 60
                        radius: Tokens.rMd
                        color: root.tileStates[index] ? Tokens.accentGlow : Tokens.bgElevated
                        border.color: root.focusIndex === root.sliderCount + index
                                     ? Tokens.accent
                                     : (root.tileStates[index] ? Tokens.accent : Tokens.border)
                        border.width: root.focusIndex === root.sliderCount + index ? 2 : 1

                        Column {
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.icon
                                font.pixelSize: 20
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.name
                                font.pixelSize: 10
                                font.family: Tokens.fontSans
                                color: root.tileStates[index] ? Tokens.accent : Tokens.textSecondary
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.itemActivated(root.sliderCount + index)
                        }
                    }
                }
            }
        }

        // Close handle
        Rectangle {
            anchors {
                verticalCenter: parent.verticalCenter
                left: root.config.side === "left" ? parent.right : undefined
                right: root.config.side === "left" ? undefined : parent.left
            }
            width: 20
            height: 60
            color: Tokens.bgElevated
            border.color: Tokens.border
            border.width: 1
            radius: 4
            Text {
                anchors.centerIn: parent
                text: root.config.closeGlyph || "›"
                font.pixelSize: 14
                color: Tokens.textSecondary
            }
            MouseArea { anchors.fill: parent; onClicked: root.closed() }
        }
    }

    component SliderRow: Item {
        id: slider
        property string label: ""
        property string icon: ""
        property int value: 50
        property bool focused: false

        signal activated()
        signal adjustRequested(int delta)

        Rectangle {
            anchors.fill: parent
            radius: Tokens.rSm
            color: slider.focused ? Tokens.accentGlow : "transparent"
            border.color: slider.focused ? Tokens.accent : "transparent"
            border.width: slider.focused ? 1 : 0
        }

        Column {
            anchors {
                fill: parent
                leftMargin: 6
                rightMargin: 6
            }
            spacing: 4
            Item {
                anchors { left: parent.left; right: parent.right }
                height: labelText.implicitHeight
                Text {
                    id: labelText
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: slider.icon + " " + slider.label
                    font.pixelSize: 11
                    font.family: Tokens.fontSans
                    color: slider.focused ? Tokens.accent : Tokens.textSecondary
                }
                Text {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: slider.value + "%"
                    font.pixelSize: 11
                    font.family: Tokens.fontMono
                    color: Tokens.textSecondary
                }
            }
            Rectangle {
                width: parent.width
                height: 4
                radius: 2
                color: Tokens.bgElevated
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(100, slider.value)) / 100
                    height: 4
                    radius: 2
                    color: Tokens.accent
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: slider.activated()
            onPressAndHold: slider.adjustRequested(5)
        }
    }
}
