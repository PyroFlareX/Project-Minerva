import QtQuick
import "."

Item {
    id: root

    property string button: "A"
    property bool teal: true
    readonly property string normalized: button.toUpperCase()
    readonly property bool face: ["A", "B", "X", "Y"].indexOf(normalized) >= 0
    readonly property bool dpad: normalized === "D-PAD"
    readonly property string shape: face ? "face" : (dpad ? "dpad" : "pill")
    readonly property real glyphWidth: dpad ? 28 : (face ? 22 : 30)

    width: glyphWidth
    height: dpad ? 22 : (face ? 22 : 18)

    Image {
        anchors.fill: parent
        source: "assets/gamepad/" + root.shape + (root.teal ? "-teal.svg" : "-base.svg")
        sourceSize: Qt.size(root.width, root.height)
        fillMode: Image.PreserveAspectFit
        smooth: true
    }

    Text {
        anchors.centerIn: parent
        text: root.normalized
        font.pixelSize: root.face ? 10 : 7
        font.family: Tokens.fontMono
        font.weight: Font.DemiBold
        color: root.teal ? Tokens.textOnAccent : Tokens.textSecondary
    }
}
