import QtQuick
import Quickshell.Io
import "../"

Item {
    id: page

    property var monitors: []
    property int rightMargin: 36

    // -------------------------
    // Brightness
    // -------------------------
    property real brightnessValue: 0.6

    Process {
        id: brightnessGet

        command: ["brightnessctl", "-m"]

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(",")

                if (parts.length < 4)
                    return

                const pct = parseInt(parts[3])

                if (!isNaN(pct))
                    page.brightnessValue = pct / 100
            }
        }
    }

    Process {
        id: brightnessSet

        stdout: StdioCollector {}
        stderr: StdioCollector {}
    }

    function commitBrightness(value) {
        brightnessSet.command = [
            "brightnessctl",
            "set",
            Math.round(value * 100) + "%"
        ]

        brightnessSet.running = true
    }

    // Night light state and schedule live in ../NightLight.qml (always running).

    // -------------------------
    // Monitor helpers (niri)
    // -------------------------
    // Monitors come from `niri msg --json outputs`; changes go through
    // `niri msg output <name> ...` (runtime only, like niri's own keybinds;
    // they reset to config.kdl on restart). niri can't mirror outputs, so
    // there is no DUPLICATE mode.
    function isInternalMonitor(mon) {
        return mon.name.indexOf("eDP") === 0
            || mon.name.indexOf("LVDS") === 0
    }

    function findMonitors() {
        let internal = null
        let external = null

        for (let i = 0; i < page.monitors.length; i++) {
            const mon = page.monitors[i]

            if (isInternalMonitor(mon)) {
                internal = mon
            } else if (!external) {
                external = mon
            }
        }

        return {
            internal: internal,
            external: external
        }
    }

    // -------------------------
    // Monitor list
    // -------------------------
    Process {
        id: pList

        command: ["sh", "-c", "niri msg --json outputs; echo; niri msg --json focused-output"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("\n").filter(l => l.trim() !== "")

                try {
                    const outputs = JSON.parse(parts[0])
                    let focused = null
                    try { focused = JSON.parse(parts[1] || "null") } catch (e) {}

                    const list = []
                    for (const name in outputs) {
                        const o = outputs[name]
                        const mode = (o.current_mode !== null && o.current_mode !== undefined)
                            ? o.modes[o.current_mode]
                            : (o.modes[0] || { width: 0, height: 0, refresh_rate: 0 })
                        const l = o.logical

                        list.push({
                            name: name,
                            description: ((o.make || "") + " " + (o.model || "")).trim(),
                            width: mode.width,
                            height: mode.height,
                            refreshRate: mode.refresh_rate / 1000,
                            enabled: l !== null,
                            x: l ? l.x : 0,
                            y: l ? l.y : 0,
                            scale: l ? l.scale : 1,
                            logicalWidth: l ? l.width : mode.width,
                            focused: focused !== null && focused.name === name
                        })
                    }

                    list.sort((a, b) => a.x - b.x)
                    page.monitors = list
                } catch (error) {
                    console.log("Failed to parse niri outputs:", error)
                    page.monitors = []
                }
            }
        }
    }

    function refresh() {
        pList.running = true
    }

    // -------------------------
    // Applying changes
    // -------------------------
    Process {
        id: pMode

        stderr: StdioCollector {
            onStreamFinished: {
                const output = text.trim()
                if (output !== "")
                    console.log("niri output ERROR:", output)
            }
        }

        onExited: refreshTimer.restart()
    }

    Timer {
        id: refreshTimer
        interval: 250
        repeat: false
        onTriggered: page.refresh()
    }

    function shq(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'"
    }

    // run `niri msg output ...` commands in order, then refresh the list
    function runOutputs(cmds) {
        pMode.command = ["sh", "-c", cmds.map(c => "niri msg output " + c).join(" && ")]
        pMode.running = true
    }

    function setScale(mon, scale) {
        runOutputs([shq(mon.name) + " scale " + scale.toFixed(2)])
    }

    // -------------------------
    // Monitor modes
    // -------------------------
    function applyMonitorMode(mode) {
        const displays = findMonitors()
        const internal = displays.internal
        const external = displays.external

        if (!internal || !external) {
            page.refresh()
            return
        }

        const I = shq(internal.name)
        const E = shq(external.name)

        if (mode === "first") {
            runOutputs([I + " on", I + " position set 0 0", E + " off"])
        } else if (mode === "second") {
            runOutputs([E + " on", E + " position set 0 0", I + " off"])
        } else if (mode === "extend") {
            // external on the left, laptop panel to its right
            const extWidth = Math.round(external.width / (external.enabled ? external.scale : 1))
            runOutputs([
                E + " on",
                I + " on",
                E + " position set 0 0",
                I + " position set " + extWidth + " 0"
            ])
        }
    }

    // -------------------------
    // Page
    // -------------------------
    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: page.rightMargin
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: 20

        // -------------------------
        // Header
        // -------------------------
        Row {
            width: parent.width

            Text {
                text: "MONITORS"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 18
                font.bold: true
                font.letterSpacing: 3
            }

            Item {
                width: parent.width - 150
                height: 1
            }

            Text {
                text: "󰑐"
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: 22

                MouseArea {
                    anchors.fill: parent
                    onClicked: page.refresh()
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.border
        }

        // -------------------------
        // MONITOR MODE
        // -------------------------
        Column {
            // nothing to choose between with a single display
            visible: page.monitors.length > 1
            width: parent.width
            spacing: 10

            Text {
                text: "MONITOR MODE"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.bold: true
                font.letterSpacing: 2
            }

            Row {
                width: parent.width
                spacing: 10

                Repeater {
                    model: [
                        { name: "FIRST", mode: "first" },
                        { name: "SECOND", mode: "second" },
                        { name: "EXTEND", mode: "extend" }
                    ]

                    delegate: Rectangle {
                        required property var modelData

                        width:
                            (
                                parent.width -
                                parent.spacing * 2
                            ) / 3

                        height: 42
                        radius: Theme.radius
                        color: "#00000000"
                        border.width: 1
                        border.color: Theme.border

                        Text {
                            anchors.centerIn: parent
                            text: modelData.name
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.bold: true
                            font.letterSpacing: 1
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true

                            onEntered: {
                                parent.color =
                                    Theme.alpha(
                                        Theme.accent,
                                        0.08
                                    )

                                parent.border.color =
                                    Theme.accent
                            }

                            onExited: {
                                parent.color = "#00000000"
                                parent.border.color = Theme.border
                            }

                            onClicked: {
                                console.log(
                                    "BUTTON CLICKED:",
                                    modelData.name,
                                    modelData.mode
                                )

                                page.applyMonitorMode(
                                    modelData.mode
                                )
                            }
                        }
                    }
                }
            }
        }

        // -------------------------
        // BRIGHTNESS
        // -------------------------
        Item {
            width: parent.width
            height: 58

            Slider {
                anchors.fill: parent

                label: "BRIGHTNESS"
                icon: "\uf185"
                value: page.brightnessValue
                accentColor: Theme.accent2

                onCommitted: (value) =>
                    page.commitBrightness(value)
            }
        }

        // -------------------------
        // NIGHT LIGHT
        // -------------------------
        Item {
            width: parent.width
            height: 58

            property int controlMargin: 25

            Row {
                anchors.fill: parent
                spacing: parent.controlMargin

                Slider {
                    width:
                        parent.width -
                        70 -
                        parent.spacing

                    height: parent.height

                    label: "NIGHT LIGHT  ·  " + NightLight.temperature + "K"
                    icon: ""
                    value: NightLight.value
                    accentColor: Theme.accent

                    onMoved: (value) =>
                        NightLight.value = value
                }

                Rectangle {
                    width: 70
                    height: 36
                    radius: Theme.radius
                    anchors.verticalCenter: parent.verticalCenter

                    color:
                        NightLight.active
                            ? Theme.alpha(Theme.accent, 0.1)
                            : Theme.alpha("#A0A0A0", 0.15)

                    border.width: 1
                    border.color: NightLight.active ? Theme.accent : "#A0A0A0"

                    Text {
                        anchors.centerIn: parent
                        text: NightLight.active ? "ON" : "OFF"
                        color: NightLight.active ? Theme.accent : "#A0A0A0"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: NightLight.toggle()
                    }
                }
            }
        }

        // -------------------------
        // NIGHT LIGHT SCHEDULE
        // -------------------------
        Column {
            width: parent.width
            spacing: 12

            // mode selector + status
            Item {
                width: parent.width
                height: 28

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 96
                        text: "SCHEDULE"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.letterSpacing: 2
                    }

                    Repeater {
                        model: [
                            { mode: "manual", label: "MANUAL" },
                            { mode: "sun",    label: "SUNSET" },
                            { mode: "custom", label: "CUSTOM" }
                        ]

                        Rectangle {
                            required property var modelData
                            readonly property bool selected: NightLight.mode === modelData.mode

                            width: modeText.implicitWidth + 22
                            height: 26
                            radius: Theme.radius
                            color: selected ? Theme.alpha(Theme.accent, 0.12)
                                 : modeMouse.containsMouse ? Theme.bgCard : "transparent"
                            border.width: 1
                            border.color: selected ? Theme.accent : Theme.border

                            Text {
                                id: modeText
                                anchors.centerIn: parent
                                text: modelData.label
                                color: parent.selected ? Theme.accent : Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.letterSpacing: 2
                                font.bold: parent.selected
                            }

                            MouseArea {
                                id: modeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: NightLight.mode = modelData.mode
                            }
                        }
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: NightLight.status
                    color: NightLight.active ? Theme.accent : Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.letterSpacing: 2
                }
            }

            // sunset mode: show today's times
            Row {
                visible: NightLight.mode === "sun"
                x: 102
                spacing: 18

                Repeater {
                    model: [
                        { label: "SUNSET",  min: NightLight.sun.set },
                        { label: "SUNRISE", min: NightLight.sun.rise }
                    ]
                    Row {
                        required property var modelData
                        spacing: 8
                        Text {
                            text: modelData.label
                            color: Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.letterSpacing: 2
                            anchors.baseline: sunTime.baseline
                        }
                        Text {
                            id: sunTime
                            text: NightLight.fmt(modelData.min)
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                    }
                }
            }

            // custom mode: start/end pickers (± 15 min, or scroll)
            Row {
                visible: NightLight.mode === "custom"
                x: 102
                spacing: 22

                Repeater {
                    model: [
                        { label: "FROM", key: "start" },
                        { label: "TO",   key: "end" }
                    ]

                    Row {
                        id: picker
                        required property var modelData
                        readonly property int minutes: NightLight[modelData.key]
                        spacing: 8

                        function shift(delta) {
                            NightLight[modelData.key] = ((minutes + delta) % 1440 + 1440) % 1440
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 38
                            text: picker.modelData.label
                            color: Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.letterSpacing: 2
                        }

                        Repeater {
                            model: ["−", "time", "+"]

                            Rectangle {
                                required property string modelData
                                readonly property bool isTime: modelData === "time"

                                width: isTime ? 92 : 26
                                height: 26
                                radius: Theme.radius
                                color: !isTime && stepMouse.containsMouse ? Theme.bgCard : "transparent"
                                border.width: 1
                                border.color: !isTime && stepMouse.containsMouse ? Theme.accent : Theme.border

                                Text {
                                    anchors.centerIn: parent
                                    text: parent.isTime ? NightLight.fmt(picker.minutes) : parent.modelData
                                    color: parent.isTime ? Theme.text : Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: parent.isTime ? 12 : 13
                                }

                                MouseArea {
                                    id: stepMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: parent.isTime ? Qt.SizeVerCursor : Qt.PointingHandCursor
                                    onClicked: {
                                        if (parent.modelData === "−") picker.shift(-15)
                                        else if (parent.modelData === "+") picker.shift(15)
                                    }
                                    onWheel: wheel => picker.shift(wheel.angleDelta.y > 0 ? 15 : -15)
                                }
                            }
                        }
                    }
                }
            }
        }

        // -------------------------
        // MONITOR LIST
        // -------------------------
        Column {
            width: parent.width
            spacing: 16

            Repeater {
                model: page.monitors

                delegate: Rectangle {
                    required property var modelData

                    width: parent.width
                    height: 100
                    radius: Theme.radius
                    color: "#00000000"
                    border.width: 1
                    border.color:
                        modelData.focused
                            ? "#454545"
                            : Theme.border

                    Column {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 8

                        Row {
                            spacing: 10

                            Text {
                                text: modelData.name
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                font.bold: true
                            }

                            Text {
                                text:
                                    modelData.width +
                                    "x" +
                                    modelData.height +
                                    " @ " +
                                    Math.round(
                                        modelData.refreshRate
                                    ) +
                                    "Hz"

                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }

                            Text {
                                visible: modelData.focused
                                text: "ACTIVE"
                                color: Theme.accent2
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                            }
                        }

                        Slider {
                            width: parent.width

                            label:
                                "SCALE (" +
                                modelData.scale.toFixed(2) +
                                "x)"

                            icon: "\uf00e"

                            value:
                                (
                                    modelData.scale - 0.5
                                ) / 1.5

                            onCommitted: (value) =>
                                page.setScale(
                                    modelData,
                                    0.5 + value * 1.5
                                )
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        brightnessGet.running = true
    }
}
