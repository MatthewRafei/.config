import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "ScreensaverScenes.js" as Scenes
import qs

// ASCII screensaver: after 3 minutes idle (apps that inhibit idle, like video
// players, prevent it), every monitor gets a full-screen overlay playing its
// own animated ASCII scenes in random order (never the same one as another
// monitor, when there are enough), one per minute. Any key, click or mouse movement dismisses it
// without reaching the app underneath. The lock screen (Lock.qml) follows at
// 5 minutes; rendering pauses while locked.
//
//   qs ipc call screensaver start          start now (random scene)
//   qs ipc call screensaver scene bebop    start on a given scene (on the focused monitor)
//   qs ipc call screensaver list           scene ids
//   qs ipc call screensaver stop
Scope {
    id: root

    property bool locked: false           // bound from shell.qml
    property bool forced: false
    // timings and options come from Idle.qml (Settings > Screensaver)
    readonly property bool active: (idle.isIdle && Idle.screensaver && (Idle.onBattery || Power.onAC)) || forced

    IdleMonitor {
        id: idle
        timeout: Math.max(1, Idle.screensaverMin) * 60
        respectInhibitors: true
    }

    property string pending: ""           // scene asked for by IPC / Settings, for the focused monitor

    // a preview (started from Settings or by IPC) ignores input for a moment,
    // so the click / hand on the mouse that started it doesn't end it at once
    property real graceUntil: 0
    function inGrace() { return Date.now() < graceUntil }
    onActiveChanged: if (!active) { forced = false; pending = "" }
    // (each monitor's window starts its own scenes when this turns on)


    // ---------------- shared ----------------
    property string uptime: ""

    // OS info for the Linux scene
    property string osName: "Linux"
    property string logo: ""
    property string kernel: ""

    Process {
        running: true
        command: ["sh", "-c", ". /etc/os-release 2>/dev/null; echo \"$PRETTY_NAME\"; uname -r"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n")
                root.osName = l[0] || "Linux"
                root.kernel = l[1] || ""
            }
        }
    }

    // the distro's own ASCII logo, via fastfetch (Tux if fastfetch is missing)
    Process {
        running: true
        command: ["sh", "-c", "fastfetch -c none --pipe -s break 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: root.logo = text.replace(/\x1b\[[0-9;]*m/g, "").replace(/\s+$/, "")
                || "    .--.\n   |o_o |\n   |:_/ |\n  //   \\ \\\n (|     | )\n/'\\_   _/`\\\n\\___)=(___/"
        }
    }

    Process {
        id: uptimeProc
        command: ["sh", "-c", "uptime -p 2>/dev/null | sed 's/^up //' || cut -d. -f1 /proc/uptime"]
        stdout: StdioCollector { onStreamFinished: root.uptime = text.trim() }
    }

    // ---------------- GIF scenes ----------------
    readonly property string refs: Quickshell.shellPath("screensaver/gifs")
    readonly property string gifCache: Quickshell.env("HOME") + "/.cache/screensaver"
    readonly property string converter: Quickshell.shellPath("screensaver/gif2ascii.py")
    property var haveGifs: []           // files present in screensaver/gifs

    Process {
        id: refsProbe
        running: true
        command: ["sh", "-c", "ls -1 \"$1\" 2>/dev/null", "sh", root.refs]
        stdout: StdioCollector { onStreamFinished: root.haveGifs = text.split("\n").filter(x => x) }
    }

    function available(id) {
        const s = Scenes.get(id)
        return !s.gif || haveGifs.indexOf(s.gif) >= 0
    }

    // scenes the other monitors are showing (or loading) right now
    function showingElsewhere(win) {
        return screens.instances.filter(w => w !== win && w.currentId).map(w => w.currentId)
    }

    // the window on the focused monitor (the first one if that's unknown)
    function focusedWindow() {
        const ws = screens.instances
        return ws.find(w => w.modelData.name === Compositor.focusedOutput) || ws[0]
    }

    IpcHandler {
        target: "screensaver"
        function start(): void {
            const was = root.active
            root.graceUntil = Date.now() + 1500; root.pending = ""; root.forced = true
            if (was) for (const w of screens.instances) w.begin()
        }
        function scene(id: string): void {
            const was = root.active
            root.graceUntil = Date.now() + 1500; root.pending = id; root.forced = true
            if (was) { const w = root.focusedWindow(); if (w) w.begin() }
        }
        function stop(): void { root.forced = false }
        function list(): string { return Scenes.list().join(" ") }
        // the timings in effect (from Settings > Screensaver / Idle.qml)
        function status(): string {
            return "screensaver " + (Idle.screensaver ? "on" : "off") + ", starts after " + idle.timeout + " s idle"
                + ", scene changes every " + (Idle.sceneSec > 0 ? Idle.sceneSec + " s" : "never")
                + ", " + Scenes.list().filter(i => Idle.sceneEnabled(i)).length + " scenes in rotation"
                + (Idle.onBattery ? "" : ", skipped on battery")
                + ", " + screens.instances.length + " monitors"
        }
    }

    // ---------------- one window per monitor ----------------
    Variants {
        id: screens
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell-screensaver"
            // hold the keyboard while showing so the dismissing key isn't typed into an
            // app (one window takes it; several exclusive grabs would just fight)
            WlrLayershell.keyboardFocus: root.active && modelData === Quickshell.screens[0]
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            visible: root.active || backdrop.opacity > 0.01

            // ---------------- scene state ----------------
            FontLoader { id: blackletterFont; source: Qt.resolvedUrl("fonts/UnifrakturMaguntia-Book.ttf") }
            FontLoader { id: serifFont; source: Qt.resolvedUrl("fonts/IMFellEnglish-Regular.ttf") }
            FontLoader { source: Qt.resolvedUrl("fonts/IMFellEnglish-Italic.ttf") }

            property var ctx: ({})
            property var scene: null
            property string currentId: ""      // picked scene, set before a GIF finishes loading
            property real sceneTime: 0
            // one property per layer, so an unchanged layer isn't laid out again
            property var layers: ["", "", "", "", "", "", "", ""]
            property var sceneColors: []
            // real text over the grid (ctx.texts): [{ t, x, y (cells), size (rows),
            // font: "blackletter" | "serif" | "italic", color, opacity, center }]
            property var texts: []
            property string textsKey: ""
            // a picture on the grid (ctx.image): { src (relative to this file), x, y, w, h
            // (cells), reveal (0..1, wiped in left to right) }
            property var image: null
            property string bg: ""             // backdrop colour a scene asks for (ctx.bg)
            property var floor: null           // and below a row (ctx.floor: { row, color })
            property string nativeId: ""       // QML renderer under the grid (ctx.native)
            property real nativeOpacity: 0
            property bool loading: false
            property string tTitle: ""
            property string tSub: ""
            property color tColor: "#ffffff"
            property real tOpacity: 0
            property real tY: 0.78
            property var history: []
            property string prefer: ""
            readonly property real sceneLength: Idle.sceneSec > 0 ? Idle.sceneSec : 1e9   // 0 = keep one scene

            Connections {
                target: root
                function onActiveChanged() { if (root.active) win.begin() }
            }

            // (re)start this monitor's scenes; the focused one takes a scene asked for by IPC
            function begin() {
                if (root.pending && win === root.focusedWindow()) { prefer = root.pending; root.pending = "" }
                else prefer = ""
                scene = null
                currentId = ""
                startSoon.restart()
            }

            // the overlay needs a moment to get its full size before we size the grid
            Timer { id: startSoon; interval: 120; onTriggered: win.startScenes() }

            function startScenes() {
                if (grid.cols < 20 || grid.rows < 10) { startSoon.restart(); return }
                const p = prefer
                prefer = ""
                loadScene(pickScene(p))
            }

            function cachePath(id) {
                return root.gifCache + "/" + id + "-" + grid.cols + "x" + grid.rows + ".json"
            }

            // convert (if needed) then load a GIF scene's frames, off the UI thread
            property string loadingId: ""
            Process {
                id: gifLoader
                stdout: StdioCollector {
                    onStreamFinished: {
                        const id = win.loadingId
                        win.loading = false
                        let data = null
                        try { data = JSON.parse(text) } catch (e) {}
                        if (!data || !data.frames || !data.frames.length) {
                            console.log("screensaver: couldn't load", id)
                            root.haveGifs = root.haveGifs.filter(f => f !== Scenes.get(id).gif)
                            win.loadScene(win.pickScene(""))
                            return
                        }
                        win.beginScene(id, data)
                    }
                }
            }

            // warm the cache quietly so scenes don't stall the first time
            // (one window per grid size does it)
            readonly property string gridKey: grid.cols + "x" + grid.rows
            Timer {
                interval: 60000
                running: root.haveGifs.length > 0 && !root.active
                    && screens.instances.find(w => w.gridKey === win.gridKey) === win
                onTriggered: if (grid.cols > 20) warm.running = true
            }
            Process {
                id: warm
                command: {
                    const jobs = Scenes.gifs().filter(g => root.haveGifs.indexOf(g.file) >= 0)
                    let sh = "mkdir -p \"$1\"; "
                    for (const g of jobs)
                        sh += "[ -f \"$1/" + g.id + "-" + grid.cols + "x" + grid.rows + ".json\" ] || nice -n 19 python3 \"$2\" \"$3/"
                            + g.file + "\" " + grid.cols + " " + grid.rows + " " + grid.asp.toFixed(3) + " \"$1/" + g.id + "-"
                            + grid.cols + "x" + grid.rows + ".json\" " + g.convert.join(" ") + "; "
                    return ["sh", "-c", sh, "sh", root.gifCache, root.converter, root.refs]
                }
            }

            function pickScene(want) {
                const all = Scenes.list().filter(i => root.available(i))
                if (want && all.indexOf(want) >= 0) return want
                // only scenes left in the rotation (all of them if every one is off)
                // on battery, shader scenes only if asked for (Settings > Screensaver)
                const light = all.filter(i => Power.onAC || Idle.shadersOnBattery || Scenes.kind(i) !== "shader")
                const on = light.filter(i => Idle.sceneEnabled(i))
                const ids = on.length ? on : light.length ? light : all
                // random, never one another monitor is showing or one of the last few here
                const others = root.showingElsewhere(win)
                const n = Math.min(3, ids.length - 1)
                const recent = n > 0 ? history.slice(-n) : []
                const pools = [
                    ids.filter(i => others.indexOf(i) < 0 && recent.indexOf(i) < 0),
                    ids.filter(i => others.indexOf(i) < 0),
                    ids
                ]
                const pool = pools.find(p => p.length)
                return pool[Math.floor(Math.random() * pool.length)]
            }

            function loadScene(id) {
                // too small to draw yet: try again once the window has its size
                if (grid.cols < 20 || grid.rows < 10) { prefer = id; startSoon.restart(); return }
                currentId = id
                const s = Scenes.get(id)
                if (s.gif) {
                    loading = true
                    loadingId = id
                    const out = cachePath(id)
                    gifLoader.command = ["sh", "-c",
                        "g=$1 c=$2 r=$3 a=$4 f=$5 py=$6; shift 6; "
                        + "[ -f \"$f\" ] || { mkdir -p \"$(dirname \"$f\")\"; python3 \"$py\" \"$g\" \"$c\" \"$r\" \"$a\" \"$f\" \"$@\"; }; cat \"$f\"",
                        "sh", root.refs + "/" + s.gif, String(grid.cols), String(grid.rows), grid.asp.toFixed(3), out, root.converter].concat(s.convert)
                    gifLoader.running = true
                    return
                }
                beginScene(id, null)
            }

            function beginScene(id, gifData) {
                uptimeProc.running = true
                const c = {
                    cols: grid.cols, rows: grid.rows, asp: grid.asp,
                    os: root.osName, osName: root.osName, logo: root.logo, kernel: root.kernel,
                    uptime: root.uptime,
                    title: "", sub: "", titleColor: "#ffffff", titleOpacity: 0,
                    gif: gifData
                }
                const s = Scenes.get(id)
                s.init(c)
                sceneColors = s.colors.slice()
                win.ctx = c
                win.scene = s
                win.sceneTime = 0
                win.history = win.history.concat([id]).slice(-8)
                sceneFade.restart()
                win.step(0)
            }

            function step(dt) {
                if (!scene || loading) return
                sceneTime += dt
                ctx.titleOpacity = 0
                scene.frame(ctx, sceneTime, dt)
                const r = Scenes.render(ctx)
                let changed = false
                const next = layers.slice()
                for (let i = 0; i < 8; i++) {
                    const v = r[i] || ""
                    if (v !== next[i]) { next[i] = v; changed = true }
                }
                if (changed) layers = next
                tTitle = ctx.title || ""
                tSub = ctx.sub || ""
                tColor = ctx.titleColor || "#ffffff"
                tOpacity = ctx.titleOpacity || 0
                tY = ctx.titleY || 0.78
                const tk = ctx.texts ? JSON.stringify(ctx.texts) : ""
                if (tk !== textsKey) { textsKey = tk; texts = ctx.texts || [] }
                image = ctx.image || null
                bg = ctx.bg || ""
                floor = ctx.floor || null
                nativeId = ctx.native ? ctx.native.id : ""
                nativeOpacity = ctx.native ? ctx.native.opacity : 0
                if (sceneTime > sceneLength) loadScene(pickScene(""))
            }

            // 10 fps for drawn scenes (light on the battery); GIF scenes follow their
            // own frame timing up to 20 fps
            Timer {
                interval: win.scene && win.scene.gif ? 50 : 100
                repeat: true
                running: root.active && !root.locked && win.visible
                onTriggered: win.step(interval / 1000)
            }

            Rectangle {
                id: backdrop
                anchors.fill: parent
                color: win.bg !== "" ? win.bg : "#050506"
                Behavior on color { ColorAnimation { duration: 900; easing.type: Easing.InOutQuad } }
                opacity: root.active ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.InOutQuad } }

                focus: root.active
                Keys.onPressed: event => { if (!root.inGrace()) root.forced = false; event.accepted = true }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    property point last: Qt.point(-1, -1)
                    onPositionChanged: mouse => {
                        // first event after appearing (or during a preview's grace
                        // period) just records where the pointer is
                        if (last.x >= 0 && !root.inGrace() && (Math.abs(mouse.x - last.x) > 3 || Math.abs(mouse.y - last.y) > 3))
                            root.forced = false
                        last = Qt.point(mouse.x, mouse.y)
                    }
                    onPressed: if (!root.inGrace()) root.forced = false
                    onWheel: if (!root.inGrace()) root.forced = false
                }

                FontMetrics {
                    id: fm
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                }

                // what one cell really measures when laid out like the scene text
                Text {
                    id: probe
                    visible: false
                    text: "M".repeat(40)
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    renderType: Text.NativeRendering
                }

                // backdrop below a scene's floor row (its ground runs out to the screen edge)
                Rectangle {
                    visible: win.floor !== null
                    y: win.floor ? grid.y + win.floor.row * grid.ch : 0
                    width: parent.width
                    height: parent.height - y
                    color: win.floor ? win.floor.color : "transparent"
                    opacity: sceneLayer.opacity
                }

                Item {
                    id: grid
                    readonly property real cw: Math.max(1, probe.implicitWidth / 40)
                    readonly property real ch: Math.ceil(fm.height)
                    readonly property int cols: Math.max(0, Math.floor((backdrop.width - 32) / cw))
                    readonly property int rows: Math.max(0, Math.floor((backdrop.height - 24) / ch))
                    readonly property real asp: ch / cw

                    width: cols * cw
                    height: rows * ch
                    anchors.centerIn: parent

                    // resized while showing: restart the same scene at the new size
                    // (not while the window is still being sized: a 0-wide grid would
                    // write a broken cache file)
                    onColsChanged: if (root.active && win.scene && grid.cols >= 20 && grid.rows >= 10) win.loadScene(win.scene.id)

                    Item {
                        id: sceneLayer
                        anchors.fill: parent

                        NumberAnimation on opacity {
                            id: sceneFade
                            from: 0; to: 1; duration: 900
                            easing.type: Easing.OutCubic
                        }

                        // native renderers (ctx.native), full-screen under the grid text
                        Loader {
                            x: -grid.x
                            y: -grid.y
                            width: backdrop.width
                            height: backdrop.height
                            active: win.nativeId === "matrix"
                            source: Qt.resolvedUrl("MatrixRain.qml")
                            opacity: win.nativeOpacity
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            onLoaded: item.playing = Qt.binding(() => root.active && !root.locked)
                        }

                        Repeater {
                            model: 8
                            Text {
                                required property int index
                                anchors.fill: parent
                                visible: text !== ""
                                text: win.layers[index] || ""
                                color: win.sceneColors[index] || "transparent"
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                lineHeightMode: Text.FixedHeight
                                lineHeight: grid.ch
                                textFormat: Text.PlainText
                                wrapMode: Text.NoWrap
                                renderType: Text.NativeRendering
                            }
                        }

                        Item {
                            visible: win.image !== null
                            x: win.image ? win.image.x * grid.cw : 0
                            y: win.image ? win.image.y * grid.ch : 0
                            width: win.image ? win.image.w * grid.cw * win.image.reveal : 0
                            height: win.image ? win.image.h * grid.ch : 0
                            clip: true
                            Image {
                                width: win.image ? win.image.w * grid.cw : 0
                                height: parent.height
                                source: win.image ? Qt.resolvedUrl(win.image.src) : ""
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                            }
                        }

                        // scene text in book fonts (Death Note's rules)
                        Repeater {
                            model: win.texts
                            Text {
                                required property var modelData
                                x: modelData.center ? 0 : modelData.x * grid.cw
                                width: modelData.center ? grid.width : implicitWidth
                                horizontalAlignment: modelData.center ? Text.AlignHCenter : Text.AlignLeft
                                y: modelData.y * grid.ch
                                text: modelData.t
                                color: modelData.color || "#ffffff"
                                opacity: modelData.opacity === undefined ? 1 : modelData.opacity
                                font.family: modelData.font === "blackletter" ? blackletterFont.name
                                    : modelData.font === "serif" || modelData.font === "italic" ? serifFont.name
                                    : Theme.fontFamily
                                font.italic: modelData.font === "italic"
                                font.pixelSize: Math.round((modelData.size || 1) * grid.ch)
                                textFormat: Text.PlainText
                            }
                        }

                        // title / subtitle
                        Column {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: parent.height * win.tY
                            spacing: 8
                            opacity: win.tOpacity
                            visible: win.tTitle !== ""

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: titleText.implicitWidth + 60
                                height: titleText.implicitHeight + 18
                                color: "#cc050506"
                                Text {
                                    id: titleText
                                    anchors.centerIn: parent
                                    text: win.tTitle
                                    color: win.tColor
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 30
                                    font.bold: true
                                    font.letterSpacing: 6
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: text !== ""
                                text: win.tSub
                                color: win.tColor
                                opacity: 0.75
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.letterSpacing: 3
                            }
                        }
                    }
                }

                // scene name, bottom right
                Text {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 18
                    visible: Idle.showName
                    text: win.scene ? "// " + win.scene.name.toUpperCase() : ""
                    color: "#3a3a44"
                    font.family: Theme.fontFamily
                    font.pixelSize: 17
                    font.letterSpacing: 3
                }
            }
        }
    }
}
