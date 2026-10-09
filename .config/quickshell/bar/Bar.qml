import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Services.SystemTray
import Quickshell.Bluetooth
import QtQuick
import qs.widgets
import qs

// Top bar (replaces waybar). Same HUD language as TelemetryHud.
//
//  left   : workspaces (sliding indicator) + focused window title
//  center : quote (fortune) + clock (click: calendar, right-click: date)
//  right  : media, volume, wifi, cpu, mem, battery, notifications, tray, power
//
// Workspace state comes from Compositor.qml (niri or Hyprland).
PanelWindow {
    id: bar

    anchors { top: true; left: true; right: true }
    implicitHeight: 36
    color: "transparent"

    exclusionMode: ExclusionMode.Auto
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-bar"

    // -------------------------
    // workspaces (Compositor.qml: niri or Hyprland)
    // -------------------------
    readonly property var workspaces: Compositor.workspaces.filter(function (w) {
        return !bar.screen || w.output === bar.screen.name
    })
    readonly property string windowTitle: Compositor.windowTitle
    readonly property string windowApp: Compositor.windowApp

    // -------------------------
    // Stats (cpu / mem / battery / wifi)
    // -------------------------
    property real cpu: 0
    property real mem: 0
    property int bat: -1
    property string batStatus: ""
    readonly property string ssid: Net.ssid       // Net.qml
    readonly property int signal: Net.signal
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

    readonly property string ethIface: Net.ethIface

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

    // Caffeine.qml: while on, tell the compositor we're not idle, so the
    // screensaver and lock (which respect inhibitors) stay away
    IdleInhibitor {
        window: bar
        enabled: Caffeine.on && bar.screen === Quickshell.screens[0]
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    // -------------------------
    // Inline components
    // -------------------------

    // "LABEL value" chip with optional mini gauge underneath (widgets/BarChip.qml)
    component Chip: BarChip { height: bar.implicitHeight }

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
                            onClicked: Compositor.focusWorkspace(modelData.idx)
                        }
                    }
                }
            }

            WheelHandler {
                onWheel: event => event.angleDelta.y > 0 ? Compositor.workspaceUp() : Compositor.workspaceDown()
            }
        }

        Divider {}

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            visible: bar.windowTitle !== ""

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

        // click = calendar (CalendarPanel.qml), right-click = show the date
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton)
                    clockItem.showDate = !clockItem.showDate
                else {
                    const cal = Modules.service("calendar")      // the calendar module
                    if (cal) cal.panelOpen = !cal.panelOpen
                }
            }
        }
    }

    // quote + skits left of the clock (Quote.qml)
    Quote {
        id: quote
        bar: bar
        clock: clock
        clockItem: clockItem
        leftRow: left
        tray: tray
        anchors.right: clockItem.left
        anchors.rightMargin: 18
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


        // volume: scroll = ±5%, click = sound dropdown (QuickPanel.qml), right = mute
        Chip {
            icon: bar.muted ? "󰝟" : bar.volume < 0.34 ? "󰕿" : bar.volume < 0.67 ? "󰖀" : "󰕾"
            value: bar.muted ? "" : Math.round(bar.volume * 100) + "%"
            gauge: bar.muted ? 0 : Math.min(1, bar.volume)
            accent: bar.muted ? Theme.danger : Theme.text
            onClicked: mouse => {
                if (mouse.button !== Qt.RightButton)
                    Quickshell.execDetached(["qs", "ipc", "call", "quick", "audio"])
                else if (bar.sink && bar.sink.audio)
                    bar.sink.audio.muted = !bar.sink.audio.muted
            }
            onWheel: wheel => {
                if (!bar.sink || !bar.sink.audio) return
                var v = bar.sink.audio.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05)
                bar.sink.audio.volume = Math.max(0, Math.min(1, v))
            }
        }


        // network: wifi when connected, else ethernet when wired, else disconnected
        // click = quick dropdown (QuickPanel.qml), right-click = settings
        Chip {
            readonly property bool wifi: bar.ssid !== ""
            readonly property bool wired: !wifi && bar.ethIface !== ""

            icon: wifi ? (bar.signal < 25 ? "󰤟" : bar.signal < 50 ? "󰤢" : bar.signal < 75 ? "󰤥" : "󰤨")
                : wired ? "󰈀" : "󰤮"
            value: wifi ? (bar.ssid.length > 12 ? bar.ssid.slice(0, 11) + "…" : bar.ssid) : ""
            gauge: wifi ? bar.signal / 100 : -1
            accent: wifi || wired ? Theme.text : Theme.danger
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
            icon: !adapter || !adapter.enabled ? "󰂲" : connected.length > 0 ? "󰂱" : "󰂯"
            // name only while something is connected
            value: adapter && adapter.enabled && connected.length > 0
                ? (n => n.length > 12 ? n.slice(0, 11) + "…" : n)(connected[0].name || "device")
                : ""
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

        // chips from active modules (Modules.qml, module.json "chip"), by their order
        Repeater {
            model: Modules.chips
            Loader {
                required property var modelData
                id: chipLoader
                anchors.verticalCenter: parent.verticalCenter
                // a chip that hides itself (no drive plugged in …) leaves no gap
                visible: item !== null && (item.shown === undefined || item.shown)
                Component.onCompleted: setSource(modelData.url, { service: Modules.service(modelData.id), bar: bar })
            }
        }





        // caffeine: keep awake (no screensaver, idle lock or idle suspend)
        Chip {
            icon: Caffeine.on ? "󰅶" : "󰛊"
            accent: Caffeine.on ? Theme.accent : Theme.textFaint
            onClicked: Caffeine.toggle()
        }

        Divider {}

        // cpu and ram; click either = HUD with the full graphs
        Chip {
            icon: "󰍛"
            value: Math.round(bar.cpu * 100) + "%"
            gauge: bar.cpu
            accent: bar.cpu > 0.9 ? Theme.danger : Theme.text
            onClicked: Quickshell.execDetached(["qs", "ipc", "call", "hud", "toggle"])
        }

        Chip {
            icon: "\uefc5"     // RAM stick (nf-fa-memory)
            value: Math.round(bar.mem * 100) + "%"
            gauge: bar.mem
            accent: bar.mem > 0.9 ? Theme.danger : Theme.text
            onClicked: Quickshell.execDetached(["qs", "ipc", "call", "hud", "toggle"])
        }

        Chip {
            visible: bar.bat >= 0
            icon: bar.batStatus === "Charging" ? "󰂄"
                : ["󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"][Math.round(bar.bat / 10)]
            value: bar.bat + "%"
            gauge: bar.bat / 100
            accent: bar.batStatus === "Charging" ? Theme.ok
                  : bar.bat <= 15 ? Theme.danger
                  : Theme.text
            // click = Settings > Power (battery details, profiles)
            onClicked: Quickshell.execDetached(["qs", "ipc", "call", "settings", "page", "Power"])
        }

        // power profile: only when power-profiles-daemon offers a choice.
        // click = next profile, right-click = Settings > Power
        Chip {
            visible: Power.available
            icon: Power.icons[Power.current]
            value: ""
            accent: Power.current === "performance" ? Theme.accent
                  : Power.current === "power-saver" ? Theme.ok
                  : Theme.text
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton)
                    Quickshell.execDetached(["qs", "ipc", "call", "settings", "page", "Power"])
                else
                    Power.cycle()
            }
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

        Divider { visible: tray.items.length > 0 }

        TrayMenu { id: trayMenu }

        // tray (apps listed in `hidden` keep running, just without an icon;
        // blueman stays for its pairing prompts, the BT chip replaces its icon)
        Row {
            id: tray
            readonly property var hidden: ["blueman"]
            readonly property var items: SystemTray.items.values.filter(i => hidden.indexOf(i.id) < 0)

            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            leftPadding: 6
            rightPadding: 6

            Repeater {
                id: trayRepeater
                model: tray.items

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
                                    // our own menu (TrayMenu.qml) instead of Qt's stock one
                                    trayMenu.open(it, bar, p.x, p.y)
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
