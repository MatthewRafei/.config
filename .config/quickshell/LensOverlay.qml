import Quickshell
import Quickshell.Wayland
import QtQuick

// Lens overlay (state in Lens.qml). One window per monitor, each over a
// frozen screenshot of its monitor, for the whole flow:
//   select   drag a box round some text, on any monitor
//   reading  a scan line sweeps the box while tesseract reads it
//   result   the words stay where they are; drag over them to select, and a
//            toolbar above the selection copies / opens / searches it.
//            Dragging outside the box (or on another monitor) reads a new one.
// Dragging selects like text on screen: from the word you press on to the one
// under the pointer, row by row. Ctrl+drag selects just the words inside the
// dragged rectangle (one column of a table, say).
// No overlay grabs the keyboard exclusively: Hyprland would then send the
// pointer only to that one and the other monitors would be dead. Keys reach
// whichever overlay has focus and are passed on (Lens.keyAction) to the one
// with the box.
//
// Ctrl+A select all   Ctrl+C / Enter copy   right click clear   Esc close
PanelWindow {
    id: win

    required property var modelData
    screen: modelData
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    visible: img.status === Image.Ready

    // the monitor the box is on
    readonly property bool active: Lens.screen !== null && Lens.screen.name === modelData.name
    // the overlay the pointer is over (draws the crosshair)
    readonly property bool keyboard: Lens.kbScreen !== null && Lens.kbScreen.name === modelData.name

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: "quickshell-lens"

    readonly property string phase: Lens.phase
    readonly property var words: active ? Lens.words : []
    readonly property color hl: Theme.accent
    readonly property color dim: Theme.alpha(Theme.bgPanel, 0.62)

    // ---------------- region ----------------
    property real sx: 0
    property real sy: 0
    property real ex: 0
    property real ey: 0
    property real mx: -1
    property real my: -1
    property bool dragging: false          // dragging out a region
    property bool has: false               // a region is drawn
    readonly property bool boxed: active && (has || phase === "reading" || phase === "result")

    readonly property real rx: dragging || phase === "select" ? Math.min(sx, ex) : Lens.rect.x
    readonly property real ry: dragging || phase === "select" ? Math.min(sy, ey) : Lens.rect.y
    readonly property real rw: dragging || phase === "select" ? Math.abs(ex - sx) : Lens.rect.width
    readonly property real rh: dragging || phase === "select" ? Math.abs(ey - sy) : Lens.rect.height

    // ---------------- selection ----------------
    property int anchorIdx: -1
    property point pressAt: Qt.point(0, 0)  // where a word drag started, relative to the region
    property bool rectMode: false          // Ctrl+drag: words inside the rectangle
    // word indices in on-screen order (Lens.visualOrder)
    readonly property var vorder: {
        const a = []
        for (let i = 0; i < words.length; i++) a[words[i].vpos] = i
        return a
    }
    property var sel: []                   // selected word indices, in reading order
    property int hoverIdx: -1
    property bool wordDrag: false
    property bool copied: false
    property var selRects: []              // one merged box per line, relative to the region
    property rect selBox: Qt.rect(0, 0, 0, 0)

    readonly property string selText: sel.length ? textFor(sel) : ""
    // a selection that is one link or e-mail address gets an OPEN button
    readonly property string link: {
        const s = selText.trim()
        if (s === "" || /\s/.test(s)) return ""
        if (/^[\w.+-]+@[\w-]+(\.[\w-]+)+$/.test(s)) return "mailto:" + s
        if (/^(https?:\/\/|www\.)\S+$/i.test(s) || /^[\w-]+(\.[\w-]+)*\.[a-z]{2,}(\/\S*)?$/i.test(s))
            return s.replace(/[.,;:)\]]+$/, "")
        return ""
    }

    function range(lo, hi) {
        const r = []
        for (let i = lo; i <= hi; i++) r.push(i)
        return r
    }

    function setSel(idx) {
        sel = idx
        copied = false
        const rs = []
        let cur = null
        for (const i of idx) {
            const w = words[i]
            if (!w) continue
            if (cur && cur.line === w.line) {
                cur.r = Math.max(cur.r, w.x + w.w)
                cur.t = Math.min(cur.t, w.y)
                cur.b = Math.max(cur.b, w.y + w.h)
            } else {
                if (cur) rs.push(cur)
                cur = { line: w.line, l: w.x, t: w.y, r: w.x + w.w, b: w.y + w.h }
            }
        }
        if (cur) rs.push(cur)
        selRects = rs
        if (rs.length) {
            let l = 1e9, t = 1e9, r = -1e9, b = -1e9
            for (const q of rs) { l = Math.min(l, q.l); t = Math.min(t, q.t); r = Math.max(r, q.r); b = Math.max(b, q.b) }
            selBox = Qt.rect(Lens.rect.x + l, Lens.rect.y + t, r - l, b - t)
        }
    }

    function selectAll() { setSel(vorder.slice()) }

    // a word drag from the anchor word to word j (pointer at lx, ly)
    function dragTo(j, lx, ly) {
        if (!rectMode) {
            const p = words[anchorIdx].vpos, q = words[j].vpos
            setSel(vorder.slice(Math.min(p, q), Math.max(p, q) + 1))
            return
        }
        const x0 = Math.min(pressAt.x, lx), x1 = Math.max(pressAt.x, lx)
        const y0 = Math.min(pressAt.y, ly), y1 = Math.max(pressAt.y, ly)
        const r = []
        for (let i = 0; i < words.length; i++) {
            const w = words[i]
            if (w.x <= x1 && w.x + w.w >= x0 && w.y <= y1 && w.y + w.h >= y0) r.push(i)
        }
        setSel(r)
    }

    function textFor(idx) {
        let out = "", prev = null
        for (const i of idx) {
            const w = words[i]
            if (!w) continue           // words just changed under an old selection
            // a space within a line (or an on-screen row), a paragraph's lines
            // joined when that's on, otherwise a line break
            if (prev) out += w.line === prev.line || (w.row === prev.row && w.vpos === prev.vpos + 1)
                || (w.par === prev.par && Lens.joinLines) ? " " : "\n"
            out += w.t
            prev = w
        }
        return out
    }

    function doCopy() {
        if (!words.length) return
        if (!sel.length) selectAll()
        Lens.copy(textFor(sel))
        copied = true
        if (Lens.closeAfterCopy) closeTimer.restart()
    }

    function hit(px, py) {
        for (let i = 0; i < words.length; i++) {
            const w = words[i]
            if (px >= w.x - 3 && px <= w.x + w.w + 3 && py >= w.y - 2 && py <= w.y + w.h + 2) return i
        }
        return -1
    }

    // while dragging, snap to the closest word so gaps don't break the range
    function nearest(px, py) {
        let best = -1, bd = 1e9
        for (let i = 0; i < words.length; i++) {
            const w = words[i]
            const dx = Math.max(w.x - px, 0, px - (w.x + w.w)), dy = Math.max(w.y - py, 0, py - (w.y + w.h))
            const d = dx * dx + dy * dy
            if (d < bd) { bd = d; best = i }
        }
        return bd < 2500 ? best : -1
    }

    Timer { id: closeTimer; interval: 600; onTriggered: Lens.cancel() }

    Connections {
        target: Lens
        function onKeyAction(what) {
            if (!win.active) return
            if (what === "all") win.selectAll()
            else if (what === "copy") win.doCopy()
        }
        function onSelectRequested(lo, hi) {
            const n = win.words.length
            if (n && win.active) win.setSel(win.range(Math.max(0, Math.min(lo, n - 1)), Math.max(0, Math.min(hi, n - 1))))
        }
    }

    onActiveChanged: if (!active) { has = false; dragging = false; wordDrag = false; sel = []; selRects = []; hoverIdx = -1 }

    onPhaseChanged: {
        if (phase !== "result" || !active) return
        setSel([])
        hoverIdx = -1
        flash.restart()
        if (Lens.autoCopy && words.length) { selectAll(); doCopy() }
    }

    // small HUD pill button for the toolbar
    component LensButton: Rectangle {
        id: b
        property string icon
        property string label
        property bool done: false
        signal activated()
        width: bRow.implicitWidth + 22
        height: 30
        radius: Theme.radius
        color: bMouse.pressed ? Theme.alpha(win.hl, 0.25) : bMouse.containsMouse ? Theme.alpha(win.hl, 0.12) : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        Row {
            id: bRow
            anchors.centerIn: parent
            spacing: 7
            Text {
                text: b.done ? "󰄬" : b.icon
                color: b.done ? Theme.ok : bMouse.containsMouse ? win.hl : Theme.textDim
                font.family: Theme.iconFont
                font.pixelSize: 13
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: b.label
                color: b.done ? Theme.ok : bMouse.containsMouse ? win.hl : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 2
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        MouseArea {
            id: bMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: b.activated()
        }
    }

    // a dark HUD panel (toolbar, hints)
    component Pill: Rectangle {
        radius: Theme.radius
        color: Theme.alpha(Theme.bgPanel, 0.94)
        border.width: 1
        border.color: Theme.borderAccent
    }

    FocusScope {
        anchors.fill: parent
        focus: true

        HoverHandler {
            onHoveredChanged: {
                if (hovered) Lens.kbScreen = win.modelData
                else if (win.keyboard) Lens.kbScreen = null
            }
        }
        Keys.onPressed: ev => {
            const ctrl = ev.modifiers & Qt.ControlModifier
            if (ev.key === Qt.Key_Escape) Lens.cancel()
            else if (Lens.phase !== "result") return
            else if (ev.key === Qt.Key_A && ctrl) Lens.keyAction("all")
            else if ((ev.key === Qt.Key_C && ctrl) || ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) Lens.keyAction("copy")
            else return
            ev.accepted = true
        }

        // the frozen screen
        Image {
            id: img
            anchors.fill: parent
            source: Lens.shots[win.modelData.name] ? "file://" + Lens.shots[win.modelData.name] : ""
            fillMode: Image.Stretch
            cache: false
            smooth: false
        }

        // dim everything but the region
        Rectangle { visible: !win.boxed; anchors.fill: parent; color: win.dim }
        Rectangle { visible: win.boxed; width: parent.width; height: win.ry; color: win.dim }
        Rectangle { visible: win.boxed; y: win.ry + win.rh; width: parent.width; height: parent.height - y; color: win.dim }
        Rectangle { visible: win.boxed; y: win.ry; width: win.rx; height: win.rh; color: win.dim }
        Rectangle { visible: win.boxed; x: win.rx + win.rw; y: win.ry; width: parent.width - x; height: win.rh; color: win.dim }

        // crosshair before the first drag
        Rectangle { visible: win.phase === "select" && !win.boxed && win.keyboard && win.mx >= 0; x: win.mx; width: 1; height: parent.height; color: win.hl; opacity: 0.4 }
        Rectangle { visible: win.phase === "select" && !win.boxed && win.keyboard && win.my >= 0; y: win.my; width: parent.width; height: 1; color: win.hl; opacity: 0.4 }

        // region frame with HUD corner brackets
        Item {
            visible: win.boxed
            x: win.rx; y: win.ry; width: win.rw; height: win.rh
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: 1
                border.color: win.hl
                opacity: win.phase === "result" ? 0.3 : 0.8
            }
            Repeater {
                model: 4
                Item {
                    required property int index
                    readonly property bool atRight: index % 2 === 1
                    readonly property bool atBottom: index >= 2
                    x: atRight ? parent.width - 16 + 2 : -2
                    y: atBottom ? parent.height - 16 + 2 : -2
                    width: 16; height: 16
                    Rectangle { y: parent.atBottom ? 14 : 0; width: 16; height: 2; color: win.hl }
                    Rectangle { x: parent.atRight ? 14 : 0; width: 2; height: 16; color: win.hl }
                }
            }
        }

        // size tag while dragging
        Pill {
            visible: win.phase === "select" && win.boxed && win.rw > 2
            x: win.rx
            y: win.ry + win.rh + 8 + height > parent.height ? win.ry - height - 8 : win.ry + win.rh + 8
            width: sizeText.implicitWidth + 16
            height: 20
            Text {
                id: sizeText
                anchors.centerIn: parent
                text: Math.round(win.rw) + " × " + Math.round(win.rh)
                color: win.hl
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.letterSpacing: 1
            }
        }

        // top hint
        Pill {
            visible: win.phase === "select" && !win.boxed
            anchors.horizontalCenter: parent.horizontalCenter
            y: 40
            width: topHint.implicitWidth + 32
            height: 30
            Text {
                id: topHint
                anchors.centerIn: parent
                text: "// LENS    DRAG A BOX ROUND SOME TEXT    ESC CLOSE"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.letterSpacing: 2
            }
        }

        // ---------------- reading: scan line ----------------
        Item {
            visible: win.active && win.phase === "reading"
            x: win.rx; y: win.ry; width: win.rw; height: win.rh
            clip: true
            Rectangle {
                width: parent.width
                height: 48
                y: scan.y - height
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Theme.alpha(win.hl, 0.18) }
                }
            }
            Rectangle {
                id: scan
                width: parent.width
                height: 2
                color: win.hl
                SequentialAnimation on y {
                    running: win.phase === "reading"
                    loops: Animation.Infinite
                    NumberAnimation { from: 0; to: win.rh; duration: 850; easing.type: Easing.InOutQuad }
                    PauseAnimation { duration: 80 }
                }
            }
        }
        Pill {
            visible: win.active && win.phase === "reading"
            x: win.rx
            y: win.ry + win.rh + 8 + height > parent.height ? win.ry - height - 8 : win.ry + win.rh + 8
            width: readText.implicitWidth + 20
            height: 22
            Text {
                id: readText
                anchors.centerIn: parent
                text: "READING" + ".".repeat(1 + Math.floor(dots.n % 3))
                color: win.hl
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 2
            }
            Timer { id: dots; property int n: 0; interval: 300; repeat: true; running: win.phase === "reading"; onTriggered: n++ }
        }

        // ---------------- result: words ----------------
        Item {
            visible: win.active && win.phase === "result"
            x: Lens.rect.x; y: Lens.rect.y; width: Lens.rect.width; height: Lens.rect.height

            // brief flash of every word found
            Item {
                id: flashLayer
                opacity: 0
                Repeater {
                    model: win.phase === "result" ? win.words : []
                    Rectangle {
                        required property var modelData
                        x: modelData.x - 2; y: modelData.y - 1
                        width: modelData.w + 4; height: modelData.h + 2
                        radius: 2
                        color: Theme.alpha(win.hl, 0.22)
                    }
                }
            }
            SequentialAnimation {
                id: flash
                NumberAnimation { target: flashLayer; property: "opacity"; from: 0; to: 1; duration: 140 }
                PauseAnimation { duration: 260 }
                NumberAnimation { target: flashLayer; property: "opacity"; to: 0; duration: 520; easing.type: Easing.OutCubic }
            }

            // word under the pointer
            Rectangle {
                readonly property var w: win.hoverIdx >= 0 && win.hoverIdx < win.words.length ? win.words[win.hoverIdx] : null
                visible: w !== null && win.sel.length === 0
                x: w ? w.x - 2 : 0; y: w ? w.y - 1 : 0
                width: w ? w.w + 4 : 0; height: w ? w.h + 2 : 0
                radius: 2
                color: Theme.alpha(Theme.text, 0.12)
            }

            // the selection, one box per line
            Repeater {
                model: win.selRects
                Rectangle {
                    required property var modelData
                    x: modelData.l - 2; y: modelData.t - 1
                    width: modelData.r - modelData.l + 4; height: modelData.b - modelData.t + 2
                    radius: 2
                    color: Theme.alpha(win.hl, 0.38)
                }
            }
        }

        // toolbar above the selection
        Pill {
            id: bar
            z: 10
            visible: win.active && win.phase === "result" && win.sel.length > 0 && !win.wordDrag
            readonly property bool above: win.selBox.y - height - 10 >= 8
            x: Math.max(10, Math.min(win.selBox.x + win.selBox.width / 2 - width / 2, parent.width - width - 10))
            y: above ? win.selBox.y - height - 10 : win.selBox.y + win.selBox.height + 10
            width: barRow.implicitWidth + 8
            height: 38
            onVisibleChanged: if (visible) barIn.restart()
            ParallelAnimation {
                id: barIn
                NumberAnimation { target: bar; property: "opacity"; from: 0; to: 1; duration: Theme.animFast }
                NumberAnimation { target: bar; property: "scale"; from: 0.94; to: 1; duration: Theme.animMed; easing.type: Easing.OutBack }
            }
            // accent edge, like the power menu tiles
            Rectangle { x: 0; y: 6; width: 2; height: parent.height - 12; color: win.hl }

            Row {
                id: barRow
                x: 4; y: 4
                LensButton { icon: "󰆏"; label: win.copied ? "COPIED" : "COPY"; done: win.copied; onActivated: win.doCopy() }
                LensButton { visible: !win.copied; icon: "󰒆"; label: "ALL"; onActivated: win.selectAll() }
                LensButton { visible: !win.copied && win.link !== ""; icon: "󰖟"; label: "OPEN"; onActivated: { Lens.openUrl(win.link); Lens.cancel() } }
                LensButton { visible: !win.copied && win.link === ""; icon: "󰍉"; label: "SEARCH"; onActivated: { Lens.search(win.selText); Lens.cancel() } }
                // to the phone, as a QR code (Beam.qml)
                LensButton { visible: !win.copied; icon: "󰐲"; label: "BEAM"; onActivated: { const t = win.selText; Lens.cancel(); Lens.beamRequested(t) } }
            }
        }

        // status under the region
        Pill {
            visible: win.active && win.phase === "result" && !bar.visible && !win.dragging
            x: Math.max(12, Math.min(Lens.rect.x, parent.width - width - 12))
            y: Lens.rect.y + Lens.rect.height + 10 + height > parent.height ? Math.max(12, Lens.rect.y - height - 10) : Lens.rect.y + Lens.rect.height + 10
            width: statusRow.implicitWidth + 24
            height: 28
            Row {
                id: statusRow
                anchors.centerIn: parent
                spacing: 14
                Text {
                    text: win.words.length === 0 ? "NO TEXT FOUND"
                        : win.words.length + " WORDS · " + Lens.conf + "%" + (Lens.conf < Lens.minConf ? " · UNSURE" : "")
                    color: win.words.length === 0 || Lens.conf < Lens.minConf ? Theme.danger : win.hl
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 2
                }
                Text {
                    text: win.words.length === 0 ? "DRAG A NEW BOX    ESC CLOSE"
                        : "DRAG TO SELECT    ENTER COPY ALL    ESC CLOSE"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.letterSpacing: 2
                }
            }
        }

        // ---------------- input ----------------
        MouseArea {
            anchors.fill: parent
            z: -1                      // under the toolbar
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: win.phase === "result" && !win.dragging
                ? (win.hoverIdx >= 0 ? Qt.IBeamCursor : Qt.ArrowCursor) : Qt.CrossCursor

            function inRegion(x, y) {
                const r = Lens.rect
                return x >= r.x && y >= r.y && x <= r.x + r.width && y <= r.y + r.height
            }

            onPressed: mouse => {
                Lens.kbScreen = win.modelData
                if (win.phase === "capturing" || (win.phase === "reading" && win.active)) return
                if (mouse.button === Qt.RightButton) {
                    if (win.phase === "result") win.setSel([])
                    else { win.has = false; win.dragging = false }
                    return
                }
                if (win.active && win.phase === "result" && inRegion(mouse.x, mouse.y)) {
                    const lx = mouse.x - Lens.rect.x, ly = mouse.y - Lens.rect.y
                    const i = win.hit(lx, ly)
                    if (i >= 0) {
                        win.anchorIdx = i
                        win.rectMode = (mouse.modifiers & Qt.ControlModifier) !== 0
                        win.pressAt = Qt.point(lx, ly)
                        win.setSel([i])
                        win.wordDrag = true
                    } else win.setSel([])
                    return
                }
                // outside the region, or on another monitor: drag out a new one
                if (!win.active || win.phase !== "select") Lens.reselect(win.modelData)
                win.setSel([])
                win.sx = win.ex = mouse.x
                win.sy = win.ey = mouse.y
                win.dragging = true
                win.has = true
            }
            onPositionChanged: mouse => {
                win.mx = mouse.x
                win.my = mouse.y
                if (win.dragging) { win.ex = mouse.x; win.ey = mouse.y; return }
                if (win.phase !== "result" || !win.active) return
                const lx = mouse.x - Lens.rect.x, ly = mouse.y - Lens.rect.y
                win.hoverIdx = win.hit(lx, ly)
                if (win.wordDrag) {
                    const j = win.nearest(lx, ly)
                    if (j >= 0) win.dragTo(j, lx, ly)
                }
            }
            onReleased: mouse => {
                win.wordDrag = false
                if (mouse.button !== Qt.LeftButton || !win.dragging) return
                win.dragging = false
                if (win.rw > 8 && win.rh > 8)
                    Lens.read(win.rx, win.ry, win.rw, win.rh, img.sourceSize.width / win.width)
                else
                    win.has = false
            }
        }
    }
}
