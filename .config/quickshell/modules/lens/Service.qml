import Quickshell
import Quickshell.Io
import QtQuick
import qs

// Lens: select and copy text from anywhere on screen, Google Lens style.
// Freezes every monitor, you drag a box round some text on any of them, tesseract
// reads it (ocr.py), and the words become selectable right where they
// are. The overlay is LensOverlay.qml; settings are in Settings > Lens, kept
// per machine in ~/.cache/quickshell/lens.json.
// Adapted from scribe (github.com/lunanoir21/scribe, MIT).
//
//   qs ipc call lens start               (Super+Shift+T on Hyprland, Mod+Shift+T on niri)
//   qs ipc call lens region X Y W H      read that box of the focused monitor, no dragging
//   qs ipc call lens select FROM TO      select words FROM..TO of an open result
//   qs ipc call lens cancel
//
// Needs grim, wl-copy, tesseract and python3 with Pillow. Reading languages
// are whatever tesseract has installed (Gentoo: L10N for app-text/tessdata_fast).
Scope {
    id: root

    // idle -> capturing -> select -> reading -> result
    property string phase: "idle"
    property var shots: ({})                       // output name -> frozen screenshot
    property var screen: null                      // the monitor the box is on
    property var kbScreen: null                    // the overlay with the keyboard (under the pointer)
    readonly property string shot: screen && shots[screen.name] ? shots[screen.name] : ""
    property rect rect: Qt.rect(0, 0, 0, 0)        // read region, logical px on `screen`
    property var words: []                         // [{ t, x, y, w, h, par, line, row, vpos }] relative to rect
    property int conf: 0
    property string error: ""
    property var pendingRegion: null               // region() read, once the screen is frozen

    signal selectRequested(int lo, int hi)
    signal keyAction(string what)                  // "all" / "copy", from whichever overlay has the keyboard
    signal beamRequested(string text)              // BEAM button: Beam.qml shows it as a QR code

    property bool available: false                 // tesseract installed
    property var installed: []                     // tesseract language codes
    readonly property string langs: {
        const want = st.langs.filter(l => installed.indexOf(l) >= 0)
        return want.length ? want.join("+") : installed.indexOf("eng") >= 0 ? "eng" : (installed[0] || "eng")
    }

    // settings
    property alias langList: st.langs              // reading languages
    property alias joinLines: st.joinLines         // join a paragraph's lines with spaces
    property alias closeAfterCopy: st.closeAfterCopy
    property alias autoCopy: st.autoCopy           // copy everything as soon as it's read
    property alias minConf: st.minConf             // below this the result is flagged as unsure

    function setLang(code, on) {
        const l = st.langs.filter(x => x !== code)
        if (on) l.push(code)
        st.langs = l
    }

    readonly property string dir: (Quickshell.env("XDG_RUNTIME_DIR") || "") + "/lens"
    readonly property string ocr: Quickshell.shellPath("modules/lens/ocr.py")

    function notify(msg) {
        Quickshell.execDetached(["notify-send", "-a", "Lens", "Lens", msg])
    }

    function region(x, y, w, h) {
        if (phase !== "idle" || w < 8 || h < 8) return
        pendingRegion = { x: x, y: y, w: w, h: h }
        start()
    }

    function start() {
        if (phase !== "idle") return
        if (!available) {
            notify("tesseract isn't installed (sudo emerge app-text/tesseract)")
            return
        }
        const name = Compositor.focusedOutput
        screen = Quickshell.screens.find(s => s.name === name) || Quickshell.screens[0] || null
        if (!screen) return
        kbScreen = screen
        error = ""
        words = []
        shots = {}
        phase = "capturing"
        // every monitor at once; names come from the compositor, keep them plain
        const names = Quickshell.screens.map(s => s.name).filter(n => /^[A-Za-z0-9._:-]{1,64}$/.test(n))
        grab.command = ["sh", "-c",
            'umask 077; [ -n "$XDG_RUNTIME_DIR" ] || exit 1; d="$XDG_RUNTIME_DIR/lens"; '
            + '[ -L "$d" ] && exit 1; mkdir -p "$d" && chmod 700 "$d" && rm -f "$d"/*.png || exit 1; '
            + 'for o; do grim -l 0 -o "$o" "$d/$o.png" & done; wait; '
            + 'for o; do [ -s "$d/$o.png" ] && printf "%s\\t%s\\n" "$o" "$d/$o.png"; done; true',
            "sh"].concat(names)
        grab.running = true
    }

    // x, y, w, h in logical px; scale = real px per logical px
    function read(x, y, w, h, scale) {
        rect = Qt.rect(x, y, w, h)
        words = []
        phase = "reading"
        watchdog.restart()
        reader.command = ["python3", "-I", ocr, shot, String(x), String(y), String(w), String(h), String(scale), langs]
        reader.running = true
    }

    // back to dragging a box over the frozen screens, on `scr`
    function reselect(scr) {
        reader.running = false
        watchdog.stop()
        words = []
        if (scr) screen = scr
        phase = "select"
    }

    function cancel() {
        phase = "idle"
        pendingRegion = null
        words = []
        watchdog.stop()
        grab.running = false
        reader.running = false
        Quickshell.execDetached(["sh", "-c", 'rm -f -- "$1"/*.png', "sh", dir])
        shots = {}
    }

    // through wl-copy's stdin, never its command line (other users can read /proc/*/cmdline)
    property string pending: ""
    function copy(text) {
        if (text === "") return
        pending = text
        copier.stdinEnabled = true
        copier.running = true
    }

    // Rows as they look on screen (across columns), and each word's place in
    // that top-to-bottom, left-to-right order: dragging selects like text.
    function visualOrder(ws) {
        const cy = w => w.y + w.h / 2
        const byY = ws.map((w, i) => i).sort((a, b) => cy(ws[a]) - cy(ws[b]))
        const rows = []
        let cur = [], mean = 0
        for (const i of byY) {
            const w = ws[i]
            const hs = cur.map(j => ws[j].h).sort((a, b) => a - b)
            const med = hs.length ? hs[hs.length >> 1] : w.h
            if (cur.length && Math.abs(cy(w) - mean) > 0.6 * Math.max(Math.min(w.h, med), 4)) {
                rows.push(cur)
                cur = []
            }
            cur.push(i)
            mean = cur.reduce((s, j) => s + cy(ws[j]), 0) / cur.length
        }
        if (cur.length) rows.push(cur)
        let n = 0
        rows.forEach((r, k) => {
            r.sort((a, b) => ws[a].x - ws[b].x)
            for (const i of r) { ws[i].row = k; ws[i].vpos = n++ }
        })
    }

    function openUrl(u) {
        if (!/^[a-z]+:\/\//i.test(u) && !/^mailto:/i.test(u)) u = "https://" + u
        Quickshell.execDetached(["xdg-open", u])
    }

    function search(text) {
        Quickshell.execDetached(["xdg-open", "https://duckduckgo.com/?q=" + encodeURIComponent(text)])
    }

    IpcHandler {
        target: "lens"
        function start(): void { root.start() }
        function region(x: real, y: real, w: real, h: real): void { root.region(x, y, w, h) }
        function select(lo: int, hi: int): void { if (root.phase === "result") root.selectRequested(lo, hi) }
        function cancel(): void { root.cancel() }
    }

    FileView {
        path: Quickshell.env("HOME") + "/.cache/quickshell/lens.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter() }

        JsonAdapter {
            id: st
            property var langs: ["eng"]
            property bool joinLines: true
            property bool closeAfterCopy: true
            property bool autoCopy: false
            property int minConf: 60
        }
    }

    // which languages tesseract can read (also tells whether it's installed)
    function refresh() { langProc.running = true }
    Component.onCompleted: refresh()
    Process {
        id: langProc
        command: ["sh", "-c", "tesseract --list-langs 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n").map(s => s.trim()).filter(s => /^[A-Za-z_]+$/.test(s) && s !== "osd")
                root.installed = l
                root.available = l.length > 0
            }
        }
    }

    // a read that never finishes must not leave a frozen screen up
    Timer {
        id: watchdog
        interval: 90000
        onTriggered: if (root.phase === "reading") { root.notify("Reading took too long"); root.cancel() }
    }

    Process {
        id: grab
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.phase !== "capturing") return
                const m = {}
                for (const l of text.split("\n")) {
                    const f = l.split("\t")
                    if (f.length === 2 && f[1] !== "") m[f[0]] = f[1]
                }
                if (!m[root.screen.name]) { root.notify("Couldn't capture the screen"); root.cancel(); return }
                root.shots = m
                root.phase = "select"
                const r = root.pendingRegion
                root.pendingRegion = null
                if (r) root.read(r.x, r.y, r.w, r.h, root.screen.devicePixelRatio)
            }
        }
        onExited: code => {
            if (code !== 0 && root.phase === "capturing") {
                root.notify("Couldn't capture the screen")
                root.cancel()
            }
        }
    }

    Process {
        id: reader
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.phase !== "reading") return          // cancelled meanwhile
                watchdog.stop()
                const out = [], pars = {}, lines = {}
                let conf = 0, err = "", np = 0, nl = 0
                for (const l of text.split("\n")) {
                    const f = l.split("\t")
                    if (f[0] === "W" && f.length >= 8 && out.length < 4000) {
                        const x = parseFloat(f[3]), y = parseFloat(f[4]), w = parseFloat(f[5]), h = parseFloat(f[6])
                        if (!isFinite(x) || !isFinite(y) || !isFinite(w) || !isFinite(h)) continue
                        if (pars[f[1]] === undefined) pars[f[1]] = np++
                        if (lines[f[2]] === undefined) lines[f[2]] = nl++
                        out.push({ par: pars[f[1]], line: lines[f[2]], x: x, y: y, w: w, h: h, t: f.slice(7).join("\t") })
                    } else if (f[0] === "CONF") conf = parseInt(f[1] || "0")
                    else if (f[0] === "ERR") err = f[1] || "fail"
                }
                if (err !== "") {
                    root.notify("Couldn't read the text (" + err + ")")
                    root.cancel()
                    return
                }
                root.conf = conf
                root.visualOrder(out)
                root.words = out
                root.phase = "result"
            }
        }
        onExited: code => {
            if (code !== 0 && root.phase === "reading") {
                root.notify("Couldn't read the text (exit " + code + ")")
                root.cancel()
            }
        }
    }

    Process {
        id: copier
        command: ["wl-copy"]
        stdinEnabled: true
        onStarted: {
            write(root.pending)
            root.pending = ""
            stdinEnabled = false        // EOF: wl-copy takes the text and keeps serving it
        }
    }
}
