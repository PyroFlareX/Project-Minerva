pragma ComponentBehavior: Bound
import QtQuick
import "."

// Controller-navigated on-screen keyboard.
// D-pad moves focus, A (via shell.handleConfirm → osk.activateKey) types the key.
// Signals: keyEmitted(key) for characters/backspace, closeRequested() for ✓.
// Shell owns the text state; this component is purely visual + layout.

Item {
    id: root

    property bool open: false

    signal keyEmitted(string key)
    signal closeRequested()

    visible: open
    opacity: open ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: Tokens.animNormal } }

    // ── Internal nav state ────────────────────────────────────────────────────
    property int  focusRow: 0
    property int  focusCol: 0
    property bool shifted:  false
    property bool symMode:  false

    // ── Layouts ───────────────────────────────────────────────────────────────
    readonly property var normalRows: [
        ["q","w","e","r","t","y","u","i","o","p"],
        ["a","s","d","f","g","h","j","k","l","⌫"],
        ["z","x","c","v","b","n","m",",","."],
        ["⇧","123"," ","@","-","_","✓"]
    ]
    readonly property var shiftRows: [
        ["Q","W","E","R","T","Y","U","I","O","P"],
        ["A","S","D","F","G","H","J","K","L","⌫"],
        ["Z","X","C","V","B","N","M","<",">"],
        ["⇧","123"," ","!","?",":","✓"]
    ]
    readonly property var symRows: [
        ["1","2","3","4","5","6","7","8","9","0"],
        ["!","@","#","$","%","^","&","*","(",")"],
        ["-","_","=","+","[","]","{","}","\\","/"],
        ["abc",",",".",";",'\"',"'","⌫","✓"]
    ]

    readonly property var activeRows: symMode ? symRows : (shifted ? shiftRows : normalRows)

    // ── Public API ────────────────────────────────────────────────────────────
    function reset() {
        focusRow = 0
        focusCol = 0
        shifted  = false
        symMode  = false
    }

    function navUp() {
        if (focusRow > 0) {
            focusRow--
            var rlen = activeRows[focusRow].length
            if (focusCol >= rlen) focusCol = rlen - 1
        }
    }
    function navDown() {
        if (focusRow < activeRows.length - 1) {
            focusRow++
            var rlen = activeRows[focusRow].length
            if (focusCol >= rlen) focusCol = rlen - 1
        }
    }
    function navLeft() {
        var rlen = activeRows[focusRow].length
        focusCol = (focusCol - 1 + rlen) % rlen
    }
    function navRight() {
        var rlen = activeRows[focusRow].length
        focusCol = (focusCol + 1) % rlen
    }

    function activateKey() {
        var row = activeRows[focusRow]
        var col = Math.min(focusCol, row.length - 1)
        var key = row[col]
        if      (key === "⌫")   { keyEmitted("\b") }
        else if (key === "✓")   { closeRequested() }
        else if (key === "⇧")   { shifted = !shifted }
        else if (key === "123") { symMode = true;  shifted = false }
        else if (key === "abc") { symMode = false; shifted = false }
        else {
            keyEmitted(key)
            // auto-unshift after a letter
            if (shifted && key.length === 1 && key !== " ") shifted = false
        }
    }

    // ── Visual ────────────────────────────────────────────────────────────────
    Rectangle {
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: oskRows.implicitHeight + Tokens.sp3 * 2 + 1
        color: Qt.rgba(0.051, 0.059, 0.078, 0.97)  // bgBase near-opaque

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 1
            color: Tokens.border
        }

        Column {
            id: oskRows
            anchors {
                top: parent.top
                topMargin: Tokens.sp3
                horizontalCenter: parent.horizontalCenter
            }
            spacing: 8

            Repeater {
                model: root.activeRows
                delegate: Row {
                    id: keyRow
                    required property int index
                    required property var modelData
                    spacing: 8
                    anchors.horizontalCenter: parent.horizontalCenter

                    Repeater {
                        model: keyRow.modelData
                        delegate: Rectangle {
                            id: keyRect
                            required property int    index
                            required property string modelData

                            property bool isFocused: root.focusRow === keyRow.index &&
                                                     root.focusCol === keyRect.index
                            property bool isShift: keyRect.modelData === "⇧"
                            property bool isSym:   keyRect.modelData === "123" ||
                                                   keyRect.modelData === "abc"
                            property bool isSpec:  isShift || isSym ||
                                                   keyRect.modelData === "⌫" ||
                                                   keyRect.modelData === "✓"

                            width:  keyRect.modelData === " " ? 240 :
                                    isSpec                    ?  88 : 68
                            height: 52
                            radius: Tokens.rMd

                            color: isFocused                       ? Tokens.accent :
                                   (isShift && root.shifted)       ? Qt.rgba(0, 0.83, 1, 0.22) :
                                   isSpec                          ? Tokens.bgElevated :
                                                                     Tokens.bgSurface
                            border.color: isFocused ? "transparent" : Tokens.borderSubtle
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: Tokens.animFast } }

                            Text {
                                anchors.centerIn: parent
                                text: keyRect.modelData === " " ? "SPACE" : keyRect.modelData
                                font.pixelSize: keyRect.modelData === " " ? 11 :
                                                keyRect.isSpec            ? 14 : 19
                                font.family:    keyRect.isSpec ? Tokens.fontSans : Tokens.fontMono
                                font.bold:      keyRect.isSpec
                                color: keyRect.isFocused ? Tokens.bgBase : Tokens.textPrimary
                            }
                        }
                    }
                }
            }
        }
    }
}
