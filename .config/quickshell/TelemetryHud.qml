import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import QtQuick

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
//  - MPRIS now-playing strip with controls (only when a player exists)
//
// Toggle it from niri, e.g. in config.kdl:
//   Mod+H { spawn "qs" "ipc" "call" "hud" "toggle"; }
PanelWindow {
    id: root

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
        if (lastMinute >= 0)
            glitchAnim.restart()
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

    property real cpu: 0
    property real mem: 0
    property real memUsedGb: 0
    property real memTotalGb: 0
    property real temp: -1
    property int bat: -1
    property string batStatus: ""
    property real uptime: 0

    property real _lastBusy: -1
    property real _lastIdle: -1

    function pushHist(arr, v) {
        var a = arr.slice()
        a.push(v)
        while (a.length > histLen)
            a.shift()
        return a
    }

    function ingest(text) {
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
            var p = lines[i].trim().split(/\s+/)
            switch (p[0]) {
            case "cpu":
                var busy = +p[1], idle = +p[2]
                if (_lastBusy >= 0) {
                    var db = busy - _lastBusy, di = idle - _lastIdle
                    cpu = (db + di) > 0 ? db / (db + di) : 0
                }
                _lastBusy = busy
                _lastIdle = idle
                break
            case "mem":
                var total = +p[1], avail = +p[2]
                mem = total > 0 ? (total - avail) / total : 0
                memUsedGb = (total - avail) / 1048576
                memTotalGb = total / 1048576
                break
            case "temp":
                temp = +p[1] / 1000
                break
            case "bat":
                bat = +p[1]
                batStatus = p[2] || ""
                break
            case "up":
                uptime = +p[1]
                break
            }
        }
        cpuHist = pushHist(cpuHist, cpu)
        memHist = pushHist(memHist, mem)
        spark.requestPaint()
    }

    Process {
        id: statProc

        command: [
            "sh",
            "-c",
            "read -r _ u n s i w q sq st _ < /proc/stat; " +
            "echo cpu $((u+n+s+q+sq+st)) $((i+w)); " +
            "awk '/^MemTotal/{t=$2} /^MemAvailable/{a=$2} END{print \"mem\", t, a}' /proc/meminfo; " +
            "for h in /sys/class/hwmon/hwmon*; do " +
            "  [ \"$(cat $h/name 2>/dev/null)\" = coretemp ] && { echo temp $(cat $h/temp1_input); break; }; " +
            "done; " +
            "for b in /sys/class/power_supply/BAT*; do " +
            "  [ -r $b/capacity ] && { echo bat $(cat $b/capacity) $(cat $b/status); break; }; " +
            "done; " +
            "read -r up _ < /proc/uptime; echo up ${up%.*}"
        ]

        stdout: StdioCollector {
            onStreamFinished: root.ingest(text)
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: if (!statProc.running) statProc.running = true
    }

    // -------------------------
    // Media
    // -------------------------
    readonly property var player: {
        var ps = Mpris.players.values
        for (var i = 0; i < ps.length; i++)
            if (ps[i].isPlaying)
                return ps[i]
        return ps.length > 0 ? ps[0] : null
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.visible && root.player !== null && root.player.isPlaying
        onTriggered: root.player.positionChanged()
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

    component MediaButton: Text {
        id: mb
        signal clicked()
        font.family: Theme.iconFont
        font.pixelSize: 16
        color: ma.containsMouse ? Theme.text : Theme.textDim
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        scale: ma.pressed ? 0.85 : 1
        Behavior on scale { NumberAnimation { duration: Theme.animFast } }
        MouseArea {
            id: ma
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: mb.clicked()
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

            // slow sweeping highlight
            Rectangle {
                width: parent.width
                height: 60
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 0.5; color: Theme.alpha(Theme.text, 0.035) }
                    GradientStop { position: 1; color: "transparent" }
                }
                NumberAnimation on y {
                    from: -60
                    to: card.height
                    duration: 5000
                    loops: Animation.Infinite
                    running: root.visible
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
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: root.visible
                            NumberAnimation { to: 0.2; duration: 900; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                        }
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
            Item {
                width: parent.width
                height: 74

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

                Row {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 4
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
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 4
                    text: "60s"
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
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

            // ---- media ----
            Item {
                visible: root.player !== null
                width: parent.width
                height: visible ? media.implicitHeight : 0

                Column {
                    id: media
                    width: parent.width
                    spacing: 8

                    Rectangle { width: parent.width; height: 1; color: Theme.border }

                    Item {
                        width: parent.width
                        height: 34

                        Column {
                            anchors.left: parent.left
                            anchors.right: controls.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3

                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: root.player ? (root.player.trackTitle || "Unknown") : ""
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: root.player ? (root.player.trackArtist || root.player.identity).toUpperCase() : ""
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.letterSpacing: 1
                            }
                        }

                        Row {
                            id: controls
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 14

                            MediaButton {
                                text: "󰒮"
                                onClicked: if (root.player && root.player.canGoPrevious) root.player.previous()
                            }
                            MediaButton {
                                text: root.player && root.player.isPlaying ? "󰏤" : "󰐊"
                                color: Theme.text
                                onClicked: if (root.player && root.player.canTogglePlaying) root.player.togglePlaying()
                            }
                            MediaButton {
                                text: "󰒭"
                                onClicked: if (root.player && root.player.canGoNext) root.player.next()
                            }
                        }
                    }

                    // progress
                    Rectangle {
                        visible: root.player !== null && root.player.positionSupported && root.player.length > 0
                        width: parent.width
                        height: 2
                        color: Theme.trackBg
                        Rectangle {
                            height: parent.height
                            color: Theme.text
                            width: root.player && root.player.length > 0
                                ? parent.width * Math.min(1, root.player.position / root.player.length)
                                : 0
                        }
                    }
                }
            }
        }
    }
}
