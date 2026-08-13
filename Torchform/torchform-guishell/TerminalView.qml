import QtQuick
import "."

FocusScope {
    id: root

    property var lines: []
    property bool running: false
    property string prompt: "torchform@minerva:~$"

    signal commandSubmitted(string command)
    signal externalRequested()
    focus: visible
    Component.onCompleted: if (visible) input.forceActiveFocus()
    onVisibleChanged: if (visible) input.forceActiveFocus()

    function focusInput() {
        if (visible && !root.running) input.forceActiveFocus()
    }

    function submitInput() {
        root.commandSubmitted(input.text)
        input.text = ""
    }

    Column {
        anchors.fill: parent
        anchors.margins: Tokens.sp4
        spacing: Tokens.sp2

        Row {
            width: parent.width
            height: 34
            spacing: Tokens.sp2

            Text {
                width: parent.width - 174
                text: "TERMINAL"
                font.pixelSize: 15
                font.family: Tokens.fontDisplay
                color: Tokens.textPrimary
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                width: 76; height: 28; radius: Tokens.rSm
                color: Tokens.bgElevated
                border.color: Tokens.border
                Text { anchors.centerIn: parent; text: "Run"; font.pixelSize: 9; font.family: Tokens.fontMono; color: Tokens.accent }
                MouseArea { anchors.fill: parent; onClicked: root.submitInput() }
            }
            Rectangle {
                width: 84; height: 28; radius: Tokens.rSm
                color: Tokens.accentGlow
                border.color: Tokens.accent
                Text { anchors.centerIn: parent; text: "Terminal App"; font.pixelSize: 9; font.family: Tokens.fontMono; color: Tokens.accent }
                MouseArea { anchors.fill: parent; onClicked: root.externalRequested() }
            }
        }

        Rectangle {
            width: parent.width
            height: parent.height - 96
            color: "#080b10"
            border.color: Tokens.borderSubtle
            border.width: 1
            radius: Tokens.rSm

            Flickable {
                id: output
                anchors.fill: parent
                anchors.margins: Tokens.sp3
                contentWidth: width
                contentHeight: outputColumn.implicitHeight
                clip: true
                Column {
                    id: outputColumn
                    width: output.width
                    spacing: 3
                    Repeater {
                        model: root.lines
                        delegate: Text {
                            width: outputColumn.width
                            text: modelData
                            wrapMode: Text.Wrap
                            font.pixelSize: 11
                            font.family: Tokens.fontMono
                            color: index === root.lines.length - 1 ? Tokens.accent : Tokens.textSecondary
                        }
                    }
                }
                onContentHeightChanged: contentY = Math.max(0, contentHeight - height)
            }
        }

        Row {
            width: parent.width
            height: 36
            spacing: Tokens.sp2
            Text {
                text: root.prompt
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: 11
                font.family: Tokens.fontMono
                color: Tokens.success
            }
            Rectangle {
                width: parent.width - 120
                height: 32
                radius: Tokens.rSm
                color: Tokens.bgSurface
                border.color: input.activeFocus ? Tokens.accent : Tokens.border
                border.width: 1
                TextInput {
                    id: input
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.sp2
                    anchors.rightMargin: Tokens.sp2
                    verticalAlignment: TextInput.AlignVCenter
                    color: Tokens.textPrimary
                    selectionColor: Tokens.accentDim
                    font.pixelSize: 11
                    font.family: Tokens.fontMono
                    focus: visible
                    enabled: !root.running
                    onAccepted: root.submitInput()
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Escape) {
                            event.accepted = true
                            input.focus = false
                        }
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: input.forceActiveFocus() }
            }
        }

        ControlHints {
            width: parent.width
            hints: [
                {button: "A", label: root.running ? "Running" : "Run"},
                {button: "B", label: "Home"}
            ]
        }
    }
}
