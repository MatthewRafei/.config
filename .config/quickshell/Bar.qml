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

    // "LABEL value" chip with optional mini gauge underneath
    component Chip: Item {
        id: chip
        property string label
        property string icon            // shown instead of `label` when set
        property string value
        property real gauge: -1
        property color accent: Theme.text
        signal clicked(var mouse)
        signal wheel(var wheel)

        implicitWidth: chipRow.implicitWidth + 14
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
                visible: chip.icon !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: chip.icon
                color: chip.accent === Theme.text ? Theme.textDim : chip.accent
                font.family: Theme.iconFont
                font.pixelSize: 14
            }
            Text {
                visible: chip.label !== "" && chip.icon === ""
                anchors.baseline: valueText.baseline
                text: chip.label
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.letterSpacing: 2
            }
            Text {
                id: valueText
                visible: chip.value !== ""
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
                else
                    Calendar.panelOpen = !Calendar.panelOpen
            }
        }
    }

    // quote: types out a short fortune left of the clock, ticker-scrolling
    // as it goes if it doesn't fit, then eases back to the start and from
    // there scrolls on repeat like a news ticker (pauses under the mouse). New quote
    // every 5 minutes; click = next, hover = full quote in a popup.
    // Now and then (1 in 3 changes, or `qs ipc call bar peek`) a little skit
    // decodes in instead: a face peeking left and right, dozing off, flipping
    // a table, praising the sun, dancing, hacking, shrugging, a cat, a YOU
    // DIED, Pac-Man, a bonfire, a Naruto run, a domain expansion, a
    // Factorio belt... then it dissolves and the next quote types in.
    // `qs ipc call bar skit <name>` plays a given one.
    // Uses `fortune` if installed, else ~/.local/bin/fortune
    // (quotes live in ~/.config/quickshell/quotes/).
    Item {
        id: quote

        property string body: ""
        property string author: ""
        property int typed: 0
        property real restX: 0
        property bool ticker: false      // long quote, after the glide back: scrolling on repeat
        property real tickX: 0

        function stopTicker() {
            settle.stop()
            tickerLoop.stop()
            ticker = false
        }
        readonly property bool typing: typed < body.length
        readonly property real room: clockItem.x - (left.x + left.width) - 36

        anchors.right: clockItem.left
        anchors.rightMargin: 18
        height: bar.implicitHeight
        // while a skit plays, hold the width of its longest frame so the
        // characters move instead of the whole line shifting
        width: Math.max(0, Math.min(peeking ? Math.max(faceRow.implicitWidth, faceMetrics.advanceWidth + 20)
                                            : quoteRow.implicitWidth, room))
        visible: room > 100 && (body !== "" || peeking)
        clip: true

        // ---------------- peeking face ----------------
        property bool peeking: false
        property string face: ""
        property bool sparkle: false
        property var frames: []
        property int frameIdx: 0

        function scrambled(target, revealed) {
            const noise = "▓▒░#%&@*"
            let out = ""
            for (let i = 0; i < target.length; i++)
                out += i < revealed || target[i] === " " ? target[i] : noise[Math.floor(Math.random() * noise.length)]
            return out
        }

        function dissolve(from) {
            // each char goes to · then away, in random order
            const steps = []
            let cur = from.split("")
            const order = cur.map((c, i) => i).filter(i => cur[i] !== " ").sort(() => Math.random() - 0.5)
            for (const i of order) { cur[i] = "·"; steps.push({ t: cur.join(""), ms: 45 }) }
            for (const i of order) { cur[i] = " "; steps.push({ t: cur.join(""), ms: 40 }) }
            return steps
        }

        // a skit: frames { t: text, ms: how long, sparkle?, color? }. The
        // first frame decodes in, the last one dissolves away.
        function play(core, force) {
            if (peeking && !force) return
            faceTimer.stop()
            quote.stopTicker()
            let f = []
            const first = core[0].t
            for (let k = 0; k <= first.length; k++) f.push({ t: scrambled(first, k), ms: 45 })
            frames = f.concat(core).concat(dissolve(core[core.length - 1].t))
            faceMetrics.text = core.reduce((a, fr) => fr.t.length > a.length ? fr.t : a, "")
            frameIdx = 0
            face = frames[0].t
            faceColor = ""
            sparkle = false
            peeking = true
            faceTimer.interval = frames[0].ms
            faceTimer.restart()
        }

        property string faceColor: ""   // "" = accent, or "danger" / "accent2" / "dim"

        readonly property var skits: ({
            // looks left and right, smiles
            peek: () => [
                { t: "( ◕_◕ )", ms: 700 },
                { t: "( -_- )", ms: 110 },
                { t: "( ◕_◕ )", ms: 350 },
                { t: "(◕_◕  )", ms: 750 },
                { t: "(  ◕_◕)", ms: 750 },
                { t: "( ◕_◕ )", ms: 450 },
                { t: "( ◕‿◕ )", ms: 500 },
                { t: "( ^‿^ )", ms: 1100, sparkle: true }
            ],
            // dozes off, snores, startles awake, salutes
            sleepy: () => [
                { t: "( -_-)", ms: 700 },
                { t: "( -_-) z", ms: 500 },
                { t: "( -_-) zZ", ms: 500 },
                { t: "( -_-) zZz", ms: 600 },
                { t: "( -_-)  Zz", ms: 500 },
                { t: "( -_-) zZz", ms: 600 },
                { t: "( °_°)!", ms: 450 },
                { t: "( °_°)", ms: 500 },
                { t: "( ^_^)ゞ", ms: 1100, sparkle: true }
            ],
            // flips the table, thinks better of it
            tableflip: () => [
                { t: "(°_°)", ms: 600 },
                { t: "(°□°)", ms: 350 },
                { t: "(╯°□°)╯ ┬─┬", ms: 350 },
                { t: "(╯°□°)╯︵ ┻━┻", ms: 1300, color: "danger" },
                { t: "(°_°)    ┻━┻", ms: 700 },
                { t: "┬─┬ノ(º_ºノ)", ms: 1300 },
                { t: "(^_^)  ┬─┬", ms: 900, sparkle: true }
            ],
            // Solaire
            sun: () => [
                { t: "( ・_・)", ms: 600 },
                { t: "( ・_・)/", ms: 300 },
                { t: "\\( ・_・)/", ms: 300 },
                { t: "\\[T]/", ms: 900, sparkle: true },
                { t: "\\[T]/ praise the sun!", ms: 1700, sparkle: true }
            ],
            // dances to something only it can hear
            dance: () => {
                const f = []
                for (let i = 0; i < 4; i++) {
                    f.push({ t: "(～￣▽￣)～ ♪", ms: 380 })
                    f.push({ t: "～(￣▽￣～) ♫", ms: 380 })
                }
                return f.concat([{ t: "(￣▽￣)ノ ♪", ms: 1000, sparkle: true }])
            },
            // hacks the mainframe
            hack: () => {
                const f = [{ t: "(•_•) hacking...", ms: 700 }]
                for (let i = 0; i <= 8; i++)
                    f.push({ t: "[" + "■".repeat(i) + "□".repeat(8 - i) + "] " + Math.round(i / 8 * 100) + "%", ms: 160 + Math.random() * 160 })
                return f.concat([
                    { t: "[■■■■■■■■] ACCESS GRANTED", ms: 1200, sparkle: true },
                    { t: "(•_•)", ms: 450 },
                    { t: "( •_•)>⌐■-■", ms: 600 },
                    { t: "(⌐■_■)", ms: 1300, sparkle: true }
                ])
            },
            // has no idea either
            shrug: () => [
                { t: "(・_・)", ms: 600 },
                { t: "(・_・)?", ms: 700 },
                { t: "¯\\_(ツ)_/¯", ms: 1600 }
            ],
            // a cat wanders in
            cat: () => [
                { t: "(=^･ω･^=)", ms: 900 },
                { t: "(=^･ω･^=) mrrp", ms: 900 },
                { t: "(=^-ω-^=)", ms: 600 },
                { t: "(=^-ω-^=) zZ", ms: 1000 },
                { t: "(=^･ω･^=)!", ms: 450 },
                { t: "(=^･ｪ･^=)ﾉ", ms: 1100, sparkle: true }
            ],
            // Pac-Man eats the dots with a ghost on his tail, gets the power
            // pellet, turns and eats the ghost
            pacman: () => {
                const W = 20, f = []
                const line = cells => cells.join("").replace(/\s+$/, "")
                // right: chomp the dots, ghost three behind
                for (let p = 0; p <= W; p++) {
                    const c = []
                    for (let i = 0; i <= W; i++)
                        c.push(i === W ? "◉" : i > p && i % 2 === 0 ? "•" : " ")
                    if (p - 4 >= 0) c[p - 4] = "ᗣ"
                    c[Math.min(p, W)] = p % 2 === 0 ? "ᗧ" : "●"
                    f.push({ t: line(c), ms: 120 })
                }
                // power pellet: the ghost turns and runs, Pac-Man gives chase
                let g = W - 4, p = W
                f.push({ t: line(Array(g).fill(" ").concat(["ᗣ", " ", " ", " ", "ᗤ"])), ms: 450, color: "accent2" })
                for (let k = 0; g > 0 && p - g > 1; k++) {
                    if (k % 2 === 0) g--
                    p--
                    const c = Array(W + 1).fill(" ")
                    c[g] = "ᗣ"
                    c[p] = k % 2 === 0 ? "ᗤ" : "●"
                    f.push({ t: line(c), ms: 110, color: "accent2" })
                }
                const c = Array(W + 1).fill(" ")
                c[g] = "2"; c[g + 1] = "0"; c[g + 2] = "0"
                f.push({ t: line(c), ms: 900, color: "accent2", sparkle: true })
                return f.concat([{ t: "Pᗣᗧ•••MᗣN", ms: 1600, sparkle: true }])
            },
            // Dark Souls: rests at the bonfire
            bonfire: () => {
                const f = []
                for (let i = 6; i >= 1; i--) f.push({ t: "( ・_・)" + " ".repeat(i) + "†", ms: 260 })
                return f.concat([
                    { t: "( ・_・)†", ms: 500 },
                    { t: "( -_-)†", ms: 500 },
                    { t: "( -_-)†,", ms: 260 },
                    { t: "( -_-)†,'", ms: 260 },
                    { t: "( -_-)†,'`", ms: 400, color: "accent2" },
                    { t: "B O N F I R E   L I T", ms: 1800, color: "accent2", sparkle: true }
                ])
            },
            // runs across the bar, arms back
            narutorun: () => {
                const f = []
                for (let i = 0; i <= 16; i++)
                    f.push({ t: " ".repeat(i) + (i % 2 === 0 ? "ε=ε=┌( `ー´)┘" : "ε=ε=└( `ー´)┐"), ms: 110 })
                return f.concat([{ t: " ".repeat(16) + "( `ー´)ゞ believe it!", ms: 1500, sparkle: true }])
            },
            // Gojo
            domain: () => [
                { t: "( ¬‿¬)", ms: 700 },
                { t: "( ¬‿¬)ノ", ms: 400 },
                { t: "( ¬‿¬)ノ 領域展開", ms: 900 },
                { t: "( ¬‿¬)ノ domain expansion...", ms: 1100 },
                { t: "∞", ms: 180, color: "accent2" },
                { t: "∞ ∞ ∞", ms: 180, color: "accent2" },
                { t: "∞ I N F I N I T E   V O I D ∞", ms: 1800, color: "accent2", sparkle: true }
            ],
            // Factorio: a belt carries gears along
            factory: () => {
                const W = 22, f = []
                for (let k = 0; k < 26; k++) {
                    let t = ""
                    for (let i = 0; i < W; i++)
                        t += (i + k) % 5 === 0 ? "⚙" : (i - k % 2) % 2 === 0 ? "›" : " "
                    f.push({ t: "[" + t + "]", ms: 120 })
                }
                return f.concat([{ t: "the factory must grow ⚙", ms: 1600, sparkle: true }])
            },
            // types the forbidden command, thinks better of it
            sudo: () => {
                const cmd = "$ sudo rm -rf /", f = []
                for (let i = 2; i <= cmd.length; i++) f.push({ t: cmd.slice(0, i) + "▌", ms: 90 })
                return f.concat([
                    { t: cmd + "▌", ms: 700 },
                    { t: "(°ロ°) !!", ms: 600, color: "danger" },
                    { t: cmd + "^C", ms: 700 },
                    { t: "(˘︹˘ ) phew", ms: 1300 }
                ])
            },
            // coffee break
            coffee: () => [
                { t: "( ・_・)_旦", ms: 800 },
                { t: "( ・_・)_旦 ~", ms: 350 },
                { t: "( ・_・)_旦 ~~", ms: 350 },
                { t: "( ˘▽˘)っ旦", ms: 900 },
                { t: "( ˘ω˘)  ahh", ms: 1100 },
                { t: "( ・ω・)_旦 ~", ms: 900, sparkle: true }
            ],
            // casts, waits, lands one
            fishing: () => {
                const f = [
                    { t: "( ・_・)ノ", ms: 500 },
                    { t: "( ・_・)ノ⌒", ms: 250 },
                    { t: "( ・_・)ノ⌒ ゜", ms: 250 }
                ]
                for (let i = 0; i < 4; i++) {
                    f.push({ t: "( ・_・)ノ⌒ ~~゜~~", ms: 400 })
                    f.push({ t: "( ・_・)ノ⌒ ~゜~~~", ms: 400 })
                }
                return f.concat([
                    { t: "( °_°)ノ⌒ ~~!~~", ms: 500 },
                    { t: "( >_<)ノ⌒ ><(((°>", ms: 500 },
                    { t: "( ^_^)ノ ><(((°>", ms: 1300, sparkle: true }
                ])
            },
            // a snail takes its time
            snail: () => {
                const f = []
                for (let i = 0; i <= 12; i++)
                    f.push({ t: ".".repeat(i) + "_@_y", ms: 330 })
                return f.concat([{ t: "............_@_y  made it", ms: 1400, sparkle: true }])
            },
            // Chainsaw Man: pulls the cord
            chainsaw: () => [
                { t: "( ・_・)", ms: 600 },
                { t: "( ・_・)ノ⌐", ms: 450 },
                { t: "( °_°)ノ⌐ *pull*", ms: 500 },
                { t: "( °_°)ノ⌐ *pull* *pull*", ms: 600 },
                { t: "(ʘ皿ʘ) VRRRRR", ms: 260, color: "danger" },
                { t: "(ʘ皿ʘ) VRRRRRRRR", ms: 260, color: "danger" },
                { t: "(ʘ皿ʘ) VRRRRRRRRRRRR", ms: 900, color: "danger" },
                { t: "( ・ω・) ...woof", ms: 1300 }
            ],
            // Berserk: the Dragon Slayer
            berserk: () => {
                const f = [{ t: "( ಠ_ಠ)", ms: 700 }]
                for (let i = 1; i <= 12; i++) f.push({ t: "( ಠ_ಠ)╾" + "━".repeat(i) + "⊳", ms: 70 })
                return f.concat([
                    { t: "( ಠ_ಠ)╾━━━━━━━━━━━━⊳", ms: 800 },
                    { t: "that thing was too big to be called a sword.", ms: 2000, color: "dim" }
                ])
            },
            // Death Note: writes a name, Ryuk laughs
            deathnote: () => {
                const name = "L Lawliet", f = [{ t: "( ¬‿¬)✎", ms: 600 }]
                for (let i = 1; i <= name.length; i++) f.push({ t: "( ¬‿¬)✎ " + name.slice(0, i), ms: 120 })
                return f.concat([
                    { t: "( ¬‿¬)✎ " + name, ms: 800 },
                    { t: "40 seconds...", ms: 1100, color: "danger" },
                    { t: "(ﾟ∀ﾟ) hyuk hyuk... humans are so interesting", ms: 1900, color: "dim" }
                ])
            },
            // Half-Life: headcrab vs. crowbar
            headcrab: () => {
                const f = []
                for (let i = 10; i >= 1; i--) f.push({ t: "( •_•)" + " ".repeat(i) + "ж", ms: 120 })
                return f.concat([
                    { t: "( °_°)ж", ms: 400, color: "danger" },
                    { t: "( >_<)ノ⌐ *crowbar*", ms: 500 },
                    { t: "( •_•)ノ⌐    ж.", ms: 700 },
                    { t: "( •_•) λ", ms: 1300, color: "accent2", sparkle: true }
                ])
            },
            // Gurren Lagann: the drill that pierces the heavens
            drill: () => {
                const f = [{ t: "( `ー´)ﾉ", ms: 600 }]
                for (let i = 1; i <= 10; i++) f.push({ t: "( `ー´)ﾉ" + "=".repeat(i) + "≫", ms: 90, color: i > 6 ? "accent2" : "" })
                return f.concat([
                    { t: "( `ー´)ﾉ==========≫ GIGA DRILL", ms: 900, color: "accent2" },
                    { t: "who the hell do you think I am?!", ms: 1800, color: "accent2", sparkle: true }
                ])
            },
            // vim: can't leave
            vimtrap: () => [
                { t: "( ・_・) :q", ms: 700 },
                { t: "E37: No write since last change", ms: 900, color: "danger" },
                { t: "( °_°) :q!", ms: 600 },
                { t: "( °_°) ^C ^C ^C", ms: 700 },
                { t: "( ;_;) ESC ESC ESC :wq", ms: 800 },
                { t: "( ;_;) i live here now", ms: 1500, color: "dim" }
            ],
            // Gentoo: a quick update
            gentoo: () => {
                const f = [{ t: "$ emerge -avuDN @world", ms: 900 }]
                for (const p of ["gcc", "llvm", "rust", "chromium", "qtwebengine"])
                    f.push({ t: ">>> compiling " + p + "...", ms: 500 })
                return f.concat([
                    { t: "( -_-) zZ  [3h 42m left]", ms: 1100, color: "dim" },
                    { t: "( °_°) USE flags changed. starting over.", ms: 1300, color: "danger" },
                    { t: "(ﾉಥ益ಥ)ﾉ", ms: 1200, color: "danger" }
                ])
            },
            // Water Breathing
            breathing: () => [
                { t: "( -_-) hhhh...", ms: 900, color: "dim" },
                { t: "( -_-) total concentration...", ms: 1000 },
                { t: "( `ー´)⚔ ~", ms: 220 },
                { t: "( `ー´)⚔ ~~≈", ms: 220 },
                { t: "( `ー´)⚔ ~~≈≈~~≈≈", ms: 220 },
                { t: "water breathing, first form!", ms: 1800, color: "accent2", sparkle: true }
            ],
            // Undertale: a skeleton's warning, and determination
            determination: () => [
                { t: "( ・_・)", ms: 500 },
                { t: "( ・_・) ♥", ms: 700, color: "danger" },
                { t: "* you feel like you're going to have a bad time.", ms: 1800, color: "dim" },
                { t: "( `_´) ♥", ms: 500, color: "danger" },
                { t: "* you are filled with DETERMINATION.", ms: 1800, color: "accent2", sparkle: true }
            ],
            // Metal Gear: spotted, hides in a box
            alert: () => [
                { t: "( ・_・)", ms: 600 },
                { t: "( °_°) !", ms: 600, color: "danger" },
                { t: "[ ! ] ALERT", ms: 700, color: "danger" },
                { t: "( ;_;)□", ms: 400 },
                { t: "    □", ms: 900 },
                { t: "    □ ...", ms: 1000 },
                { t: "    □ kept you waiting, huh?", ms: 1600, sparkle: true }
            ],
            // Skyrim
            fusrodah: () => [
                { t: "( `ー´) FUS", ms: 500 },
                { t: "( `ー´) FUS RO", ms: 500 },
                { t: "( `ロ´) FUS RO DAH!!", ms: 300, color: "accent2" },
                { t: "( `ロ´)    ≡≡≡≡≡    ┻━┻", ms: 300, color: "accent2" },
                { t: "( `ロ´)              ≡≡≡≡  ┻━┻", ms: 300, color: "accent2" },
                { t: "( ^_^) hey, you. you're finally awake.", ms: 1700 }
            ],
            // Zelda: opens a chest
            chest: () => [
                { t: "( ・_・) ▣", ms: 700 },
                { t: "( ・_・)ノ▣", ms: 600 },
                { t: "( °o°)ノ□ ✧", ms: 500, color: "accent2" },
                { t: "\\(°o°)/ ▲ ♪ da-na-na-naaa", ms: 1400, color: "accent2", sparkle: true },
                { t: "you got a heart container!", ms: 1500, sparkle: true }
            ],
            // Steins;Gate: phone call to the Organization
            steinsgate: () => [
                { t: "( ¬‿¬)ノ☎", ms: 700 },
                { t: "( ¬‿¬)ノ☎ it's me.", ms: 900 },
                { t: "( ¬‿¬)ノ☎ the Organization is on the move.", ms: 1500 },
                { t: "world line: 1.048596", ms: 1200, color: "accent2" },
                { t: "( ¬‿¬) El Psy Kongroo.", ms: 1500, sparkle: true }
            ],
            // Matrix rain, then the message
            matrix: () => {
                const chars = "ｱｲｳｴｵｶｷｸｹｺ01ﾊﾋﾌﾍﾎ", f = []
                for (let k = 0; k < 10; k++) {
                    let t = ""
                    for (let i = 0; i < 22; i++) t += Math.random() < 0.3 ? " " : chars[Math.floor(Math.random() * chars.length)]
                    f.push({ t: t, ms: 110, color: "accent2" })
                }
                return f.concat([
                    { t: "wake up, Neo...", ms: 1400, color: "accent2" },
                    { t: "follow the white rabbit.", ms: 1500, color: "accent2" },
                    { t: "knock, knock. (°_°)", ms: 1400 }
                ])
            },
            // Noctis: building your own compiler
            compiler: () => [
                { t: "$ noctis build", ms: 800 },
                { t: "error: expected ';' at 1:1", ms: 1000, color: "danger" },
                { t: "(ಠ_ಠ) ...the language doesn't have semicolons", ms: 1500 },
                { t: "( ・_・)⌨ fixing the parser...", ms: 1000 },
                { t: "$ noctis build", ms: 600 },
                { t: "( ^_^)b 0 errors. it compiles itself now", ms: 1600, sparkle: true }
            ],
            // N64: blows on the cartridge
            cartridge: () => [
                { t: "( ・_・)[▤]", ms: 600 },
                { t: "[N64] ▓▒░▒▓ ...", ms: 800, color: "danger" },
                { t: "( ・3・)~[▤] fwoo", ms: 600 },
                { t: "( ・3・)~~[▤] FWOOO", ms: 600 },
                { t: "( ^_^)[▤] *click*", ms: 500 },
                { t: "it's-a me! ♪", ms: 1400, sparkle: true }
            ],
            // Hack The Box: owns a box
            pwn: () => [
                { t: "$ nmap -sV 10.10.11.42", ms: 900 },
                { t: "22/tcp ssh · 80/tcp http", ms: 900 },
                { t: "( ・_・)⌨ gobuster...", ms: 800 },
                { t: "( °_°) /admin.bak ?!", ms: 900 },
                { t: "user.txt ✓", ms: 800, color: "accent2" },
                { t: "root.txt ✓", ms: 800, color: "accent2" },
                { t: "(⌐■_■) pwned.", ms: 1300, sparkle: true }
            ],
            // Welcome to the Game: someone at the door
            knock: () => [
                { t: "( ・_・)⌨ ...", ms: 1000 },
                { t: "( ・_・)⌨ ... *knock*", ms: 700, color: "dim" },
                { t: "( °_°) ... *knock knock*", ms: 800, color: "danger" },
                { t: "(  ;°_°) lights off. mic off.", ms: 1300, color: "danger" },
                { t: "( ;-_-) ...", ms: 1400, color: "dim" },
                { t: "( ・_・)⌨ back to work.", ms: 1200 }
            ],
            // deadmau5
            mau5: () => {
                const f = [{ t: "( ・_・) ♪", ms: 600 }]
                for (let i = 0; i < 6; i++) {
                    f.push({ t: "[◕ ◕]  ♫ ▁▃▅▇", ms: 260, color: "accent2" })
                    f.push({ t: "[◕ ◕]  ♪ ▇▅▃▁", ms: 260 })
                }
                return f.concat([{ t: "[◕ ◕] *strobe*", ms: 1300, color: "accent2", sparkle: true }])
            },
            // ricing: one more tweak
            rice: () => [
                { t: "( ・_・)⌨ one more tweak...", ms: 1100 },
                { t: "( ・_・)⌨ ...padding 4px → 5px", ms: 1000 },
                { t: "( -_-)⌨ 2 AM", ms: 800, color: "dim" },
                { t: "( -_-)⌨ 4 AM", ms: 800, color: "dim" },
                { t: "( ˘▽˘) perfect.", ms: 900 },
                { t: "( ・_・) ...actually, 4px was better.", ms: 1600 }
            ],
            // Pop Team Epic
            popteamepic: () => [
                { t: "(´・ω・`)", ms: 700 },
                { t: "(´・ω・`) ?", ms: 600 },
                { t: "(╬ Ò﹏Ó)", ms: 500, color: "danger" },
                { t: "(╬ Ò皿Ó)ノ ┻━┻", ms: 800, color: "danger" },
                { t: "(´・ω・`) ...it's pop team epic.", ms: 1500 }
            ],
            // TempleOS: random words from God
            oracle: () => {
                const words = ["divine", "intellect", "compiler", "640x480", "holy", "C", "glow", "temple", "random", "joy", "simplicity", "ring-0"]
                const pick = () => words[Math.floor(Math.random() * words.length)]
                return [
                    { t: "( •_•) asking God...", ms: 1000 },
                    { t: "(  •_•)⊹ " + pick(), ms: 450, color: "accent2" },
                    { t: "(  •_•)⊹ " + pick() + " " + pick(), ms: 450, color: "accent2" },
                    { t: "(  •_•)⊹ " + pick() + " " + pick() + " " + pick(), ms: 1300, color: "accent2" },
                    { t: "( ^_^) God has spoken.", ms: 1300, sparkle: true }
                ]
            },
            // Cowboy Bebop
            cowboy: () => [
                { t: "see you", ms: 700, color: "dim" },
                { t: "see you space", ms: 700, color: "dim" },
                { t: "see you space cowboy...", ms: 2200, color: "dim" }
            ],
            // fingerprint scanner bit
            fingerprint: () => [
                { t: "( •_•)", ms: 500 },
                { t: "( •_•)☝", ms: 500 },
                { t: "( •_•)☝[▒▒]", ms: 450 },
                { t: "( •_•)☝[▓▒]", ms: 300 },
                { t: "( •_•)☝[▓▓]", ms: 300 },
                { t: "( ^_^)b access granted", ms: 1500, sparkle: true }
            ],
            // gets bodied by a boss, tries again
            died: () => [
                { t: "(ง •_•)ง", ms: 800 },
                { t: "(ง •_•)ง  ⚔", ms: 600 },
                { t: "( x_x)", ms: 700, color: "danger" },
                { t: "Y O U   D I E D", ms: 1700, color: "danger" },
                { t: "( •_•) ...again.", ms: 1200 }
            ]
        })

        // ---------------- event skits ----------------
        // Things happening on the machine get a reaction in place of the
        // quote: battery, charger, power profile, sound, network, VPN,
        // bluetooth, load, music, notifications, night light, calendar,
        // the clock, coming back to the desk. Each event has a cooldown so a
        // flapping signal can't spam it, and nothing fires while the shell is
        // starting up (properties settle then).
        property bool armed: false
        property var lastFired: ({})

        function react(key, core, cooldownSec) {
            if (!armed || !core || core.length === 0) return
            const now = Date.now()
            if (now - (lastFired[key] || 0) < (cooldownSec || 60) * 1000) return
            lastFired[key] = now
            stopTicker()
            play(core, true)
        }

        function short(t, n) { t = String(t || ""); return t.length > n ? t.slice(0, n - 1) + "…" : t }

        Timer {
            interval: 6000
            running: true
            onTriggered: {
                quote.armed = true
                const h = new Date().getHours()
                quote.react("hello", [
                    { t: "( ^_^)ノ", ms: 600 },
                    { t: "( ^_^)ノ good " + (h < 5 ? "night" : h < 12 ? "morning" : h < 18 ? "afternoon" : "evening") + "!", ms: 1800, sparkle: true }
                ], 1)
            }
        }

        // battery and charger
        property bool _lowWarned: false
        property bool _critWarned: false
        Connections {
            target: Power
            function onOnACChanged() {
                if (!Power.hasBattery) return
                if (Power.onAC) quote.react("plugged", [
                    { t: "(°o°) !", ms: 500 },
                    { t: "( ˘▽˘)っ⚡", ms: 900, color: "accent2" },
                    { t: "( ^‿^) thank you for charging me ♥", ms: 2000, sparkle: true }
                ], 20)
                else quote.react("unplugged", [
                    { t: "( ・_・) ...unplugged?", ms: 1000 },
                    { t: "(ง •_•)ง running on battery: " + Power.battery + "%", ms: 1800 }
                ], 20)
            }
            function onBatteryChanged() {
                if (!Power.hasBattery) return
                const b = Power.battery
                if (Power.onAC || b > Power.lowThreshold + 2) { quote._lowWarned = false; quote._critWarned = false }
                if (Power.onAC) {
                    if (b >= 100) quote.react("full", [
                        { t: "(ﾉ◕ヮ◕)ﾉ", ms: 600, color: "accent2" },
                        { t: "(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧ fully charged!", ms: 2000, color: "accent2", sparkle: true }
                    ], 3600)
                    return
                }
                if (b <= 10 && !quote._critWarned) {
                    quote._critWarned = true
                    quote.react("critical", [
                        { t: "(ﾟДﾟ;)", ms: 500, color: "danger" },
                        { t: "(ﾟДﾟ;) " + b + "%!!", ms: 900, color: "danger" },
                        { t: "( x_x) i'm fading...", ms: 1200, color: "danger" },
                        { t: "(ﾟДﾟ;) CHARGER. NOW.", ms: 1800, color: "danger" }
                    ], 60)
                } else if (b <= Power.lowThreshold && !quote._lowWarned) {
                    quote._lowWarned = true
                    quote.react("low", [
                        { t: "(°_°;)", ms: 600 },
                        { t: "(°_°;) " + b + "%...", ms: 900, color: "danger" },
                        { t: "(｡>﹏<｡) please...", ms: 1000 },
                        { t: "(｡>﹏<｡) plug me in?", ms: 1800, color: "danger" }
                    ], 60)
                }
            }
            function onCurrentChanged() {
                const c = Power.current
                if (c === "performance") quote.react("perf", [
                    { t: "(ง •_•)ง", ms: 500 },
                    { t: "(ง °□°)ง POWER UP!", ms: 1600, color: "accent2", sparkle: true }
                ], 10)
                else if (c === "power-saver") quote.react("saver", [
                    { t: "( -_-)", ms: 600, color: "dim" },
                    { t: "( -_-) power saver on.", ms: 1200, color: "dim" },
                    { t: "( -_-) dimming my thoughts...", ms: 1600, color: "dim" }
                ], 10)
                else if (c === "balanced") quote.react("balanced", [
                    { t: "( ・_・)⚖", ms: 600 },
                    { t: "( ・_・)⚖ perfectly balanced,", ms: 1300 },
                    { t: "as all things should be.", ms: 1600 }
                ], 10)
            }
        }

        // sound
        Connections {
            target: bar
            function onMutedChanged() {
                if (bar.muted) quote.react("mute", [
                    { t: "( -_-)", ms: 400, color: "dim" },
                    { t: "( -_-) shh...", ms: 1400, color: "dim" }
                ], 10)
                else quote.react("unmute", [
                    { t: "( ゜o゜) ♪", ms: 500 },
                    { t: "( ゜o゜) ♪ sound's back!", ms: 1400 }
                ], 10)
            }
        }

        // internet: judged a few seconds after things change, so a quick
        // reconnect or a switch between networks doesn't count
        property bool _online: true
        readonly property bool online: Net.ssid !== "" || Net.ethIface !== ""
        onOnlineChanged: netSettle.restart()
        Timer {
            id: netSettle
            interval: 5000
            onTriggered: {
                if (quote.online === quote._online) return
                quote._online = quote.online
                if (quote.online) quote.react("online", [
                    { t: "( °o°)", ms: 400 },
                    { t: "( ^_^) back online" + (Net.ssid !== "" ? " · " + quote.short(Net.ssid, 16) : ""), ms: 1800, sparkle: true }
                ], 30)
                else quote.react("offline", [
                    { t: "( ;_;)", ms: 600, color: "danger" },
                    { t: "(ಥ﹏ಥ) the internet is gone...", ms: 2000, color: "danger" }
                ], 30)
            }
        }

        // tailscale
        Connections {
            target: Vpn
            function onRunningChanged() {
                if (!Vpn.installed) return
                if (Vpn.running) quote.react("vpnup", [
                    { t: "( •_•)", ms: 450 },
                    { t: "( •_•)>⌐■-■", ms: 500 },
                    { t: "(⌐■_■) tunneled in.", ms: 1600, sparkle: true }
                ], 20)
                else quote.react("vpndown", [
                    { t: "( ・_・) out of the tunnel.", ms: 1600, color: "dim" }
                ], 20)
            }
        }

        // bluetooth: a device connecting
        readonly property var btNames: Bluetooth.defaultAdapter
            ? Bluetooth.defaultAdapter.devices.values.filter(d => d.connected).map(d => d.name || "device") : []
        property var _btSeen: []
        onBtNamesChanged: {
            const fresh = btNames.filter(n => _btSeen.indexOf(n) < 0)
            _btSeen = btNames.slice()
            if (fresh.length > 0) react("bt-" + fresh[0], [
                { t: "( ˘▽˘)", ms: 400 },
                { t: "( ˘▽˘)ノ hi, " + short(fresh[0], 18), ms: 1600, sparkle: true }
            ], 120)
        }

        // load: CPU pegged for ~15 s, memory over 90%
        property int _hot: 0
        property bool _memWarned: false
        Timer {
            interval: 5000
            repeat: true
            running: true
            onTriggered: {
                quote._hot = bar.cpu > 0.9 ? quote._hot + 1 : bar.cpu < 0.7 ? 0 : quote._hot
                if (quote._hot === 3) quote.react("cpu", [
                    { t: "(°□°;)", ms: 500, color: "danger" },
                    { t: "(°□°;) CPU at " + Math.round(bar.cpu * 100) + "%", ms: 1000, color: "danger" },
                    { t: "( >_<) it's getting hot in here", ms: 1800, color: "danger" }
                ], 600)
                if (bar.mem > 0.9 && !quote._memWarned) {
                    quote._memWarned = true
                    quote.react("mem", [
                        { t: "( @_@)", ms: 500 },
                        { t: "( @_@) RAM at " + Math.round(bar.mem * 100) + "%... too many tabs?", ms: 2000, color: "danger" }
                    ], 600)
                } else if (bar.mem < 0.8) quote._memWarned = false
            }
        }

        // music: a new track starts playing
        property string _track: ""
        Connections {
            target: bar.player
            function onTrackTitleChanged() { songCheck.restart() }
            function onIsPlayingChanged() { songCheck.restart() }
        }
        Timer {
            id: songCheck
            interval: 1500
            onTriggered: {
                const p = bar.player
                if (!p || !p.isPlaying || !p.trackTitle || p.trackTitle === quote._track) return
                quote._track = p.trackTitle
                quote.react("song", [
                    { t: "(～￣▽￣)～", ms: 380 },
                    { t: "～(￣▽￣～)", ms: 380 },
                    { t: "(～￣▽￣)～", ms: 380 },
                    { t: "♪ " + quote.short(p.trackTitle, 34), ms: 2400, sparkle: true }
                ], 45)
            }
        }

        Connections {
            target: Recorder
            function onStateChanged() {
                if (Recorder.state === "recording") quote.react("rec", [
                    { t: "(•_•)📹 rolling...", ms: 1400, color: "dim" }
                ], 5)
            }
            function onSaved(path) {
                quote.react("rec-saved", [
                    { t: "(•_•)📹 ...and cut!", ms: 900 },
                    { t: "(ﾉ◕ヮ◕)ﾉ that's a wrap · " + Recorder.clock, ms: 1800, color: "accent2", sparkle: true }
                ], 5)
            }
            function onFailed(why) {
                quote.react("rec-failed", [
                    { t: "(;´・ω・) the recording didn't save", ms: 2200, color: "danger" }
                ], 5)
            }
        }

        Connections {
            target: Caffeine
            function onOnChanged() {
                if (Caffeine.on) quote.react("caffeine", [
                    { t: "( ・_・)_旦", ms: 500 },
                    { t: "( ˘▽˘)っ旦 ~", ms: 700 },
                    { t: "(ﾟ∀ﾟ) caffeinated. no sleep for me!", ms: 1800, color: "accent2", sparkle: true }
                ], 5)
                else quote.react("decaf", [
                    { t: "( -_-) decaf...", ms: 1100, color: "dim" },
                    { t: "( -_-) zZ okay, i can nap now", ms: 1600, color: "dim" }
                ], 5)
            }
        }

        // do not disturb, night light
        Connections {
            target: Notifs
            function onDndChanged() {
                if (Notifs.dnd) quote.react("dnd", [{ t: "( -_-)ﾉ do not disturb.", ms: 1600, color: "dim" }], 5)
                else quote.react("undnd", [{ t: "( ・_・) I'm listening.", ms: 1400 }], 5)
            }
            function onCountChanged() {
                const l = Notifs.list
                const n = l.length ? l[l.length - 1] : null
                if (n && /screenshot/i.test((n.summary || "") + " " + (n.body || "")))
                    quote.react("shot", [
                        { t: "( ^_^)ノ[◉]", ms: 500 },
                        { t: "( ^_^)ノ[◉] say cheese!", ms: 900 },
                        { t: "[◉] *click*", ms: 900, sparkle: true }
                    ], 60)
            }
        }
        Connections {
            target: NightLight
            function onActiveChanged() {
                if (NightLight.active) quote.react("night", [{ t: "( -_-)☾ easy on the eyes", ms: 1600, color: "dim" }], 30)
                else quote.react("day", [{ t: "( ・_・)☀ lights up", ms: 1400 }], 30)
            }
        }

        // fingerprints: enrolling / testing in Settings, and unlocking with a finger
        Connections {
            target: Fingerprint
            function onEvent(kind, finger) {
                const f = finger && finger !== "all" ? Fingerprint.label(finger).toLowerCase() : ""
                if (kind === "unlock") {
                    // beats the generic "welcome back", which would fire right after
                    quote.lastFired["welcome"] = Date.now()
                    fpUnlockLater.restart()
                } else if (kind === "enrolled") quote.react("fp-enrolled", [
                    { t: "( •_•)☝", ms: 500 },
                    { t: "( •_•)☝ boop", ms: 600 },
                    { t: "(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧ " + f + " saved!", ms: 2000, color: "accent2", sparkle: true }
                ], 5)
                else if (kind === "duplicate") quote.react("fp-dupe", [
                    { t: "( ・_・)☝", ms: 500 },
                    { t: "(¬_¬) i already know that finger...", ms: 2000 }
                ], 5)
                else if (kind === "enroll-failed") quote.react("fp-fail", [
                    { t: "( >_<)☝", ms: 600, color: "danger" },
                    { t: "( ;_;) the reader didn't like that", ms: 1800, color: "danger" }
                ], 5)
                else if (kind === "match") quote.react("fp-match", [
                    { t: "( •_•)", ms: 450 },
                    { t: "( •_•)>⌐■-■", ms: 500 },
                    { t: "(⌐■_■) identity confirmed.", ms: 1600, sparkle: true }
                ], 5)
                else if (kind === "nomatch") quote.react("fp-nomatch", [
                    { t: "(¬_¬)", ms: 600, color: "danger" },
                    { t: "(¬_¬) who are you?", ms: 1600, color: "danger" }
                ], 5)
                else if (kind === "deleted") quote.react("fp-deleted", [
                    { t: "( ・_・)ノ", ms: 500, color: "dim" },
                    { t: "( ・_・)ノ bye bye, " + (f || "prints"), ms: 1600, color: "dim" }
                ], 5)
            }
        }
        Timer {
            id: fpUnlockLater
            interval: 700   // let the lock screen fade first
            onTriggered: quote.react("fp-unlock", [
                { t: "( ^_^)☝", ms: 500 },
                { t: "( ^_^)☝ *beep*", ms: 600 },
                { t: "( ^‿^)ノ it's you! welcome back", ms: 1800, sparkle: true }
            ], 10)
        }

        // the clock and the calendar, checked once a minute
        property int _minute: -1
        Connections {
            target: clock
            function onDateChanged() {
                const d = clock.date, m = d.getHours() * 60 + d.getMinutes()
                if (m === quote._minute) return
                quote._minute = m
                const h = d.getHours(), mi = d.getMinutes()
                if (mi === 0) {
                    if (h === 0) quote.react("midnight", [
                        { t: "( ・_・)☾", ms: 600 },
                        { t: "( ・_・)☾ it's midnight... go to bed", ms: 2000, color: "dim" }
                    ], 3000)
                    else if (h === 3) quote.react("3am", [
                        { t: "(；ﾟДﾟ)", ms: 500 },
                        { t: "(；ﾟДﾟ) it's 3 AM. go to sleep.", ms: 2000, color: "danger" }
                    ], 3000)
                    else if (h === 12) quote.react("noon", [
                        { t: "( ´▽`)ﾉ", ms: 500 },
                        { t: "( ´▽`)ﾉ lunch time!", ms: 1600, sparkle: true }
                    ], 3000)
                    else if (h === 17 && d.getDay() === 5) quote.react("friday", [
                        { t: "\\(^o^)/", ms: 600, color: "accent2" },
                        { t: "\\(^o^)/ it's the weekend!", ms: 2000, color: "accent2", sparkle: true }
                    ], 3000)
                }
                // calendar: five minutes before, and when it starts
                const n = Calendar.next(1)
                if (n.length) {
                    const o = n[0], mins = Math.round((o.start.getTime() - d.getTime()) / 60000)
                    const title = quote.short(o.ev.title || "event", 28)
                    if (mins === 5) quote.react("cal5-" + o.start.getTime(), [
                        { t: "(°o°) !", ms: 500 },
                        { t: "(°o°) 5 min: " + title, ms: 2400, color: "accent2", sparkle: true }
                    ], 600)
                    else if (mins === 0) quote.react("cal0-" + o.start.getTime(), [
                        { t: "(ง •_•)ง now: " + title, ms: 2400, color: "accent2", sparkle: true }
                    ], 600)
                }
            }
        }

        // back at the desk after 5+ minutes away (screensaver, lock)
        IdleMonitor {
            id: away
            timeout: 300
            respectInhibitors: false
            onIsIdleChanged: if (!isIdle) welcomeLater.restart()
        }
        Timer {
            id: welcomeLater
            interval: 1500
            onTriggered: quote.react("welcome", [
                { t: "( ^_^)ノ", ms: 500 },
                { t: "( ^_^)ノ welcome back!", ms: 1600, sparkle: true }
            ], 60)
        }

        // a random skit, or one by name
        function peek(name) {
            const names = Object.keys(skits)
            const n = name && skits[name] ? name : names[Math.floor(Math.random() * names.length)]
            play(skits[n]())
        }

        Timer {
            id: faceTimer
            onTriggered: {
                quote.frameIdx++
                if (quote.frameIdx >= quote.frames.length) {
                    quote.peeking = false
                    quote.sparkle = false
                    quote.next()          // back to quotes with a fresh one
                    return
                }
                const fr = quote.frames[quote.frameIdx]
                quote.face = fr.t
                quote.sparkle = fr.sparkle === true
                quote.faceColor = fr.color || ""
                interval = fr.ms
                restart()
            }
        }

        TextMetrics {
            id: faceMetrics
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.bold: true
        }

        Row {
            id: faceRow
            visible: quote.peeking
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Text {
                text: quote.face
                color: quote.faceColor === "danger" ? Theme.danger
                     : quote.faceColor === "accent2" ? Theme.accent2
                     : quote.faceColor === "dim" ? Theme.textDim
                     : Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: "✧"
                color: Theme.accent2
                font.pixelSize: 12
                anchors.verticalCenter: parent.verticalCenter
                opacity: quote.sparkle ? 1 : 0
                scale: quote.sparkle ? 1 : 0.4
                Behavior on opacity { NumberAnimation { duration: 180 } }
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
            }
        }

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
                    quote.stopTicker()
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
            onTriggered: Math.random() < 0.33 ? quote.peek("") : quote.next()
        }

        IpcHandler {
            target: "bar"
            // one target per shell: answer from the first monitor's bar only
            enabled: bar.screen === Quickshell.screens[0]
            function peek(): void { quote.peek("") }
            // qs ipc call bar skit <name>   (names: qs ipc call bar list)
            function skit(name: string): void { quote.peek(name) }
            function list(): string { return Object.keys(quote.skits).join(" ") }
            // tray icons, and opening one's menu without the mouse
            function tray(): string { return tray.items.map((t, i) => i + ": " + (t.title || t.id)).join("\n") }
            function trayMenu(i: int): void {
                const it = tray.items[i]
                const ti = trayRepeater.itemAt(i)
                if (trayMenu.visible) { trayMenu.close(); return }
                if (!it || !it.hasMenu || !ti) return
                const p = ti.mapToItem(null, 0, ti.height + 6)
                trayMenu.open(it, bar, p.x, p.y)
            }
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
            PauseAnimation { duration: 2500 }
            ScriptAction {
                script: {
                    quote.tickX = 0
                    quote.ticker = true
                    tickerLoop.restart()
                }
            }
        }

        // then like a news ticker: scroll left at a reading pace with a second
        // copy following, so it repeats without a gap. Pauses under the mouse.
        NumberAnimation {
            id: tickerLoop
            target: quote
            property: "tickX"
            from: 0
            to: -tickerRow.width / 2
            duration: tickerRow.width / 2 / 45 * 1000
            loops: Animation.Infinite
            paused: running && quoteMouse.containsMouse
        }

        Row {
            id: tickerRow
            visible: quote.ticker && !quote.peeking
            anchors.verticalCenter: parent.verticalCenter
            x: quote.tickX

            Repeater {
                model: 2
                Row {
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
                        text: quote.body
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.italic: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        visible: quote.author !== ""
                        text: "— " + quote.author
                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "    ✦    "
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        Row {
            id: quoteRow
            visible: !quote.peeking && !quote.ticker
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
            onClicked: if (!quote.peeking) quote.next()
        }
    }

    // full quote on hover
    PopupWindow {
        anchor.window: bar
        anchor.rect.x: quote.x + quote.width / 2 - implicitWidth / 2
        anchor.rect.y: bar.implicitHeight + 6
        implicitWidth: Math.min(420, quoteMetrics.width + 40)
        implicitHeight: popupCol.implicitHeight + 28
        visible: quoteMouse.containsMouse && quote.visible && !quote.peeking
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

        // tailscale: dim when stopped, accent + node name through an exit node.
        // click = VPN dropdown, right-click = connect / disconnect
        Chip {
            visible: Vpn.installed
            icon: "󰖂"
            value: Vpn.running && Vpn.exitNode !== ""
                ? (Vpn.exitNode.length > 12 ? Vpn.exitNode.slice(0, 11) + "…" : Vpn.exitNode)
                : ""
            accent: !Vpn.running ? Theme.textFaint
                  : Vpn.exitNode !== "" ? Theme.accent
                  : Theme.text
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton)
                    Vpn.toggle()
                else
                    Quickshell.execDetached(["qs", "ipc", "call", "quick", "vpn"])
            }
        }

        // syncthing: dim when stopped, accent + % while syncing, red on errors.
        // click = web UI (starts it first if needed), right-click = start / stop
        Chip {
            visible: Syncthing.installed
            icon: !Syncthing.running ? "󰓨" : Syncthing.failing ? "󰓧" : "󰓦"
            value: Syncthing.running && Syncthing.syncing ? Math.floor(Syncthing.completion) + "%" : ""
            accent: !Syncthing.running ? Theme.textFaint
                  : Syncthing.failing ? Theme.danger
                  : Syncthing.syncing || Syncthing.scanning || Syncthing.busy ? Theme.accent
                  : Theme.text
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) Syncthing.toggle()
                else Syncthing.open()
            }
        }

        // screen recorder (wf-recorder): dim when idle, countdown, then red with
        // the running time. click = recorder panel (or stop while recording),
        // right-click = start / stop with the last settings
        Chip {
            visible: Recorder.available
            icon: Recorder.state === "recording" ? "󰻃" : "󰑊"
            value: Recorder.state === "countdown" ? String(Recorder.countdown)
                 : Recorder.state === "recording" ? Recorder.clock
                 : Recorder.state === "saving" ? "…" : ""
            accent: Recorder.state === "recording" ? Theme.danger
                  : Recorder.state === "idle" ? Theme.textFaint
                  : Theme.accent
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton || Recorder.state === "recording" || Recorder.state === "countdown")
                    Recorder.toggle()
                else
                    Quickshell.execDetached(["qs", "ipc", "call", "quick", "rec"])
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
