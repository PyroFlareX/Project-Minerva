import QtQuick
import "."

Rectangle {
    id: root
    color: Tokens.lowerBg

    required property string timeStr
    property string activeApp:   ""
    property int    batteryPct:  100
    property bool   batteryKnown: false
    property string batteryStatus: "unknown"
    property bool   lowBattery: false
    property bool   paletteOpen: false
    property bool   radialOpen:  false
    property bool   oskOpen:      false
    property var    actions: []
    property string externalApp: ""
    property bool   externalRunning: false
    property var    externalControls: []
    // One line of app-supplied context, e.g. the Files path or the last
    // terminal command. The shell computes it; the panel only renders it.
    property string appContext: ""

    signal oskRequested()
    signal actionTriggered(string id)

    // Status bar (top 28px)
    Rectangle {
        id: lowerBar
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 28
        color: "#cc0a0c11"
        border.color: Tokens.borderSubtle
        border.width: 0

        // Bottom hairline
        Rectangle {
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 1; color: Tokens.borderSubtle
        }

        Text {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 10 }
            text: "MINERVA"
            font.pixelSize: 9
            font.family: Tokens.fontDisplay
            font.weight: Font.Bold
            color: Tokens.accentDim
            font.letterSpacing: 2
        }

        Text {
            anchors.centerIn: parent
            text: root.timeStr
            font.pixelSize: 12
            font.family: Tokens.fontMono
            color: Tokens.textPrimary
        }

        Text {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 10 }
            text: root.batteryKnown ? "🔋 " + root.batteryPct + "%" : "🔋 —"
            font.pixelSize: 10
            font.family: Tokens.fontMono
            color: root.lowBattery ? Tokens.error : Tokens.textSecondary
        }
    }

    Rectangle {
        visible: root.lowBattery
        anchors { top: lowerBar.bottom; left: parent.left; right: parent.right }
        height: 22
        color: "#40131a"
        border.color: Tokens.error
        Text {
            anchors.centerIn: parent
            text: "LOW BATTERY · " + root.batteryPct + "%"
            font.pixelSize: 9
            font.family: Tokens.fontMono
            color: Tokens.error
        }
    }

    // An external Wayland client owns the upper display; the companion screen
    // keeps the only visible way back.
    Rectangle {
        id: externalBar
        visible: root.externalRunning
        anchors { top: root.lowBattery ? undefined : lowerBar.bottom; left: parent.left; right: parent.right }
        y: root.lowBattery ? lowerBar.height + 22 : lowerBar.height
        height: 26
        color: "#101a24"
        border.color: Tokens.accent
        Text {
            anchors.centerIn: parent
            text: "RUNNING " + root.externalApp.toUpperCase() + " · B CLOSES IT"
            font.pixelSize: 9
            font.family: Tokens.fontMono
            color: Tokens.accent
            elide: Text.ElideMiddle
            width: parent.width - 16
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // Main content area
    Item {
        anchors { top: lowerBar.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }

        // Default: idle status
        Column {
            visible: !root.paletteOpen && !root.radialOpen && !root.oskOpen
            anchors.centerIn: parent
            spacing: 16

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "◎"
                font.pixelSize: 36
                color: Tokens.accentDim
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.4; duration: 1800; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 1800; easing.type: Easing.InOutSine }
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.activeApp !== "" ? root.activeApp : "Home"
                    font.pixelSize: 14
                    font.family: Tokens.fontDisplay
                    font.weight: Font.DemiBold
                    color: Tokens.textPrimary
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.appContext.length > 0
                    width: root.width - 40
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    text: root.appContext
                    font.pixelSize: 10
                    font.family: Tokens.fontMono
                    color: Tokens.accent
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Project Minerva · Companion"
                    font.pixelSize: 9
                    font.family: Tokens.fontMono
                    color: Tokens.textDisabled
                }
            }

            // Quick button hint grid
            Grid {
                anchors.horizontalCenter: parent.horizontalCenter
                columns: 3
                spacing: 8

                Repeater {
                    model: root.actions
                    delegate: Rectangle {
                        width: 72; height: 26
                        radius: Tokens.rSm
                        color: Tokens.lowerSurface
                        border.color: Tokens.borderSubtle
                        border.width: 1

                        Row {
                            anchors.centerIn: parent
                            spacing: 4
                            GamepadGlyph {
                                button: modelData.key
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: modelData.label
                                font.pixelSize: 8
                                font.family: Tokens.fontSans
                                color: Tokens.textDisabled
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.actionTriggered(modelData.id)
                        }
                    }
                }
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 96
                height: 30
                radius: Tokens.rSm
                color: Tokens.lowerSurface
                border.color: Tokens.accent
                border.width: 1
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Text { text: "⌨"; font.pixelSize: 14; color: Tokens.accent }
                    Text { text: "OSK"; font.pixelSize: 10; font.family: Tokens.fontMono; color: Tokens.textPrimary }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.oskRequested()
                }
            }
        }

        // Locked mode: controller-only unlock; no touch targets.
        Column {
            visible: root.locked
            anchors.centerIn: parent
            spacing: 12

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "🔒"
                font.pixelSize: 32
                color: Tokens.accent
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Locked"
                font.pixelSize: 13
                font.family: Tokens.fontDisplay
                color: Tokens.textPrimary
            }
            ControlHints {
                anchors.horizontalCenter: parent.horizontalCenter
                hints: [{button: "A", label: "Unlock"}]
                spacing: 8
            }
        }

        // External client mode: show the app context, its controller map, and
        // the exits owned by Torchform. The lower screen is informational
        // while an external client owns the upper display.
        Column {
            visible: root.externalRunning && !root.locked
            anchors.centerIn: parent
            spacing: 8

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "↗"
                font.pixelSize: 32
                color: Tokens.accent
            }
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.externalApp
                    font.pixelSize: 13
                    font.family: Tokens.fontDisplay
                    font.weight: Font.DemiBold
                    color: Tokens.textPrimary
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.appContext.length > 0
                    width: root.width - 40
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    text: root.appContext
                    font.pixelSize: 10
                    font.family: Tokens.fontMono
                    color: Tokens.accent
                }
            }

            Text {
                visible: root.externalControls.length > 0
                anchors.horizontalCenter: parent.horizontalCenter
                text: "APP CONTROLS"
                font.pixelSize: 8
                font.family: Tokens.fontMono
                font.weight: Font.DemiBold
                color: Tokens.textSecondary
            }

            Grid {
                id: externalControlsGrid
                visible: root.externalControls.length > 0
                width: root.width - 24
                columns: 3
                columnSpacing: 8
                rowSpacing: 4
                anchors.horizontalCenter: parent.horizontalCenter

                Repeater {
                    model: root.externalControls
                    delegate: Rectangle {
                        id: controlCard
                        required property var modelData
                        property var controlData: modelData
                        property string buttonName: controlData.button || ""
                        // no directional d-pad variants. Use compact arrows
                        // so every logical d-pad binding remains readable.
                        property string glyphButton: {
                            var name = buttonName.toLowerCase()
                            if (name === "dpad_up") return "↑"
                            if (name === "dpad_down") return "↓"
                            if (name === "dpad_left") return "←"
                            if (name === "dpad_right") return "→"
                            return buttonName
                        }

                        width: 250
                        height: 24
                        radius: Tokens.rSm
                        color: Tokens.lowerSurface
                        border.color: Tokens.borderSubtle
                        border.width: 1
                        clip: true

                        Row {
                            anchors {
                                fill: parent
                                leftMargin: 7
                                rightMargin: 5
                            }
                            spacing: 5

                            GamepadGlyph {
                                button: controlCard.glyphButton
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                width: Math.max(0, parent.width - 35)
                                text: controlCard.controlData.label || controlCard.buttonName
                                font.pixelSize: 8
                                font.family: Tokens.fontSans
                                color: Tokens.textPrimary
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }
            }

            // These exits are always Torchform-owned and visually separate
            // from the external program's controller map.
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 270
                height: 40
                radius: Tokens.rSm
                color: Tokens.lowerSurface
                border.color: Tokens.accent
                border.width: 1

                Column {
                    anchors.centerIn: parent
                    spacing: 2

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "TORCHFORM"
                        font.pixelSize: 7
                        font.family: Tokens.fontMono
                        font.weight: Font.DemiBold
                        color: Tokens.accent
                    }
                    ControlHints {
                        anchors.horizontalCenter: parent.horizontalCenter
                        hints: [
                            {button: "B", label: "Close"},
                            {button: "START", label: "Home"}
                        ]
                        spacing: 8
                    }
                }
            }
        }

        // Generic overlay mode: keep context and hints visible; no touch targets.
        Column {
            visible: root.overlayOpen && !root.locked && !root.externalRunning &&
                     !root.paletteOpen && !root.radialOpen
            anchors.centerIn: parent
            spacing: 12

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.overlayLabel
                font.pixelSize: 13
                font.family: Tokens.fontDisplay
                color: Tokens.textPrimary
            }
            ControlHints {
                anchors.horizontalCenter: parent.horizontalCenter
                hints: root.hints
                spacing: 8
            }
        }
        // Palette mode indicator
        Column {
            visible: root.paletteOpen
            anchors.centerIn: parent
            spacing: 12

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "🔍"
                font.pixelSize: 32
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Command Search"
                font.pixelSize: 13
                font.family: Tokens.fontDisplay
                color: Tokens.textPrimary
            }
            ControlHints {
                anchors.horizontalCenter: parent.horizontalCenter
                hints: [
                    {button: "D-PAD", label: "Navigate"},
                    {button: "A", label: "Select"},
                    {button: "B", label: "Close"}
                ]
                spacing: 8
            }
        }

        // Radial mode indicator
        Column {
            visible: root.radialOpen
            anchors.centerIn: parent
            spacing: 12

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "⊕"
                font.pixelSize: 32
                color: Tokens.accent
                SequentialAnimation on rotation {
                    loops: Animation.Infinite
                    NumberAnimation { to: 360; duration: 8000 }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Radial Menu"
                font.pixelSize: 13
                font.family: Tokens.fontDisplay
                color: Tokens.accent
            }
            ControlHints {
                anchors.horizontalCenter: parent.horizontalCenter
                hints: [
                    {button: "D-PAD", label: "Navigate"},
                    {button: "A", label: "Activate"},
                    {button: "B", label: "Close"}
                ]
                spacing: 8
            }
        }
    }
}
