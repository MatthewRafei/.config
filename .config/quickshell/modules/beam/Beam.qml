import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs

// Beam: anything you copied, as a QR code your phone can scan (after
// TouchWorkStation/Omarchy-Beam-). Fully local: the text goes monitor ->
// camera, nothing is sent anywhere. Links open, emails compose, numbers dial,
// WIFI: strings join, anything else copies.
//
// ← / → step back through the clipboard history (cliphist), so the link
// you copied ten minutes ago is two key presses away. Lens has a BEAM button
// for text read off the screen.
//
//   qs ipc call beam clipboard    what's on the clipboard (Mod+Shift+Q)
//   qs ipc call beam text "…"     anything else (Lens uses this)
//   qs ipc call beam close
//   beam [TEXT]                   the same from a terminal (~/.local/bin/beam)
PanelWindow {
    id: root
    property var service

    property bool showing: false
    property var qr: null              // beam.py output for what's shown
    property var history: []           // [{ id, preview }], newest first
    property int index: -1             // -1 = the given text / clipboard, else history[index]
    property string given: ""          // text passed in (not the clipboard)
    property bool fromClipboard: true
    property bool loading: false

    readonly property string script: Quickshell.shellPath("modules/beam/beam.py")

    function openClipboard() {
        fromClipboard = true
        given = ""
        index = -1
        qr = null
        showing = true
        encodeProc.input = ""
        encodeProc.command = ["sh", "-c", 'wl-paste --no-newline 2>/dev/null | python3 -I "$1" encode', "sh", script]
        run()
        historyProc.running = true
    }
    function openText(text) {
        fromClipboard = false
        given = text
        index = -1
        qr = null
        showing = true
        encodeText(text)
        historyProc.running = true
    }
    // the text goes in on stdin, never on a command line
    function encodeText(text) {
        encodeProc.input = text
        encodeProc.command = ["python3", "-I", script, "encode"]
        run()
    }
    function showEntry(i) {
        index = i
        if (i < 0) {
            if (fromClipboard) openClipboard()
            else encodeText(given)
            return
        }
        encodeProc.input = ""
        encodeProc.command = ["python3", "-I", script, "entry", history[i].id]
        run()
    }
    function run() {
        loading = true
        encodeProc.running = false
        encodeProc.stdinEnabled = encodeProc.input !== ""
        encodeProc.running = true
    }
    // ← older, → newer
    function step(d) {
        if (history.length === 0) return
        // the clipboard is normally history[0] already: skip the duplicate
        const first = fromClipboard ? 1 : 0
        let i = index < 0 ? (d > 0 ? first : -1) : index + d
        if (i < first && i !== -1) i = -1
        if (i >= history.length) i = history.length - 1
        if (i !== index) showEntry(i)
    }
    function close() { showing = false }

    Connections {
        // the Lens module's BEAM button
        target: Modules.service("lens")
        ignoreUnknownSignals: true
        function onBeamRequested(text) { root.openText(text) }
    }

    IpcHandler {
        target: "beam"
        function clipboard(): void { root.openClipboard() }
        function text(t: string): void { root.openText(t) }
        function close(): void { root.close() }
        function toggle(): void { if (root.showing) root.close(); else root.openClipboard() }
    }

    Process {
        id: encodeProc
        property string input: ""
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false
                try { root.qr = JSON.parse(text) } catch (e) { root.qr = { status: "empty", label: "COULDN'T MAKE A CODE", preview: "" } }
                qrCanvas.requestPaint()
            }
        }
        onStarted: if (stdinEnabled) {
            write(input)
            stdinEnabled = false
        }
    }
    Process {
        id: historyProc
        command: ["python3", "-I", root.script, "history", "30"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.history = JSON.parse(text) } catch (e) { root.history = [] } }
        }
    }

    // ------------------------------------------------------------ window
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-beam"
    WlrLayershell.keyboardFocus: showing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // mapped only while open, so it lands on the focused monitor
    visible: showing || card.opacity > 0

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        opacity: root.showing ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animMed } }
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    // modules dark on light, the finder squares in the accent, darkened
    // until it still reads as dark to a phone camera (decode-tested)
    function eyeColor() {
        let c = Theme.accent
        const lum = x => 0.2126 * x.r + 0.7152 * x.g + 0.0722 * x.b
        for (let i = 0; i < 16 && lum(c) > 0.07; i++) c = Qt.darker(c, 1.2)
        return c
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 440
        height: cardCol.implicitHeight + 56
        radius: Theme.radius
        color: Theme.bgPanel
        border.color: Theme.borderAccent
        opacity: root.showing ? 1 : 0
        scale: root.showing ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }   // clicks on the card don't close it

        // corner brackets, like the calendar and settings cards
        Rectangle { width: 40; height: 2; color: Theme.accent2; anchors { top: parent.top; left: parent.left; margins: 14 } }
        Rectangle { width: 2; height: 40; color: Theme.accent2; anchors { top: parent.top; left: parent.left; margins: 14 } }
        Rectangle { width: 40; height: 2; color: Theme.accent2; anchors { bottom: parent.bottom; right: parent.right; margins: 14 } }
        Rectangle { width: 2; height: 40; color: Theme.accent2; anchors { bottom: parent.bottom; right: parent.right; margins: 14 } }

        focus: root.showing
        Keys.onPressed: ev => {
            if (ev.key === Qt.Key_Escape || ev.key === Qt.Key_Return || ev.key === Qt.Key_Q) root.close()
            else if (ev.key === Qt.Key_Left || ev.key === Qt.Key_H) root.step(1)
            else if (ev.key === Qt.Key_Right || ev.key === Qt.Key_L) root.step(-1)
            else return
            ev.accepted = true
        }

        Column {
            id: cardCol
            anchors.top: parent.top
            anchors.topMargin: 28
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 64
            spacing: 14

            Item {
                width: parent.width
                height: 16
                Text {
                    text: "// BEAM"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.letterSpacing: 3
                }
                Text {
                    anchors.right: parent.right
                    text: root.index < 0 ? (root.fromClipboard ? "CLIPBOARD" : "SELECTION")
                        : "HISTORY  " + (root.index + 1) + " / " + root.history.length
                    color: root.index < 0 ? Theme.textFaint : Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.letterSpacing: 2
                }
            }

            // the code
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 320
                height: 320
                radius: Theme.radius
                color: root.qr && root.qr.status === "ok" ? "#f6f3f5" : Theme.bgCard
                border.color: Theme.border

                Canvas {
                    id: qrCanvas
                    anchors.fill: parent
                    visible: root.qr !== null && root.qr.status === "ok"
                    opacity: root.loading ? 0.25 : 1
                    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        const q = root.qr
                        if (!q || q.status !== "ok") return
                        const n = q.size, quiet = 4
                        const m = Math.floor(width / (n + 2 * quiet))     // whole pixels per module
                        const off = Math.floor((width - m * n) / 2)
                        const eye = root.eyeColor()
                        const inEye = (r, c) => (r < 7 && c < 7) || (r < 7 && c >= n - 7) || (r >= n - 7 && c < 7)
                        ctx.fillStyle = "#0b0a0b"
                        for (let r = 0; r < n; r++) {
                            const row = q.rows[r]
                            for (let c = 0; c < n; c++)
                                if (row[c] === "1" && !inEye(r, c)) ctx.fillRect(off + c * m, off + r * m, m, m)
                        }
                        // finder squares in the accent; kept square, since rounded
                        // ones stop stricter decoders (OpenCV) finding the code
                        for (const [r0, c0] of [[0, 0], [0, n - 7], [n - 7, 0]]) {
                            const x = off + c0 * m, y = off + r0 * m
                            ctx.fillStyle = eye
                            ctx.fillRect(x, y, 7 * m, 7 * m)
                            ctx.fillStyle = "#f6f3f5"
                            ctx.fillRect(x + m, y + m, 5 * m, 5 * m)
                            ctx.fillStyle = eye
                            ctx.fillRect(x + 2 * m, y + 2 * m, 3 * m, 3 * m)
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    visible: root.qr === null || root.qr.status !== "ok"
                    spacing: 8
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.qr === null ? "󰐲" : "󰅙"
                        color: Theme.textFaint
                        font.family: Theme.iconFont
                        font.pixelSize: 42
                    }
                }
            }

            // what it is
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.qr !== null && root.qr.status === "ok"
                    text: ({ url: "󰖟", email: "󰇮", tel: "󰏲", wifi: "󰖩", text: "󰅍" })[root.qr ? root.qr.kind : ""] || ""
                    color: Theme.accent
                    font.family: Theme.iconFont
                    font.pixelSize: 16
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.qr ? root.qr.label : "…"
                    color: root.qr && root.qr.status !== "ok" ? Theme.danger : Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.bold: true
                    font.letterSpacing: 3
                }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 3
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: root.qr ? root.qr.preview : ""
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }

            Rectangle { width: parent.width; height: 1; color: Theme.border }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: (root.history.length > 1 ? "← →  HISTORY    " : "") + "ESC  CLOSE    NOTHING IS SENT"
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 8
                font.letterSpacing: 2
            }
        }
    }
}
