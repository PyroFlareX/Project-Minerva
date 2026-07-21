// Smoke test: does the Torchform.Gamepad module load and expose the Gamepad
// singleton? Run headless with:
//   qmllint -I build test.qml
// or at runtime under a compositor:
//   QML_IMPORT_PATH=$PWD/build quickshell -p test.qml   (needs a Wayland display)
import QtQuick
import Torchform.Gamepad

Item {
    Component.onCompleted: console.log("gamepad connected:", Gamepad.connected)

    Connections {
        target: Gamepad
        function onButtonPressed(name) { console.log("press:", name) }
        function onButtonReleased(name) { console.log("release:", name) }
        function onActionTriggered(name) { console.log("action:", name) }
    }

    // Held-state binding sanity check.
    property bool l1Held: Gamepad.buttons["l1"] === true
    property real lx: Gamepad.leftX
}
