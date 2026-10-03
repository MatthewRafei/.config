import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Services.SystemTray
import Quickshell.Bluetooth
import QtQuick

// Top bar (replaces waybar). Same HUD language as TelemetryHud.
//
//  left   : niri workspaces (sliding indicator) + focused window title
//  center : quote (fortune) + clock (click for date)
//  right  : media, volume, wifi, cpu, mem, battery, notifications, tray, power
//
// Workspace state comes from `niri msg --json event-stream`; any event
// triggers a debounced re-query of workspaces + focused window, which is
// simpler and more robust than tracking every event type by hand.
PanelWindow {
    id: bar

    anchors { top: true; left: true; right: true }
    implicitHeight: 36
    color: "transparent"

    exclusionMode: ExclusionMode.Auto
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-bar"

    // -------------------------
    // niri
    // -------------------------
    property var workspaces: []
    property string windowTitle: ""
    property string windowApp: ""

    Process {
        id: niriEvents
        command: ["niri", "msg", "--json", "event-stream"]
        running: true
        stdout: SplitParser {
            onRead: niriDebounce.restart()
        }
        // niri restarted / socket dropped: reconnect
        onRunningChanged: if (!running) niriRetry.start()
    }

    Timer {
        id: niriRetry
        interval: 2000
        onTriggered: niriEvents.running = true
    }

    Timer {
        id: niriDebounce
        interval: 40
        onTriggered: if (!niriQuery.running) niriQuery.running = true
    }

    Process {
        id: niriQuery
        command: ["sh", "-c", "niri msg --json workspaces; echo; niri msg --json focused-window"]
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = text.split("\n").filter(function (l) { return l.trim() !== "" })
                try {
                    var ws = JSON.parse(parts[0])
                    ws.sort(function (a, b) { return a.idx - b.idx })
                    bar.workspaces = ws.filter(function (w) {
                        return !bar.screen || w.output === bar.screen.name
                    })
                } catch (e) {}
                try {
                    var win = JSON.parse(parts[1] || "null")
                    bar.windowTitle = win ? (win.title || "") : ""
                    bar.windowApp = win ? (win.app_id || "") : ""
                } catch (e) {
                    bar.windowTitle = ""
                    bar.windowApp = ""
                }
            }
        }
    }

    function niri(args) {
        Quickshell.execDetached(["niri", "msg", "action"].concat(args))
    }

    // -------------------------
    // Stats (cpu / mem / battery / wifi)
    // -------------------------
    property real cpu: 0
    property real mem: 0
    property int bat: -1
    property string batStatus: ""
    property string ssid: ""
    property int signal: 0
    property real _lastBusy: -1
    property real _lastIdle: -1

    Process {
        id: statProc
        command: [
            "sh",
            "-c",
            "read -r _ u n s i w q sq st _ < /proc/stat; " +
            "echo cpu $((u+n+s+q+sq+st)) $((i+w)); " +
            "awk '/^MemTotal/{t=$2} /^MemAvailable/{a=$2} END{print \"mem\", t, a}' /proc/meminfo; " +
            "for b in /sys/class/power_supply/BAT*; do " +
            "  [ -r $b/capacity ] && { echo bat $(cat $b/capacity) $(cat $b/status); break; }; " +
            "done"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var p = lines[i].trim().split(/\s+/)
                    if (p[0] === "cpu") {
                        var busy = +p[1], idle = +p[2]
                        if (bar._lastBusy >= 0) {
                            var db = busy - bar._lastBusy, di = idle - bar._lastIdle
                            bar.cpu = (db + di) > 0 ? db / (db + di) : 0
                        }
                        bar._lastBusy = busy
                        bar._lastIdle = idle
                    } else if (p[0] === "mem") {
                        bar.mem = +p[1] > 0 ? (+p[1] - +p[2]) / +p[1] : 0
                    } else if (p[0] === "bat") {
                        bar.bat = +p[1]
                        bar.batStatus = p[2] || ""
                    }
                }
            }
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: if (!statProc.running) statProc.running = true
    }

    Process {
        id: wifiProc
        command: ["sh", "-c", "nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi 2>/dev/null | grep '^yes' | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                // terse format: yes:<ssid>:<signal>; ssid itself may contain escaped colons
                var t = text.trim()
                if (!t) { bar.ssid = ""; bar.signal = 0; return }
                var last = t.lastIndexOf(":")
                bar.signal = +t.slice(last + 1)
                bar.ssid = t.slice(4, last).replace(/\\:/g, ":")
            }
        }
    }

    Timer {
        interval: 5000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: if (!wifiProc.running) wifiProc.running = true
    }

    // -------------------------
    // Audio / media
    // -------------------------
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volume: (sink && sink.audio) ? sink.audio.volume : 0
    readonly property bool muted: (sink && sink.audio) ? sink.audio.muted : false

    readonly property var player: {
        var ps = Mpris.players.values
        for (var i = 0; i < ps.length; i++)
            if (ps[i].isPlaying)
                return ps[i]
        return ps.length > 0 ? ps[0] : null
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    // -------------------------
    // Inline components
    // -------------------------

    // "LABEL value" chip with optional mini gauge underneath
    component Chip: Item {
        id: chip
        property string label
        property string value
        property real gauge: -1
        property color accent: Theme.text
        signal clicked(var mouse)
        signal wheel(var wheel)

        implicitWidth: chipRow.implicitWidth + 16
        height: bar.implicitHeight

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 6
            anchors.bottomMargin: 6
            radius: Theme.radius
            color: chipMouse.containsMouse ? Theme.bgCard : "transparent"
            border.color: chipMouse.containsMouse ? Theme.border : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }

        Row {
            id: chipRow
            anchors.centerIn: parent
            anchors.verticalCenterOffset: chip.gauge >= 0 ? -2 : 0
            spacing: 6
            Text {
                visible: chip.label !== ""
                anchors.baseline: valueText.baseline
                text: chip.label
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.letterSpacing: 2
            }
            Text {
                id: valueText
                text: chip.value
                color: chip.accent
                font.family: Theme.fontFamily
                font.pixelSize: 12
                Behavior on color { ColorAnimation { duration: Theme.animMed } }
            }
        }

        // 8-segment mini gauge
        Row {
            visible: chip.gauge >= 0
            anchors.horizontalCenter: chipRow.horizontalCenter
            anchors.top: chipRow.bottom
            anchors.topMargin: 2
            spacing: 1
            Repeater {
                model: 8
                Rectangle {
                    required property int index
                    width: (chipRow.width - 7) / 8
                    height: 2
                    color: index < Math.round(chip.gauge * 8)
                        ? (chip.accent === Theme.text ? Theme.accent : chip.accent)
                        : Theme.trackBg
                }
            }
        }

        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => chip.clicked(mouse)
            onWheel: wheel => chip.wheel(wheel)
        }
    }

    component Divider: Rectangle {
        width: 1
        height: 14
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        color: Theme.border
    }

    // -------------------------
    // Body
    // -------------------------
    Rectangle {
        anchors.fill: parent
        color: Theme.bgPanel

        // bottom hairline with a bright segment under the clock
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.border
        }
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: clockItem.width + 24
            height: 1
            color: Theme.accent
        }
    }

    // ---- left ----
    Row {
        id: left
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        Item {
            id: wsBox
            width: wsRow.width
            height: 22
            anchors.verticalCenter: parent.verticalCenter

            readonly property int activeIndex: {
                for (var i = 0; i < bar.workspaces.length; i++)
                    if (bar.workspaces[i].is_active)
                        return i
                return 0
            }

            // sliding active indicator
            Rectangle {
                id: wsIndicator
                x: wsBox.activeIndex * (26 + wsRow.spacing)
                width: 26
                height: parent.height
                radius: Theme.radius
                color: Theme.accent
                visible: bar.workspaces.length > 0
                Behavior on x { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }
            }

            Row {
                id: wsRow
                spacing: 4

                Repeater {
                    id: wsRepeater
                    model: bar.workspaces

                    Item {
                        required property var modelData
                        readonly property bool active: modelData.is_active
                        readonly property bool occupied: modelData.active_window_id !== null

                        width: 26
                        height: 22

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radius
                            color: "transparent"
                            border.width: 1
                            border.color: modelData.is_urgent ? Theme.danger
                                        : wsMouse.containsMouse && !parent.active ? Theme.borderAccent
                                        : "transparent"
                        }

                        Text {
                            anchors.centerIn: parent
                            text: (modelData.idx < 10 ? "0" : "") + modelData.idx
                            color: parent.active ? Theme.accentFg
                                 : parent.occupied ? Theme.text
                                 : Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: parent.active
                            Behavior on color { ColorAnimation { duration: Theme.animMed } }
                        }

                        // occupancy dot
                        Rectangle {
                            visible: parent.occupied && !parent.active
                            width: 3; height: 3; radius: 1.5
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 2
                            color: Theme.textDim
                        }

                        MouseArea {
                            id: wsMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: bar.niri(["focus-workspace", String(modelData.idx)])
                        }
                    }
                }
            }

            WheelHandler {
                onWheel: event => bar.niri([event.angleDelta.y > 0 ? "focus-workspace-up" : "focus-workspace-down"])
            }
        }

        Divider {}

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            visible: bar.windowTitle !== ""

            Text {
                anchors.baseline: titleText.baseline
                text: bar.windowApp.toUpperCase()
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.letterSpacing: 2
            }
            Text {
                id: titleText
                width: Math.min(implicitWidth, 260)
                elide: Text.ElideRight
                text: bar.windowTitle
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }
        }
    }

    // ---- center ----
    Item {
        id: clockItem
        anchors.centerIn: parent
        width: clockRow.implicitWidth
        height: parent.height

        property bool showDate: false

        Row {
            id: clockRow
            anchors.centerIn: parent
            spacing: 4

            Text {
                id: clockMain
                text: clockItem.showDate
                    ? Qt.formatDateTime(clock.date, "ddd dd MMM yyyy").toUpperCase()
                    : Qt.formatDateTime(clock.date, "hh:mm AP").split(" ")[0]
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.bold: true
                font.letterSpacing: 1
            }
            Text {
                visible: !clockItem.showDate
                anchors.baseline: clockMain.baseline
                text: Qt.formatDateTime(clock.date, ":ss")
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
            Text {
                visible: !clockItem.showDate
                anchors.baseline: clockMain.baseline
                text: Qt.formatDateTime(clock.date, "AP")
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 1
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: clockItem.showDate = !clockItem.showDate
        }
    }

    // quote: types out a short fortune left of the clock, ticker-scrolling
    // as it goes if it doesn't fit, then eases back to the start. New quote
    // every 5 minutes; click = next, hover = full quote in a popup.
    // Uses `fortune` if installed, else ~/.local/bin/fortune
    // (quotes live in ~/.config/quickshell/quotes/).
    Item {
        id: quote

        property string body: ""
        property string author: ""
        property int typed: 0
        property real restX: 0
        readonly property bool typing: typed < body.length
        readonly property real room: clockItem.x - (left.x + left.width) - 36

        anchors.right: clockItem.left
        anchors.rightMargin: 18
        height: bar.implicitHeight
        width: Math.max(0, Math.min(quoteRow.implicitWidth, room))
        visible: room > 100 && body !== ""
        clip: true

        function next() {
            if (!fortuneProc.running)
                fortuneProc.running = true
        }

        Process {
            id: fortuneProc
            command: ["sh", "-c", "fortune -s -n 110 2>/dev/null || \"$HOME/.local/bin/fortune\" -s -n 110"]
            stdout: StdioCollector {
                onStreamFinished: {
                    var lines = text.replace(/\t/g, " ").trim().split("\n")
                    var m = lines.length > 1 ? lines[lines.length - 1].match(/^\s*--\s*(.+)$/) : null
                    if (m)
                        lines.pop()
                    settle.stop()
                    quote.author = m ? m[1].trim() : ""
                    quote.body = lines.join(" ").replace(/\s+/g, " ").trim()
                    quote.typed = 0
                }
            }
        }

        Component.onCompleted: next()

        Timer {
            interval: 5 * 60 * 1000
            repeat: true
            running: true
            onTriggered: quote.next()
        }

        // typewriter
        Timer {
            interval: 28
            repeat: true
            running: quote.typing
            onTriggered: quote.typed++
            onRunningChanged: {
                // measure on the next frame, once the author text is laid out
                if (!running && quote.body !== "")
                    Qt.callLater(() => {
                        quote.restX = Math.min(0, quote.room - quoteRow.implicitWidth)
                        if (quote.restX < 0)
                            settle.restart()
                    })
            }
        }

        // after typing, hold on the ending, then glide back to the start
        SequentialAnimation {
            id: settle
            PauseAnimation { duration: 4000 }
            NumberAnimation {
                target: quote
                property: "restX"
                to: 0
                duration: Math.max(800, -quote.restX * 18)
                easing.type: Easing.InOutSine
            }
        }

        Row {
            id: quoteRow
            anchors.verticalCenter: parent.verticalCenter
            x: quote.typing ? Math.min(0, quote.room - implicitWidth) : quote.restX
            spacing: 6

            Text {
                text: "“"
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                id: quoteBody
                text: quote.body.slice(0, quote.typed)
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.italic: true
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: quote.typing
                text: "▌"
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: 11
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: !quote.typing && quote.author !== ""
                text: "— " + quote.author
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 10
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: quoteMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: quote.next()
        }
    }

    // full quote on hover
    PopupWindow {
        anchor.window: bar
        anchor.rect.x: quote.x + quote.width / 2 - implicitWidth / 2
        anchor.rect.y: bar.implicitHeight + 6
        implicitWidth: Math.min(420, quoteMetrics.width + 40)
        implicitHeight: popupCol.implicitHeight + 28
        visible: quoteMouse.containsMouse && quote.visible
        color: "transparent"

        TextMetrics {
            id: quoteMetrics
            font.family: Theme.fontFamily
            font.pixelSize: 12
            text: quote.body
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.bgPanel
            border.color: Theme.border
            radius: Theme.radius

            Rectangle {
                width: 2
                height: parent.height - 16
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.accent
            }

            Column {
                id: popupCol
                x: 22
                y: 14
                width: parent.width - 36
                spacing: 8

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: quote.body
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.italic: true
                }
                Text {
                    visible: quote.author !== ""
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                    text: "— " + quote.author
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.letterSpacing: 1
                }
            }
        }
    }

    // media: equalizer + title, click = play/pause, right = next.
    // Kept outside the right Row and squeezed into the room left between the
    // clock and the stats, so a long title can never run into the clock.
    Item {
        id: media
        readonly property real room: right.x - (clockItem.x + clockItem.width) - 24
        visible: bar.player !== null && bar.player.trackTitle !== "" && room > 80
        anchors.right: right.left
        anchors.rightMargin: 4
        width: Math.min(mediaRow.implicitWidth + 16, room)
        height: bar.implicitHeight

        Row {
            id: mediaRow
            anchors.centerIn: parent
            spacing: 8

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                height: 12
                Repeater {
                    model: 4
                    Rectangle {
                        required property int index
                        width: 2
                        anchors.bottom: parent.bottom
                        color: Theme.accent
                        height: 3
                        SequentialAnimation on height {
                            running: bar.player !== null && bar.player.isPlaying
                            loops: Animation.Infinite
                            NumberAnimation { to: 12; duration: 260 + index * 70; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 3; duration: 260 + index * 70; easing.type: Easing.InOutSine }
                        }
                    }
                }
            }

            Text {
                width: Math.min(implicitWidth, 240, media.room - 46)
                elide: Text.ElideRight
                text: bar.player
                    ? (bar.player.trackArtist ? bar.player.trackArtist + " — " : "") + bar.player.trackTitle
                    : ""
                color: bar.player && bar.player.isPlaying ? Theme.text : Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: -3
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 14
            color: Theme.border
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (!bar.player) return
                if (mouse.button === Qt.RightButton) {
                    if (bar.player.canGoNext) bar.player.next()
                } else if (bar.player.canTogglePlaying) {
                    bar.player.togglePlaying()
                }
            }
        }
    }

    // ---- right ----
    Row {
        id: right
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2


        // volume: scroll = ±5%, click = mute, right = pavucontrol
        Chip {
            label: "VOL"
            value: bar.muted ? "MUTE" : Math.round(bar.volume * 100) + "%"
            gauge: bar.muted ? 0 : Math.min(1, bar.volume)
            accent: bar.muted ? Theme.danger : Theme.text
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton)
                    Quickshell.execDetached(["pavucontrol"])
                else if (bar.sink && bar.sink.audio)
                    bar.sink.audio.muted = !bar.sink.audio.muted
            }
            onWheel: wheel => {
                if (!bar.sink || !bar.sink.audio) return
                var v = bar.sink.audio.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05)
                bar.sink.audio.volume = Math.max(0, Math.min(1, v))
            }
        }

        // wifi: click = quick dropdown (QuickPanel.qml), right-click = settings
        Chip {
            label: "NET"
            value: bar.ssid !== "" ? bar.ssid : "OFFLINE"
            gauge: bar.ssid !== "" ? bar.signal / 100 : -1
            accent: bar.ssid !== "" ? Theme.text : Theme.danger
            onClicked: mouse => Quickshell.execDetached(mouse.button === Qt.RightButton
                ? ["qs", "ipc", "call", "settings", "toggle"]
                : ["qs", "ipc", "call", "quick", "net"])
        }

        // bluetooth: click = quick dropdown, right-click = toggle power
        Chip {
            readonly property var adapter: Bluetooth.defaultAdapter
            readonly property var connected: adapter
                ? adapter.devices.values.filter(d => d.connected) : []

            visible: adapter !== null
            label: "BT"
            value: !adapter || !adapter.enabled ? "OFF"
                 : connected.length > 0 ? (connected[0].name || "1 DEVICE")
                 : "ON"
            accent: adapter && adapter.enabled && connected.length > 0 ? Theme.accent
                  : adapter && adapter.enabled ? Theme.text
                  : Theme.textFaint
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton && adapter)
                    adapter.enabled = !adapter.enabled
                else
                    Quickshell.execDetached(["qs", "ipc", "call", "quick", "bt"])
            }
        }

        Divider {}

        Chip {
            label: "CPU"
            value: (Math.round(bar.cpu * 100) < 10 ? "0" : "") + Math.round(bar.cpu * 100) + "%"
            gauge: bar.cpu
            accent: bar.cpu > 0.9 ? Theme.danger : Theme.text
            onClicked: Quickshell.execDetached(["qs", "ipc", "call", "hud", "toggle"])
        }

        Chip {
            label: "MEM"
            value: (Math.round(bar.mem * 100) < 10 ? "0" : "") + Math.round(bar.mem * 100) + "%"
            gauge: bar.mem
            accent: bar.mem > 0.9 ? Theme.danger : Theme.text
            onClicked: Quickshell.execDetached(["qs", "ipc", "call", "hud", "toggle"])
        }

        Chip {
            visible: bar.bat >= 0
            label: bar.batStatus === "Charging" ? "CHG" : "BAT"
            value: bar.bat + "%"
            gauge: bar.bat / 100
            accent: bar.batStatus === "Charging" ? Theme.ok
                  : bar.bat <= 15 ? Theme.danger
                  : Theme.text
        }

        // notifications: click = center, right-click = do not disturb
        Item {
            id: bell
            width: 30
            height: bar.implicitHeight

            Rectangle {
                anchors.fill: parent
                anchors.topMargin: 6
                anchors.bottomMargin: 6
                radius: Theme.radius
                color: Notifs.centerOpen ? Theme.alpha(Theme.accent, 0.15)
                     : bellMouse.containsMouse ? Theme.bgCard : "transparent"
                border.color: Notifs.centerOpen ? Theme.accent
                            : bellMouse.containsMouse ? Theme.border : "transparent"
            }

            Text {
                anchors.centerIn: parent
                text: Notifs.dnd ? "󰂛" : "󰂚"
                color: Notifs.dnd ? Theme.textFaint
                     : Notifs.count > 0 ? Theme.accent
                     : Theme.textDim
                font.family: Theme.iconFont
                font.pixelSize: 15
            }

            // count badge
            Rectangle {
                visible: Notifs.count > 0 && !Notifs.dnd
                x: parent.width - width - 2
                y: 6
                width: Math.max(12, badge.implicitWidth + 6)
                height: 12
                radius: 6
                color: Theme.accent
                Text {
                    id: badge
                    anchors.centerIn: parent
                    text: Notifs.count > 9 ? "9+" : Notifs.count
                    color: Theme.accentFg
                    font.family: Theme.fontFamily
                    font.pixelSize: 8
                    font.bold: true
                }
            }

            MouseArea {
                id: bellMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton)
                        Notifs.dnd = !Notifs.dnd
                    else
                        Notifs.centerOpen = !Notifs.centerOpen
                }
            }
        }

        Divider { visible: SystemTray.items.values.length > 0 }

        // tray
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            leftPadding: 6
            rightPadding: 6

            Repeater {
                model: SystemTray.items

                Item {
                    id: trayItem
                    required property var modelData
                    width: 22
                    height: 22

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radius
                        color: trayMouse.containsMouse ? Theme.bgCard : "transparent"
                        border.color: trayMouse.containsMouse ? Theme.border : "transparent"
                    }

                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 15
                        source: trayItem.modelData.icon
                    }

                    MouseArea {
                        id: trayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            var it = trayItem.modelData
                            if (mouse.button === Qt.MiddleButton) {
                                it.secondaryActivate()
                            } else if (mouse.button === Qt.RightButton || it.onlyMenu) {
                                if (it.hasMenu) {
                                    var p = trayItem.mapToItem(null, 0, trayItem.height + 6)
                                    it.display(bar, p.x, p.y)
                                }
                            } else {
                                it.activate()
                            }
                        }
                        onWheel: wheel => trayItem.modelData.scroll(wheel.angleDelta.y / 120, false)
                    }
                }
            }
        }

        Divider {}

        // power: opens the power menu (PowerMenu.qml)
        Item {
            id: power
            width: powerText.implicitWidth + 18
            height: bar.implicitHeight

            Rectangle {
                anchors.fill: parent
                anchors.topMargin: 6
                anchors.bottomMargin: 6
                radius: Theme.radius
                color: powerMouse.containsMouse ? Theme.bgCard : "transparent"
                border.color: powerMouse.containsMouse ? Theme.border : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
            }

            Text {
                id: powerText
                anchors.centerIn: parent
                text: "⏻"
                color: powerMouse.containsMouse ? Theme.danger : Theme.textDim
                font.family: Theme.iconFont
                font.pixelSize: 14
            }

            MouseArea {
                id: powerMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["qs", "ipc", "call", "power", "toggle"])
            }
        }
    }
}
