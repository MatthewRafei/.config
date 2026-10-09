import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import QtQuick
import qs

// Screen recording with wf-recorder, for the bar's REC chip and the recorder
// page of the quick panel (QuickPanel.qml). A whole monitor or a region you
// drag out (no slurp needed), with optional desktop audio or microphone.
// Files go to ~/Videos/Recordings.
//
//   qs ipc call recorder toggle    start (3 s countdown) / stop
//   qs ipc call recorder area      drag out an area, then record it
//   qs ipc call recorder panel     open the recorder panel
//   qs ipc call recorder stop
Scope {
    id: root

    property bool available: false        // wf-recorder installed
    readonly property string dir: Quickshell.env("HOME") + "/Videos/Recordings"

    // settings, kept for the session
    property string output: ""            // monitor name, "" = the first one
    property string mode: "screen"        // screen | region
    property string audio: "none"         // none | desktop | mic
    property rect region: Qt.rect(0, 0, 0, 0)   // in the chosen screen's coordinates
    property bool picking: false          // the region picker is up

    property string state: "idle"         // idle | countdown | recording | saving
    readonly property bool active: state !== "idle"
    property int countdown: 0
    property real startedAt: 0
    property int elapsed: 0               // seconds
    property string file: ""
    property string error: ""
    property var recent: []               // newest first: [{ path, name, size }]

    readonly property string clock: {
        const m = Math.floor(elapsed / 60), s = elapsed % 60
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
    }

    signal saved(string path)
    signal failed(string why)

    function screenName() {
        if (output !== "" && Quickshell.screens.some(s => s.name === output)) return output
        return Quickshell.screens.length ? Quickshell.screens[0].name : ""
    }
    readonly property var screen: Quickshell.screens.find(s => s.name === screenName()) || null
    // a size in real pixels, as it will be in the file ("1920 × 1200")
    function px(w, h, scr) {
        const k = scr ? scr.devicePixelRatio : 1
        return Math.round(w * k) + " × " + Math.round(h * k)
    }

    function toggle() {
        if (state === "idle") start()
        else stop()
    }

    function start() {
        if (!available || state !== "idle" || picking) return
        error = ""
        if (mode === "region") { picking = true; return }   // the countdown starts once a box is drawn
        startCountdown()
    }

    function regionPicked(r) {
        picking = false
        if (r.width < 16 || r.height < 16) return
        // multiples of 8, so the size stays even once scaled to real pixels
        // (the H.264 encoder rejects odd widths and heights)
        region = Qt.rect(Math.round(r.x), Math.round(r.y), Math.floor(r.width / 8) * 8, Math.floor(r.height / 8) * 8)
        startCountdown()
    }

    function startCountdown() {
        countdown = 3
        state = "countdown"
        tick.restart()
    }

    function stop() {
        if (picking) { picking = false; return }
        if (state === "countdown") { tick.stop(); state = "idle"; return }
        if (state === "recording") { state = "saving"; proc.signal(2) }   // SIGINT: finish the file
    }

    function stamp() {
        return Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss")
    }

    function begin() {
        const out = screenName()
        file = dir + "/Recording_" + stamp() + ".mp4"
        const args = ["wf-recorder", "-y", "-f", file]
        if (mode === "region" && screen) {
            // wf-recorder wants the box in global (layout) coordinates
            const g = (screen.x + region.x) + "," + (screen.y + region.y) + " " + region.width + "x" + region.height
            args.push("-g", g)
        } else args.push("-o", out)
        const sink = Pipewire.defaultAudioSink, src = Pipewire.defaultAudioSource
        if (audio === "desktop" && sink) args.push("--audio=" + sink.name + ".monitor")
        if (audio === "mic" && src) args.push("--audio=" + src.name)
        // wf-recorder stops cleanly (SIGINT) when we ask, and on its own if
        // the shell goes away, so a recording never runs on unnoticed
        proc.command = ["sh", "-c",
            'mkdir -p "$1"; shift; trap \'kill -INT "$p" 2>/dev/null\' INT TERM; "$@" & p=$!; '
            + 'while kill -0 "$p" 2>/dev/null; do kill -0 "$PPID" 2>/dev/null || kill -INT "$p"; '
            + 'sleep 1 & wait $!; done; wait "$p"',
            "sh", dir].concat(args)
        startedAt = Date.now()
        elapsed = 0
        state = "recording"
        proc.running = true
    }

    function open(path) { Quickshell.execDetached(["xdg-open", path || dir]) }
    function refreshRecent() { if (!list.running) list.running = true }

    Timer {
        id: tick
        interval: 1000
        repeat: true
        onTriggered: {
            if (root.state === "countdown") {
                root.countdown--
                if (root.countdown <= 0) { stop(); root.begin() }
            } else if (root.state === "recording") {
                root.elapsed = Math.floor((Date.now() - root.startedAt) / 1000)
            } else stop()
        }
    }
    // the clock keeps running while recording
    Binding { target: tick; property: "running"; value: true; when: root.state === "recording" }

    Process {
        id: proc
        stderr: StdioCollector { id: errOut }
        onExited: code => {
            root.elapsed = Math.round((Date.now() - root.startedAt) / 1000)
            root.state = "idle"
            check.path = root.file
            check.running = true
        }
    }

    // did a file actually come out?
    Process {
        id: check
        property string path
        command: ["sh", "-c", 'test -s "$1"', "sh", path]
        onExited: code => {
            if (code === 0) { root.saved(path); notify.send(path) }
            else {
                const t = errOut.text.trim().split("\n").filter(l => /error|fail|cannot|invalid/i.test(l))
                root.error = t.length ? t[t.length - 1] : "wf-recorder stopped without saving a file"
                root.failed(root.error)
            }
            root.refreshRecent()
        }
    }

    Process {
        id: notify
        function send(path) {
            const name = path.split("/").pop()
            command = ["busctl", "--user", "call", "org.freedesktop.Notifications",
                       "/org/freedesktop/Notifications", "org.freedesktop.Notifications", "Notify",
                       "susssasa{sv}i", "Screen recorder", "0", "media-record",
                       "Recording saved", name + "  ·  " + root.clock + "  ·  ~/Videos/Recordings",
                       "0", "0", "5000"]
            running = true
        }
    }

    Process {
        id: list
        command: ["sh", "-c", 'cd "$1" 2>/dev/null || exit 0; ls -t -- *.mp4 *.mkv 2>/dev/null | head -n 4 | '
                  + 'while IFS= read -r f; do printf "%s\\t%s\\n" "$f" "$(du -h -- "$f" | cut -f1)"; done', "sh", root.dir]
        stdout: StdioCollector {
            onStreamFinished: root.recent = text.split("\n").filter(l => l !== "").map(l => {
                const p = l.split("\t")
                return { name: p[0], path: root.dir + "/" + p[0], size: p[1] || "" }
            })
        }
    }

    Process {
        running: true
        command: ["sh", "-c", "command -v wf-recorder"]
        onExited: code => { root.available = code === 0; if (root.available) root.refreshRecent() }
    }

    // ------------------------------------------------ region picker
    LazyLoader {
        active: root.picking && root.screen !== null
        PanelWindow {
            id: picker
            screen: root.screen
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell-recorder-pick"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            property point a: Qt.point(-1, -1)
            property point b: Qt.point(-1, -1)
            readonly property bool has: a.x >= 0
            readonly property rect box: Qt.rect(Math.min(a.x, b.x), Math.min(a.y, b.y),
                                                Math.abs(b.x - a.x), Math.abs(b.y - a.y))

            // dim everything except the box
            Rectangle { x: 0; y: 0; width: parent.width; height: picker.has ? picker.box.y : parent.height; color: Theme.alpha("#000000", 0.45) }
            Rectangle { visible: picker.has; x: 0; y: picker.box.y + picker.box.height; width: parent.width; height: parent.height - y; color: Theme.alpha("#000000", 0.45) }
            Rectangle { visible: picker.has; x: 0; y: picker.box.y; width: picker.box.x; height: picker.box.height; color: Theme.alpha("#000000", 0.45) }
            Rectangle { visible: picker.has; x: picker.box.x + picker.box.width; y: picker.box.y; width: parent.width - x; height: picker.box.height; color: Theme.alpha("#000000", 0.45) }

            Rectangle {
                visible: picker.has
                x: picker.box.x - 1; y: picker.box.y - 1
                width: picker.box.width + 2; height: picker.box.height + 2
                color: "transparent"
                border.color: Theme.accent
                border.width: 1
            }

            // size tag under the box
            Rectangle {
                visible: picker.has && picker.box.width > 0
                x: picker.box.x
                y: Math.min(picker.box.y + picker.box.height + 6, parent.height - height - 6)
                width: sizeText.implicitWidth + 14
                height: 20
                radius: Theme.radius
                color: Theme.alpha(Theme.bgPanel, 0.94)
                border.color: Theme.border
                Text {
                    id: sizeText
                    anchors.centerIn: parent
                    text: root.px(Math.floor(picker.box.width / 8) * 8, Math.floor(picker.box.height / 8) * 8, root.screen)
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }
            }

            // hint
            Rectangle {
                visible: !picker.has
                anchors.centerIn: parent
                width: hint.implicitWidth + 32
                height: 40
                radius: Theme.radius
                color: Theme.alpha(Theme.bgPanel, 0.94)
                border.color: Theme.border
                Text {
                    id: hint
                    anchors.centerIn: parent
                    text: "DRAG TO PICK AN AREA  ·  ESC CANCELS"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.letterSpacing: 3
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.CrossCursor
                focus: true
                Keys.onEscapePressed: root.picking = false
                onPressed: m => { picker.a = Qt.point(m.x, m.y); picker.b = picker.a }
                onPositionChanged: m => { if (pressed) picker.b = Qt.point(m.x, m.y) }
                onReleased: root.regionPicked(picker.box)
            }
        }
    }

    // ------------------------------------------------ outline while recording a region
    // drawn just outside the box, so it never ends up in the video
    LazyLoader {
        active: root.state !== "idle" && root.mode === "region" && root.screen !== null && root.region.width > 0
        PanelWindow {
            screen: root.screen
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}                       // clicks go straight through
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell-recorder-outline"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Rectangle {
                x: root.region.x - 2; y: root.region.y - 2
                width: root.region.width + 4; height: root.region.height + 4
                color: "transparent"
                border.width: 2
                border.color: root.state === "recording" ? Theme.danger : Theme.textDim
            }
        }
    }

    IpcHandler {
        target: "recorder"
        function toggle(): void { root.toggle() }
        function area(): void { if (root.state === "idle") { root.mode = "region"; root.start() } else root.stop() }
        function stop(): void { root.stop() }
        function panel(): void { Quickshell.execDetached(["qs", "ipc", "call", "quick", "rec"]) }
        function status(): string { return root.state + (root.state === "recording" ? " " + root.clock : "") }
    }
}
