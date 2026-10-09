import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs
import qs.widgets

// Desktop telemetry HUD, pinned top-right on the Background layer next to the
// wallpaper. niri keeps it still across workspace switches via a layer-rule
// (place-within-backdrop) matching the "telemetry-hud" namespace, which only
// applies to Background surfaces that ignore exclusive zones; hence the
// larger top margin to clear waybar by hand.
//
//  - big clock with a chromatic glitch on every minute roll-over
//  - 60-tick seconds strip
//  - live CPU / MEM sparkline (last 60s)
//  - segmented gauges for CPU, MEM, TEMP, BAT
//
// Toggle it from niri, e.g. in config.kdl:
//   Mod+H { spawn "qs" "ipc" "call" "hud" "toggle"; }
PanelWindow {
    id: root
    property var service

    anchors { top: true; right: true }
    margins { top: 80; right: 28 }

    implicitWidth: 380
    implicitHeight: panel.implicitHeight + 40
    color: "transparent"

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "telemetry-hud"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    visible: showing || panel.visible

    property bool showing: true

    IpcHandler {
        target: "hud"
        function toggle(): void { root.showing = !root.showing }
        function show(): void { root.showing = true }
        function hide(): void { root.showing = false }
    }

    // -------------------------
    // Clock
    // -------------------------
    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    property int lastMinute: -1
    readonly property int minute: clock.date.getMinutes()
    onMinuteChanged: {
        if (lastMinute >= 0 && visible) {
            glitchAnim.restart()
            sweepAnim.restart()
        }
        lastMinute = minute
    }

    function isoWeek(d) {
        var t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
        var day = t.getUTCDay() || 7
        t.setUTCDate(t.getUTCDate() + 4 - day)
        var yearStart = new Date(Date.UTC(t.getUTCFullYear(), 0, 1))
        return Math.ceil(((t - yearStart) / 86400000 + 1) / 7)
    }

    function fmtUptime(s) {
        var d = Math.floor(s / 86400)
        var h = Math.floor((s % 86400) / 3600)
        var m = Math.floor((s % 3600) / 60)
        return (d > 0 ? d + "d " : "") + h + "h " + (m < 10 ? "0" : "") + m + "m"
    }

    // -------------------------
    // Telemetry sampling
    // -------------------------
    readonly property int histLen: 60

    property var cpuHist: []
    property var memHist: []

    // samples come from SysStats.qml (no shell forks); ask it for 1 s
    // samples while the HUD is up
    readonly property real cpu: SysStats.cpu
    readonly property real mem: SysStats.mem
    readonly property real memUsedGb: SysStats.memUsedGb
    readonly property real memTotalGb: SysStats.memTotalGb
    readonly property real temp: SysStats.temp
    readonly property int bat: SysStats.bat
    readonly property string batStatus: SysStats.batStatus
    readonly property real uptime: SysStats.uptime

    property bool _holdsFast: false
    function _syncFast() {
        if (visible === _holdsFast) return
        SysStats.fastUsers += visible ? 1 : -1
        _holdsFast = visible
    }
    onVisibleChanged: _syncFast()
    Component.onCompleted: _syncFast()
    Component.onDestruction: if (_holdsFast) SysStats.fastUsers--

    function pushHist(arr, v) {
        var a = arr.slice()
        a.push(v)
        while (a.length > histLen)
            a.shift()
        return a
    }

    Connections {
        target: SysStats
        enabled: root.visible
        function onSampled() {
            root.cpuHist = root.pushHist(root.cpuHist, SysStats.cpu)
            root.memHist = root.pushHist(root.memHist, SysStats.mem)
            spark.requestPaint()
        }
    }

    // -------------------------
    // Inline components
    // -------------------------

    // HUD-style segmented gauge
    component SegBar: Row {
        id: seg
        property real value: 0
        property color fillColor: Theme.text
        property int count: 24

        spacing: 2
        height: 6

        Repeater {
            model: seg.count
            Rectangle {
                required property int index
                readonly property bool lit: index < Math.round(seg.value * seg.count)

                width: (seg.width - seg.spacing * (seg.count - 1)) / seg.count
                height: seg.height
                color: lit ? seg.fillColor : Theme.trackBg
                opacity: lit ? 0.35 + 0.65 * ((index + 1) / seg.count) : 1

                Behavior on color { ColorAnimation { duration: Theme.animMed } }
            }
        }
    }

    component StatRow: Item {
        id: row
        property string label
        property string valueText
        property real value: 0
        property color accent: Theme.text

        width: parent ? parent.width : 0
        height: 30

        Text {
            id: lbl
            text: row.label
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.letterSpacing: 2
        }

        Text {
            anchors.right: parent.right
            anchors.baseline: lbl.baseline
            text: row.valueText
            color: row.accent
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.bold: true
        }

        SegBar {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            width: parent.width
            value: row.value
            fillColor: row.accent === Theme.text ? Theme.accent : row.accent
        }
    }

    component Corner: Item {
        property int hDir: 1   // 1 = bracket opens right, -1 = left
        property int vDir: 1   // 1 = bracket opens down, -1 = up
        width: 10
        height: 10
        Rectangle {
            width: parent.width; height: 1
            y: vDir > 0 ? 0 : parent.height - 1
            color: Theme.textDim
        }
        Rectangle {
            width: 1; height: parent.height
            x: hDir > 0 ? 0 : parent.width - 1
            color: Theme.textDim
        }
    }

    // -------------------------
    // Panel
    // -------------------------
    PerspectivePanel {
        id: panel

        open: root.showing
        tiltStrength: 4

        x: 20
        y: 20
        width: root.implicitWidth - 40
        implicitHeight: body.implicitHeight + 36
        height: implicitHeight

        Rectangle {
            id: card
            anchors.fill: parent
            color: Theme.bg
            border.color: Theme.border
            border.width: 1
            radius: Theme.radius
            clip: true

            // scanlines
            Canvas {
                anchors.fill: parent
                opacity: 0.6
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.fillStyle = "rgba(255,255,255,0.025)"
                    for (var y = 0; y < height; y += 3)
                        ctx.fillRect(0, y, width, 1)
                }
                onHeightChanged: requestPaint()
            }

            // slow sweeping highlight, one pass per minute roll-over (a
            // looping sweep kept the HUD rendering 60 fps around the clock)
            Rectangle {
                width: parent.width
                height: 60
                y: -60
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 0.5; color: Theme.alpha(Theme.text, 0.035) }
                    GradientStop { position: 1; color: "transparent" }
                }
                NumberAnimation on y {
                    id: sweepAnim
                    from: -60
                    to: card.height
                    duration: 5000
                    running: false
                }
            }
        }

        Corner { x: -4; y: -4; hDir: 1; vDir: 1 }
        Corner { x: parent.width - 6; y: -4; hDir: -1; vDir: 1 }
        Corner { x: -4; y: parent.height - 6; hDir: 1; vDir: -1 }
        Corner { x: parent.width - 6; y: parent.height - 6; hDir: -1; vDir: -1 }

        Column {
            id: body
            x: 18
            y: 18
            width: parent.width - 36
            spacing: 14

            // ---- header ----
            Item {
                width: parent.width
                height: 12

                Row {
                    spacing: 6
                    Rectangle {
                        width: 6; height: 6; radius: 3
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.ok
                        // blinks with the clock's seconds: one frame a second,
                        // which the seconds strip redraws anyway
                        opacity: clock.date.getSeconds() % 2 ? 0.25 : 1
                    }
                    Text {
                        text: "// TELEMETRY"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.letterSpacing: 2
                    }
                }

                Text {
                    anchors.right: parent.right
                    text: "UP " + root.fmtUptime(root.uptime)
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.letterSpacing: 1
                }
            }

            // ---- clock ----
            Item {
                width: parent.width
                height: clockText.height

                property real glitch: 0

                SequentialAnimation {
                    id: glitchAnim
                    NumberAnimation { target: clockText.parent; property: "glitch"; to: 1; duration: 40 }
                    NumberAnimation { target: clockText.parent; property: "glitch"; to: 0.2; duration: 60 }
                    NumberAnimation { target: clockText.parent; property: "glitch"; to: 1.4; duration: 40 }
                    NumberAnimation { target: clockText.parent; property: "glitch"; to: 0; duration: 420; easing.type: Easing.OutCubic }
                }

                Text {
                    x: -parent.glitch * 4
                    text: clockText.text
                    font: clockText.font
                    color: Theme.danger
                    opacity: Math.min(1, parent.glitch) * 0.8
                }
                Text {
                    x: parent.glitch * 3
                    y: parent.glitch * 1.5
                    text: clockText.text
                    font: clockText.font
                    color: Theme.ok
                    opacity: Math.min(1, parent.glitch) * 0.6
                }

                Text {
                    id: clockText
                    text: Qt.formatDateTime(clock.date, "hh:mm AP").split(" ")[0]
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 64
                    font.weight: Font.Light
                    font.letterSpacing: -2
                }

                Column {
                    anchors.left: clockText.right
                    anchors.leftMargin: 10
                    anchors.bottom: clockText.baseline
                    spacing: 2

                    Text {
                        text: Qt.formatDateTime(clock.date, "AP")
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                        font.letterSpacing: 1
                    }
                    Text {
                        text: Qt.formatDateTime(clock.date, "ss")
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 20
                    }
                }

                Column {
                    anchors.right: parent.right
                    anchors.bottom: clockText.baseline
                    spacing: 3

                    Text {
                        anchors.right: parent.right
                        text: Qt.formatDateTime(clock.date, "dddd").toUpperCase()
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.letterSpacing: 2
                    }
                    Text {
                        anchors.right: parent.right
                        text: Qt.formatDateTime(clock.date, "dd MMM yyyy").toUpperCase()
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.letterSpacing: 1
                    }
                    Text {
                        anchors.right: parent.right
                        text: "W" + root.isoWeek(clock.date)
                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.letterSpacing: 1
                    }
                }
            }

            // ---- seconds strip ----
            Row {
                id: secStrip
                width: parent.width
                height: 8
                spacing: 1
                readonly property int sec: clock.date.getSeconds()

                Repeater {
                    model: 60
                    Rectangle {
                        required property int index
                        width: (secStrip.width - 59) / 60
                        height: index % 5 === 0 ? 8 : 5
                        y: secStrip.height - height
                        color: index === secStrip.sec ? Theme.accent
                             : index < secStrip.sec ? Theme.textFaint
                             : Theme.trackBg
                    }
                }
            }

            // ---- sparkline ----
            // legend in its own strip above the graph, so a high line can't
            // run over the labels
            Item {
                width: parent.width
                height: 12

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Text {
                        text: "━ CPU"
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.letterSpacing: 1
                    }
                    Text {
                        text: "━ MEM"
                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.letterSpacing: 1
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: "60s"
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                }
            }

            Item {
                width: parent.width
                height: 64

                Canvas {
                    id: spark
                    anchors.fill: parent

                    Connections {
                        target: Theme
                        function onAccentChanged() { spark.requestPaint() }
                    }

                    function plot(ctx, data, n) {
                        var step = width / (n - 1)
                        var off = n - data.length
                        for (var i = 0; i < data.length; i++) {
                            var x = (off + i) * step
                            var y = height - 2 - data[i] * (height - 4)
                            if (i === 0) ctx.moveTo(x, y)
                            else ctx.lineTo(x, y)
                        }
                    }

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        var w = width, h = height, n = root.histLen

                        // grid
                        ctx.strokeStyle = Theme.css(Theme.border, 0.8)
                        ctx.lineWidth = 1
                        ctx.beginPath()
                        for (var g = 1; g < 4; g++) {
                            var gy = Math.round(h * g / 4) + 0.5
                            ctx.moveTo(0, gy); ctx.lineTo(w, gy)
                        }
                        for (var v = 1; v < 6; v++) {
                            var gx = Math.round(w * v / 6) + 0.5
                            ctx.moveTo(gx, 0); ctx.lineTo(gx, h)
                        }
                        ctx.stroke()

                        var cpu = root.cpuHist, mem = root.memHist
                        if (cpu.length < 2)
                            return

                        // mem: dim line
                        ctx.beginPath()
                        plot(ctx, mem, n)
                        ctx.strokeStyle = Theme.css(Theme.text, 0.28)
                        ctx.lineWidth = 1
                        ctx.stroke()

                        // cpu: filled area + bright line
                        ctx.beginPath()
                        plot(ctx, cpu, n)
                        ctx.lineTo(w, h)
                        ctx.lineTo((n - cpu.length) * w / (n - 1), h)
                        ctx.closePath()
                        var grad = ctx.createLinearGradient(0, 0, 0, h)
                        grad.addColorStop(0, Theme.css(Theme.accent, 0.28))
                        grad.addColorStop(1, Theme.css(Theme.accent, 0))
                        ctx.fillStyle = grad
                        ctx.fill()

                        ctx.beginPath()
                        plot(ctx, cpu, n)
                        ctx.strokeStyle = Theme.css(Theme.accent, 1)
                        ctx.lineWidth = 1.5
                        ctx.stroke()

                        // head dot
                        var hy = h - 2 - cpu[cpu.length - 1] * (h - 4)
                        ctx.fillStyle = Theme.css(Theme.accent, 1)
                        ctx.beginPath()
                        ctx.arc(w - 2, hy, 2.5, 0, Math.PI * 2)
                        ctx.fill()
                    }
                }
            }

            // ---- gauges ----
            Column {
                width: parent.width
                spacing: 4

                StatRow {
                    label: "CPU"
                    value: root.cpu
                    valueText: Math.round(root.cpu * 100) + "%"
                    accent: root.cpu > 0.9 ? Theme.danger : Theme.text
                }
                StatRow {
                    label: "MEM"
                    value: root.mem
                    valueText: root.memUsedGb.toFixed(1) + " / " + root.memTotalGb.toFixed(1) + " GiB"
                    accent: root.mem > 0.9 ? Theme.danger : Theme.text
                }
                StatRow {
                    visible: root.temp >= 0
                    label: "TEMP"
                    value: Math.min(1, root.temp / 100)
                    valueText: Math.round(root.temp) + "°C"
                    accent: root.temp >= 85 ? Theme.danger : Theme.text
                }
                StatRow {
                    visible: root.bat >= 0
                    label: "PWR · " + root.batStatus.toUpperCase()
                    value: root.bat / 100
                    valueText: root.bat + "%"
                    accent: root.batStatus === "Charging" ? Theme.ok
                          : root.bat <= 15 ? Theme.danger
                          : Theme.text
                }
            }
        }
    }
}
