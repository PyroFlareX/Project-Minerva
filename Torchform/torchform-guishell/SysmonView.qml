import QtQuick
import "."

Item {
    id: root

    property var metrics: ({})
    property var history: []
    property int focusIndex: 0
    property string updated: "waiting for sample"

    signal refreshRequested()

    readonly property var devices: [
        { key: "load", label: "CPU", icon: "▥", color: Tokens.accent },
        { key: "memory", label: "Memory", icon: "▤", color: "#6ea8ff" },
        { key: "disk", label: "Root disk", icon: "◫", color: "#6ed6b0" },
        { key: "network", label: "Network", icon: "⌁", color: "#d69cff" },
        { key: "temperature", label: "Thermal", icon: "♨", color: "#ff7b72" },
        { key: "battery", label: "Battery", icon: "⌂", color: "#e7c86e" }
    ]

    function textValue(key, fallback) {
        var value = root.metrics[key]
        return value === undefined || value === "" ? (fallback || "—") : String(value)
    }

    function numericValue(value) {
        var number = Number.parseFloat(String(value === undefined ? "" : value))
        return Number.isFinite(number) ? number : 0
    }

    function currentValue(key) {
        if (key === "network")
            return textValue("net_rx", "0 KB/s") + " ↓"
        if (key === "temperature")
            return textValue("temperature", "—")
        if (key === "battery") {
            var battery = textValue("battery", "—")
            return battery === "—" || battery === "?" ? "—" : battery + "%"
        }
        if (key === "load")
            return textValue("load", "—") + "%"
        if (key === "memory" || key === "disk")
            return textValue(key, "—")
        return "—"
    }

    function deviceSubtitle(device) {
        if (device.key === "load")
            return textValue("cpu_speed", "—") + " · " + textValue("processes", "—") + " processes"
        if (device.key === "memory")
            return textValue("memory_used", "—") + " / " + textValue("memory_total", "—")
        if (device.key === "disk")
            return textValue("disk_used", "—") + " / " + textValue("disk_total", "—")
        if (device.key === "network")
            return textValue("net_tx", "0 KB/s") + " ↑"
        if (device.key === "temperature")
            return textValue("temperature", "thermal sensors")
        return textValue("battery_status", "battery telemetry unavailable")
    }

    function historyValues(key) {
        var values = []
        for (var i = 0; i < root.history.length; i++) {
            var sample = root.history[i] || {}
            if (key === "network") {
                values.push(numericValue(sample.net_rx))
            } else if (key === "temperature") {
                values.push(numericValue(sample.temperature))
            } else if (key === "battery") {
                values.push(numericValue(sample.battery))
            } else {
                values.push(numericValue(sample[key]))
            }
        }
        if (values.length === 0) values.push(numericValue(root.metrics[key]))
        return values
    }

    function graphSpecs() {
        if (root.focusIndex === 0) {
            return [
                { key: "cpu0", title: "CPU 0", unit: "%", color: Tokens.accent },
                { key: "cpu1", title: "CPU 1", unit: "%", color: Tokens.accent },
                { key: "cpu2", title: "CPU 2", unit: "%", color: Tokens.accent },
                { key: "cpu3", title: "CPU 3", unit: "%", color: Tokens.accent }
            ]
        }
        if (root.focusIndex === 1) {
            return [
                { key: "memory", title: "Memory used", unit: "%", color: "#6ea8ff" },
                { key: "swap", title: "Swap used", unit: "%", color: "#9bc4ff" },
                { key: "memory_used", title: "Resident", unit: "MB", color: "#6ea8ff" },
                { key: "memory_available", title: "Available", unit: "MB", color: "#9bc4ff" }
            ]
        }
        if (root.focusIndex === 2) {
            return [
                { key: "disk", title: "Root disk", unit: "%", color: "#6ed6b0" },
                { key: "disk_read", title: "Read throughput", unit: "KB/s", color: "#92e6c6" },
                { key: "disk_write", title: "Write throughput", unit: "KB/s", color: "#4dbd92" },
                { key: "uptime", title: "Uptime", unit: "", color: "#6ed6b0" }
            ]
        }
        if (root.focusIndex === 3) {
            return [
                { key: "net_rx", title: "Received", unit: "KB/s", color: "#d69cff" },
                { key: "net_tx", title: "Transmitted", unit: "KB/s", color: "#b778ef" },
                { key: "net_rx", title: "Wireless / LAN", unit: "KB/s", color: "#d69cff" },
                { key: "net_tx", title: "Interface total", unit: "KB/s", color: "#b778ef" }
            ]
        }
        if (root.focusIndex === 4) {
            return [
                { key: "temperature", title: "SoC temperature", unit: "°C", color: "#ff7b72" },
                { key: "load", title: "CPU load", unit: "%", color: "#ff9a91" },
                { key: "cpu_speed", title: "Clock speed", unit: "", color: "#ff7b72" },
                { key: "processes", title: "Processes", unit: "", color: "#ff9a91" }
            ]
        }
        return [
            { key: "battery", title: "Charge", unit: "%", color: "#e7c86e" },
            { key: "battery", title: "Battery history", unit: "%", color: "#e7c86e" },
            { key: "memory", title: "System load", unit: "%", color: "#c9aa59" },
            { key: "temperature", title: "Thermal context", unit: "°C", color: "#c9aa59" }
        ]
    }

    function graphCurrent(spec) {
        var value = root.metrics[spec.key]
        if (value === undefined || value === "") {
            if (spec.key === "cpu0" || spec.key === "cpu1" || spec.key === "cpu2" || spec.key === "cpu3")
                value = root.metrics.load
            else if (spec.key === "memory_available")
                value = numericValue(root.metrics.memory_total) - numericValue(root.metrics.memory_used)
            else if (spec.key === "disk_read" || spec.key === "disk_write")
                value = 0
        }
        var text = value === undefined || value === "" ? "—" : String(value)
        return spec.unit && text !== "—" && text.indexOf(spec.unit) < 0 ? text + spec.unit : text
    }

    component Sparkline: Canvas {
        property var values: []
        property color stroke: Tokens.accent
        property color fill: "#204b67"
        onValuesChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)
            if (values.length < 1) return
            var maxValue = 1
            for (var i = 0; i < values.length; i++) maxValue = Math.max(maxValue, numericValue(values[i]))
            var step = values.length > 1 ? width / (values.length - 1) : width
            ctx.beginPath()
            ctx.moveTo(0, height)
            for (var j = 0; j < values.length; j++) {
                var x = j * step
                var y = height - numericValue(values[j]) / maxValue * (height - 4) - 2
                ctx.lineTo(x, y)
            }
            ctx.lineTo(width, height)
            ctx.closePath()
            ctx.fillStyle = fill
            ctx.fill()
            ctx.beginPath()
            for (var k = 0; k < values.length; k++) {
                var px = k * step
                var py = height - numericValue(values[k]) / maxValue * (height - 4) - 2
                if (k === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py)
            }
            ctx.strokeStyle = stroke
            ctx.lineWidth = 1.5
            ctx.stroke()
        }
    }

    component GraphPanel: Rectangle {
        property var spec: ({ key: "load", title: "CPU", unit: "%", color: Tokens.accent })
        property var values: []
        property string current: "—"
        radius: Tokens.rMd
        color: Tokens.bgSurface
        border.color: Tokens.borderSubtle
        border.width: 1

        Text {
            anchors { top: parent.top; left: parent.left; topMargin: 10; leftMargin: 12 }
            text: spec.title
            font.pixelSize: 11
            font.family: Tokens.fontMono
            color: Tokens.textSecondary
        }
        Text {
            anchors { top: parent.top; right: parent.right; topMargin: 9; rightMargin: 12 }
            text: current
            font.pixelSize: 13
            font.family: Tokens.fontMono
            color: spec.color
        }
        Sparkline {
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left; right: parent.right }
            anchors.margins: 10
            values: parent.values
            stroke: spec.color
            fill: Qt.rgba(spec.color.r, spec.color.g, spec.color.b, 0.16)
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            color: spec.color
            opacity: 0.35
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: Tokens.sp4
        spacing: Tokens.sp3

        Row {
            width: parent.width
            height: 34
            Text {
                width: parent.width - 170
                text: "SYSTEM MONITOR  /  PERFORMANCE"
                font.pixelSize: 15
                font.family: Tokens.fontDisplay
                font.weight: Font.DemiBold
                color: Tokens.textPrimary
            }
            Text {
                width: 90
                text: "LIVE  ·  " + root.updated
                horizontalAlignment: Text.AlignRight
                font.pixelSize: 9
                font.family: Tokens.fontMono
                color: Tokens.textDisabled
            }
            Rectangle {
                width: 76
                height: 28
                radius: Tokens.rSm
                color: Tokens.bgElevated
                border.color: Tokens.accent
                Text {
                    anchors.centerIn: parent
                    text: "Refresh"
                    font.pixelSize: 9
                    font.family: Tokens.fontMono
                    color: Tokens.accent
                }
                MouseArea { anchors.fill: parent; onClicked: root.refreshRequested() }
            }
        }

        Row {
            width: parent.width
            height: parent.height - 34 - Tokens.sp3
            spacing: Tokens.sp3

            Rectangle {
                width: Math.max(210, Math.min(260, parent.width * 0.18))
                height: parent.height
                radius: Tokens.rMd
                color: Tokens.bgSurface
                border.color: Tokens.borderSubtle
                Column {
                    anchors.fill: parent
                    anchors.margins: Tokens.sp3
                    spacing: Tokens.sp2
                    Text {
                        text: "DEVICES"
                        font.pixelSize: 10
                        font.family: Tokens.fontMono
                        color: Tokens.textDisabled
                    }
                    Repeater {
                        model: root.devices
                        delegate: Rectangle {
                            width: parent.width
                            height: 82
                            radius: Tokens.rSm
                            color: root.focusIndex === index ? Tokens.accentGlow : Tokens.bgElevated
                            border.color: root.focusIndex === index ? modelData.color : Tokens.borderSubtle
                            border.width: root.focusIndex === index ? 2 : 1
                            Row {
                                anchors.fill: parent
                                anchors.margins: 9
                                spacing: 8
                                Text {
                                    width: 23
                                    text: modelData.icon
                                    font.pixelSize: 18
                                    color: modelData.color
                                    horizontalAlignment: Text.AlignHCenter
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Column {
                                    width: parent.width - 31
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 3
                                    Text {
                                        text: modelData.label
                                        font.pixelSize: 11
                                        font.family: Tokens.fontSans
                                        color: Tokens.textPrimary
                                    }
                                    Text {
                                        width: parent.width
                                        text: root.currentValue(modelData.key)
                                        font.pixelSize: 16
                                        font.family: Tokens.fontMono
                                        color: modelData.color
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width
                                        text: root.deviceSubtitle(modelData)
                                        font.pixelSize: 8
                                        font.family: Tokens.fontMono
                                        color: Tokens.textDisabled
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                            Sparkline {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: 18
                                anchors.leftMargin: 9
                                anchors.rightMargin: 9
                                anchors.bottomMargin: 5
                                values: root.historyValues(modelData.key)
                                stroke: modelData.color
                                fill: Qt.rgba(modelData.color.r, modelData.color.g, modelData.color.b, 0.10)
                            }
                        }
                    }
                }
            }

            Column {
                width: parent.width - Math.max(210, Math.min(260, parent.width * 0.18)) - Tokens.sp3
                height: parent.height
                spacing: Tokens.sp2

                Row {
                    width: parent.width
                    height: 74
                    spacing: Tokens.sp3
                    Rectangle {
                        width: 180
                        height: parent.height
                        radius: Tokens.rMd
                        color: Tokens.bgElevated
                        border.color: root.devices[root.focusIndex].color
                        Text {
                            anchors { left: parent.left; top: parent.top; leftMargin: 14; topMargin: 10 }
                            text: root.devices[root.focusIndex].label
                            font.pixelSize: 11
                            font.family: Tokens.fontMono
                            color: Tokens.textSecondary
                        }
                        Text {
                            anchors { left: parent.left; bottom: parent.bottom; leftMargin: 14; bottomMargin: 9 }
                            text: root.currentValue(root.devices[root.focusIndex].key)
                            font.pixelSize: 25
                            font.family: Tokens.fontDisplay
                            color: root.devices[root.focusIndex].color
                        }
                    }
                    Rectangle {
                        width: parent.width - 180 - Tokens.sp3
                        height: parent.height
                        radius: Tokens.rMd
                        color: Tokens.bgElevated
                        Text {
                            anchors { left: parent.left; top: parent.top; leftMargin: 14; topMargin: 10 }
                            text: "DETAILS"
                            font.pixelSize: 10
                            font.family: Tokens.fontMono
                            color: Tokens.textDisabled
                        }
                        Text {
                            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 14; rightMargin: 14; topMargin: 30 }
                            text: root.deviceSubtitle(root.devices[root.focusIndex]) + "  ·  updated " + root.updated
                            font.pixelSize: 10
                            font.family: Tokens.fontMono
                            color: Tokens.textSecondary
                            elide: Text.ElideRight
                        }
                    }
                }

                Grid {
                    width: parent.width
                    height: parent.height - 74 - Tokens.sp2
                    columns: 2
                    rowSpacing: Tokens.sp2
                    columnSpacing: Tokens.sp2
                    Repeater {
                        model: root.graphSpecs()
                        delegate: GraphPanel {
                            width: (parent.width - Tokens.sp2) / 2
                            height: (parent.height - Tokens.sp2) / 2
                            spec: modelData
                            values: root.historyValues(modelData.key)
                            current: root.graphCurrent(modelData)
                        }
                    }
                }
            }
        }

        ControlHints {
            width: parent.width
            hints: [
                {button: "D-PAD", label: "Select device"},
                {button: "A", label: "Refresh"},
                {button: "B", label: "Home"}
            ]
        }
    }
}
