import QtQuick
import "."

Item {
    id: root

    property var metrics: ({
        load: "—", memory: "—", disk: "—", temperature: "—",
        battery: "—", batteryStatus: "unknown", uptime: "—"
    })
    property string updated: "waiting for sample"

    signal refreshRequested()

    function metricValue(key) {
        var value = root.metrics[key]
        return value === undefined || value === "" ? "—" : String(value)
    }

    Column {
        anchors.fill: parent
        anchors.margins: Tokens.sp4
        spacing: Tokens.sp3

        Row {
            width: parent.width
            height: 34
            Text {
                width: parent.width - 86
                text: "SYSTEM MONITOR"
                font.pixelSize: 15
                font.family: Tokens.fontDisplay
                color: Tokens.textPrimary
            }
            Rectangle {
                width: 76; height: 28; radius: Tokens.rSm
                color: Tokens.bgElevated
                border.color: Tokens.border
                Text { anchors.centerIn: parent; text: "Refresh"; font.pixelSize: 9; font.family: Tokens.fontMono; color: Tokens.accent }
                MouseArea { anchors.fill: parent; onClicked: root.refreshRequested() }
            }
        }

        Grid {
            width: parent.width
            columns: 2
            rowSpacing: Tokens.sp2
            columnSpacing: Tokens.sp2
            Repeater {
                model: [
                    { key: "load", label: "CPU load", icon: "▥" },
                    { key: "memory", label: "Memory", icon: "▤" },
                    { key: "disk", label: "Root disk", icon: "◫" },
                    { key: "temperature", label: "Temperature", icon: "♨" },
                    { key: "battery", label: "Battery", icon: "⌁" },
                    { key: "uptime", label: "Uptime", icon: "◷" }
                ]
                delegate: Rectangle {
                    width: (parent.width - Tokens.sp2) / 2
                    height: 72
                    radius: Tokens.rMd
                    color: Tokens.bgSurface
                    border.color: modelData.key === "battery" && root.metrics.batteryLow ? Tokens.error : Tokens.borderSubtle
                    border.width: 1
                    Column {
                        anchors.fill: parent
                        anchors.margins: Tokens.sp3
                        spacing: 4
                        Row {
                            spacing: Tokens.sp1
                            Text { text: modelData.icon; font.pixelSize: 12; color: Tokens.accent }
                            Text { text: modelData.label; font.pixelSize: 9; font.family: Tokens.fontMono; color: Tokens.textDisabled }
                        }
                        Text {
                            text: root.metricValue(modelData.key)
                            font.pixelSize: 16
                            font.family: Tokens.fontMono
                            color: modelData.key === "battery" && root.metrics.batteryLow ? Tokens.error : Tokens.textPrimary
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.refreshRequested() }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 54
            radius: Tokens.rMd
            color: root.metrics.batteryLow ? "#30131a" : Tokens.bgElevated
            border.color: root.metrics.batteryLow ? Tokens.error : Tokens.border
            Text {
                anchors.fill: parent
                anchors.margins: Tokens.sp3
                text: root.metrics.batteryLow ? "LOW BATTERY · reduce brightness or connect power" : "Live data from /proc, /sys, and df"
                wrapMode: Text.WordWrap
                font.pixelSize: 10
                font.family: Tokens.fontMono
                color: root.metrics.batteryLow ? Tokens.error : Tokens.textSecondary
                verticalAlignment: Text.AlignVCenter
            }
        }

        ControlHints {
            width: parent.width
            hints: [
                {button: "A", label: "Refresh"},
                {button: "B", label: "Home"}
            ]
        }
    }
}
