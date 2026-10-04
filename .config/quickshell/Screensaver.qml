import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "ScreensaverScenes.js" as Scenes

// ASCII screensaver: after 3 minutes idle (apps that inhibit idle, like video
// players, prevent it), a full-screen overlay plays animated ASCII scenes in
// random order, one per minute. Any key, click or mouse movement dismisses it
// without reaching the app underneath. The lock screen (Lock.qml) follows at
// 5 minutes; rendering pauses while locked.
//
//   qs ipc call screensaver start          start now (random scene)
//   qs ipc call screensaver scene bebop    start on a given scene
//   qs ipc call screensaver list           scene ids
//   qs ipc call screensaver stop
Scope {
    id: root

    property bool locked: false           // bound from shell.qml
    property bool forced: false
    readonly property bool active: idle.isIdle || forced

    IdleMonitor {
        id: idle
        timeout: 180
        respectInhibitors: true
    }

    property string pending: ""
    onActiveChanged: {
        if (active) { scene = null; startSoon.restart() }
        else forced = false
    }

    // the overlay needs a moment to get its full size before we size the grid
    Timer { id: startSoon; interval: 120; onTriggered: root.startScenes(root.pending); }

    // ---------------- scene state ----------------
    property var ctx: ({})
    property var scene: null
    property real sceneTime: 0
    // one property per layer, so an unchanged layer isn't laid out again
    property var layers: ["", "", "", "", "", "", "", ""]
    property var sceneColors: []
    property bool loading: false
    property string tTitle: ""
    property string tSub: ""
    property color tColor: "#ffffff"
    property real tOpacity: 0
    property real tY: 0.78
    property var history: []
    readonly property real sceneLength: 60

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
        stdout: StdioCollector { onStreamFinished: root.ctx.uptime = text.trim() }
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

    function cachePath(id) {
        return gifCache + "/" + id + "-" + grid.cols + "x" + grid.rows + ".json"
    }

    // convert (if needed) then load a GIF scene's frames, off the UI thread
    property string loadingId: ""
    Process {
        id: gifLoader
        stdout: StdioCollector {
            onStreamFinished: {
                const id = root.loadingId
                root.loading = false
                let data = null
                try { data = JSON.parse(text) } catch (e) {}
                if (!data || !data.frames || !data.frames.length) {
                    console.log("screensaver: couldn't load", id)
                    root.haveGifs = root.haveGifs.filter(f => f !== Scenes.get(id).gif)
                    root.loadScene(root.pickScene(""))
                    return
                }
                root.beginScene(id, data)
            }
        }
    }

    // warm the cache quietly so scenes don't stall the first time
    Timer {
        interval: 60000
        running: root.haveGifs.length > 0 && !root.active
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
                    + grid.cols + "x" + grid.rows + ".json\"; "
            return ["sh", "-c", sh, "sh", root.gifCache, root.converter, root.refs]
        }
    }

    function pickScene(prefer) {
        const ids = Scenes.list().filter(i => available(i))
        if (prefer && ids.indexOf(prefer) >= 0) return prefer
        // random, never one of the last few
        const recent = history.slice(-Math.min(3, ids.length - 1))
        const pool = ids.filter(i => recent.indexOf(i) < 0)
        return pool[Math.floor(Math.random() * pool.length)]
    }

    function startScenes(prefer) {
        pending = ""
        if (grid.cols < 20 || grid.rows < 10) { pending = prefer; startSoon.restart(); return }
        loadScene(pickScene(prefer))
    }

    function loadScene(id) {
        const s = Scenes.get(id)
        if (s.gif) {
            loading = true
            loadingId = id
            const out = cachePath(id)
            gifLoader.command = ["sh", "-c",
                "[ -f \"$5\" ] || { mkdir -p \"$(dirname \"$5\")\"; python3 \"$6\" \"$1\" \"$2\" \"$3\" \"$4\" \"$5\"; }; cat \"$5\"",
                "sh", refs + "/" + s.gif, String(grid.cols), String(grid.rows), grid.asp.toFixed(3), out, converter]
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
            uptime: root.ctx.uptime || "",
            title: "", sub: "", titleColor: "#ffffff", titleOpacity: 0,
            gif: gifData
        }
        const s = Scenes.get(id)
        s.init(c)
        sceneColors = s.colors.slice()
        root.ctx = c
        root.scene = s
        root.sceneTime = 0
        root.history = root.history.concat([id]).slice(-8)
        sceneFade.restart()
        root.step(0)
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
        if (sceneTime > sceneLength) loadScene(pickScene(""))
    }

    // 10 fps for drawn scenes (light on the battery); GIF scenes follow their
    // own frame timing up to 20 fps
    Timer {
        interval: root.scene && root.scene.gif ? 50 : 100
        repeat: true
        running: root.active && !root.locked && win.visible
        onTriggered: root.step(interval / 1000)
    }

    IpcHandler {
        target: "screensaver"
        function start(): void { root.pending = ""; root.forced = true; startSoon.restart() }
        function scene(id: string): void { root.pending = id; root.forced = true; startSoon.restart() }
        function stop(): void { root.forced = false }
        function list(): string { return Scenes.list().join(" ") }
    }

    // ---------------- window ----------------
    PanelWindow {
        id: win

        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-screensaver"
        // hold the keyboard while showing so the dismissing key isn't typed into an app
        WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        visible: root.active || backdrop.opacity > 0.01

        Rectangle {
            id: backdrop
            anchors.fill: parent
            color: "#050506"
            opacity: root.active ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.InOutQuad } }

            focus: root.active
            Keys.onPressed: event => { root.forced = false; event.accepted = true }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                property point last: Qt.point(-1, -1)
                onPositionChanged: mouse => {
                    // first event after appearing just records where the pointer is
                    if (last.x >= 0 && (Math.abs(mouse.x - last.x) > 3 || Math.abs(mouse.y - last.y) > 3))
                        root.forced = false
                    last = Qt.point(mouse.x, mouse.y)
                }
                onPressed: root.forced = false
                onWheel: root.forced = false
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
                onColsChanged: if (root.active && root.scene) root.loadScene(root.scene.id)

                Item {
                    id: sceneLayer
                    anchors.fill: parent

                    NumberAnimation on opacity {
                        id: sceneFade
                        from: 0; to: 1; duration: 900
                        easing.type: Easing.OutCubic
                    }

                    Repeater {
                        model: 8
                        Text {
                            required property int index
                            anchors.fill: parent
                            visible: text !== ""
                            text: root.layers[index] || ""
                            color: root.sceneColors[index] || "transparent"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            lineHeightMode: Text.FixedHeight
                            lineHeight: grid.ch
                            textFormat: Text.PlainText
                            wrapMode: Text.NoWrap
                            renderType: Text.NativeRendering
                        }
                    }

                    // title / subtitle
                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: parent.height * root.tY
                        spacing: 8
                        opacity: root.tOpacity
                        visible: root.tTitle !== ""

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: titleText.implicitWidth + 60
                            height: titleText.implicitHeight + 18
                            color: "#cc050506"
                            Text {
                                id: titleText
                                anchors.centerIn: parent
                                text: root.tTitle
                                color: root.tColor
                                font.family: Theme.fontFamily
                                font.pixelSize: 30
                                font.bold: true
                                font.letterSpacing: 6
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: text !== ""
                            text: root.tSub
                            color: root.tColor
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
                text: root.scene ? "// " + root.scene.name.toUpperCase() : ""
                color: "#3a3a44"
                font.family: Theme.fontFamily
                font.pixelSize: 17
                font.letterSpacing: 3
            }
        }
    }
}
