import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.widgets

// Typing test for Settings > Keyboard, after LeoMoon's Omarchy Typing Test
// (passages: passages.json, CC0). Timed, word-count and one-passage
// tests; live WPM; results with accuracy, consistency, a per-second chart and
// the keys you missed; history, personal best and a heatmap of missed keys
// across every test (~/.cache/quickshell/typing-test.json).
//
// Click the text box (or START) to focus it. Tab: new text  ·  Shift+Tab: same
// text again. Esc still closes Settings. Space mid-word skips to the next
// word, so one missed or extra letter doesn't throw off the rest.
//
// WPM = correctly typed characters / 5 per minute; raw counts every character;
// accuracy = keystrokes that were right the first time / all keystrokes;
// consistency = 100 - coefficient of variation of per-second raw WPM.
Item {
    id: tt

    implicitHeight: col.implicitHeight

    // -------------------------------------------------------------- options
    property string mode: "time"      // time | words | quote
    property int amount: 30           // seconds or words
    property string content: "prose"  // words | prose | code | symbols

    readonly property var modes: [
        { l: "15S", m: "time", a: 15 }, { l: "30S", m: "time", a: 30 }, { l: "60S", m: "time", a: 60 }, { l: "2M", m: "time", a: 120 },
        { l: "25W", m: "words", a: 25 }, { l: "50W", m: "words", a: 50 }, { l: "100W", m: "words", a: 100 },
        { l: "QUOTE", m: "quote", a: 0 }
    ]
    readonly property var contents: [
        { l: "WORDS", v: "words" }, { l: "PROSE", v: "prose" }, { l: "CODE", v: "code" }, { l: "SYMBOLS", v: "symbols" }
    ]

    // -------------------------------------------------------------- test state
    property var passages: null
    property string target: ""
    property string typed: ""
    property bool running: false
    property bool done: false
    property real startMs: 0
    property real elapsed: 0          // seconds
    property int keystrokes: 0
    property int misses: 0
    property var keyRun: ({})         // char -> [hits, misses], this test
    property var samples: []          // typed chars at the end of each second
    property var result: null

    readonly property bool focused: catcher.activeFocus
    readonly property int correct: {
        let n = 0
        for (let i = 0; i < typed.length; i++) if (typed[i] === target[i]) n++
        return n
    }
    readonly property real liveWpm: elapsed > 0.5 ? correct / 5 / (elapsed / 60) : 0
    readonly property real liveAcc: keystrokes ? (keystrokes - misses) / keystrokes * 100 : 100

    // -------------------------------------------------------------- saved data
    property var history: []          // newest last: { at, mode, amount, content, wpm, raw, acc, cons, secs }
    property var keyStats: ({})       // lowercase char -> [hits, misses], all tests
    readonly property var best: history.reduce((b, r) => !b || r.wpm > b.wpm ? r : b, null)
    readonly property real avg10: {
        const l = history.slice(-10)
        return l.length ? l.reduce((s, r) => s + r.wpm, 0) / l.length : 0
    }

    FileView {
        id: store
        path: Quickshell.env("HOME") + "/.cache/quickshell/typing-test.json"
        onLoaded: {
            try {
                const d = JSON.parse(text())
                tt.history = d.history || []
                tt.keyStats = d.keys || {}
            } catch (e) {}
        }
    }
    function save() { store.setText(JSON.stringify({ history: history, keys: keyStats })) }

    FileView {
        path: Quickshell.shellPath("modules/typing-test/passages.json")
        onLoaded: { try { tt.passages = JSON.parse(text()); tt.reset(true) } catch (e) {} }
    }

    // -------------------------------------------------------------- text
    function shuffled(a) {
        a = a.slice()
        for (let i = a.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1))
            const t = a[i]; a[i] = a[j]; a[j] = t
        }
        return a
    }
    function pool() {
        const p = passages
        return content === "code" ? p.programming : content === "symbols" ? p.punctuation : p.common.concat(p.literature)
    }
    // plain lowercase words from the everyday passages
    property var wordList: []
    function words() {
        if (!wordList.length) {
            const seen = {}
            for (const e of passages.common)
                for (const w of e[1].toLowerCase().replace(/[^a-z' ]/g, " ").split(/\s+/))
                    if (w.length > 1 && w.indexOf("'") < 0) seen[w] = true
            wordList = Object.keys(seen)
        }
        const out = []
        for (let i = 0; i < 60; i++) out.push(wordList[Math.floor(Math.random() * wordList.length)])
        return out.join(" ")
    }
    // more text than the test can use (timed tests get more as they go)
    function more() {
        if (content === "words") return words()
        return shuffled(pool()).slice(0, 4).map(e => e[1]).join(" ")
    }
    function makeText() {
        if (mode === "quote") {
            const p = content === "words" ? [[1, words().split(" ").slice(0, 30).join(" ")]] : pool()
            return p[Math.floor(Math.random() * p.length)][1]
        }
        let t = more()
        if (mode === "words") {
            while (t.split(" ").length < amount) t += " " + more()
            return t.split(" ").slice(0, amount).join(" ")
        }
        return t
    }

    // fresh: new text; otherwise the same text again
    function reset(fresh) {
        if (!passages) return
        if (fresh || !target) target = makeText()
        typed = ""
        running = false
        done = false
        elapsed = 0
        keystrokes = 0
        misses = 0
        keyRun = {}
        samples = []
        result = null
        view.contentY = 0
    }
    function setOptions(m, a, c) {
        mode = m; amount = a; content = c
        reset(true)
        catcher.forceActiveFocus()
    }

    // -------------------------------------------------------------- typing
    function type(ch) {
        if (done || !target) return
        if (!running) { running = true; startMs = Date.now() }
        const want = target[typed.length]
        keystrokes++
        const k = keyRun[want] || [0, 0]
        if (ch === want) k[0]++
        else { k[1]++; misses++ }
        keyRun[want] = k
        // space in the middle of a word skips to the next one (the rest of the
        // word counts as wrong), so a missed or extra letter doesn't shift
        // everything after it
        // and a letter where a space belongs is an extra: it counts as a miss
        // but the caret waits on the space
        if (want === " " && ch !== " ") return
        if (ch === " " && want !== " ") {
            let j = target.indexOf(" ", typed.length)
            if (j < 0) j = target.length
            typed += "\u0001".repeat(j - typed.length) + (j < target.length ? " " : "")
        } else typed += ch
        if (mode === "time" && target.length - typed.length < 120) target += " " + more()
        if (mode !== "time" && typed.length >= target.length) finish()
    }
    function backspace(word) {
        if (done || !typed.length) return
        if (!word) { typed = typed.slice(0, -1); return }
        let i = typed.length
        while (i > 0 && typed[i - 1] === " ") i--
        while (i > 0 && typed[i - 1] !== " ") i--
        typed = typed.slice(0, i)
    }

    Timer {
        interval: 100
        repeat: true
        running: tt.running && !tt.done
        onTriggered: {
            tt.elapsed = (Date.now() - tt.startMs) / 1000
            while (tt.samples.length < Math.floor(tt.elapsed)) tt.samples = tt.samples.concat([tt.typed.length])
            if (tt.mode === "time" && tt.elapsed >= tt.amount) { tt.elapsed = tt.amount; tt.finish() }
        }
    }
    // a test left alone for 30 s is abandoned
    Timer {
        id: idleTimer
        interval: 30000
        running: tt.running && !tt.done
        onTriggered: tt.reset(false)
    }
    onTypedChanged: if (running) idleTimer.restart()

    function finish() {
        if (done) return
        elapsed = mode === "time" ? amount : (Date.now() - startMs) / 1000
        running = false
        done = true
        const min = Math.max(elapsed, 0.5) / 60
        // per-second raw WPM, for the chart and consistency
        const per = []
        let prev = 0
        const s = samples.concat([typed.length])
        for (const n of s) { per.push((n - prev) / 5 * 60); prev = n }
        const mean = per.reduce((a, b) => a + b, 0) / per.length
        const sd = Math.sqrt(per.reduce((a, b) => a + (b - mean) * (b - mean), 0) / per.length)
        const missed = Object.keys(keyRun).filter(k => keyRun[k][1] > 0)
            .sort((a, b) => keyRun[b][1] - keyRun[a][1]).slice(0, 6)
            .map(k => ({ k: k, n: keyRun[k][1] }))
        const r = {
            at: Date.now(), mode: mode, amount: amount, content: content,
            wpm: Math.round(correct / 5 / min), raw: Math.round(typed.length / 5 / min),
            acc: Math.round(liveAcc * 10) / 10,
            cons: mean > 0 ? Math.max(0, Math.round(100 - sd / mean * 100)) : 0,
            secs: Math.round(elapsed)
        }
        const pb = !best || r.wpm > best.wpm
        result = Object.assign({ per: per, missed: missed, pb: pb && history.length > 0, chars: correct + "/" + typed.length }, r)
        // tests under 5 s (a stray key, then Tab) aren't worth keeping
        if (elapsed < 5) return
        history = history.concat([r]).slice(-200)
        const ks = Object.assign({}, keyStats)
        for (const k in keyRun) {
            const c = k.toLowerCase()
            const v = ks[c] || [0, 0]
            v[0] += keyRun[k][0]; v[1] += keyRun[k][1]
            ks[c] = v
        }
        keyStats = ks
        save()
    }

    // -------------------------------------------------------------- render
    function esc(c) { return c === "&" ? "&amp;" : c === "<" ? "&lt;" : c === ">" ? "&gt;" : c }
    // the text as rich text: typed right, typed wrong, the caret, the rest
    function html() {
        const ok = Theme.css(Theme.text), bad = Theme.css(Theme.danger), rest = Theme.css(Theme.textFaint)
        const badBg = Theme.css(Theme.alpha(Theme.danger, 0.25)), caretBg = Theme.css(Theme.alpha(Theme.accent, tt.focused ? 0.45 : 0.15))
        let out = "", run = "", cls = ""
        const flush = () => {
            if (!run) return
            out += cls === "ok" ? "<span style=\"color:" + ok + "\">" + run + "</span>"
                 : cls === "bad" ? "<span style=\"color:" + bad + ";background-color:" + badBg + "\">" + run + "</span>"
                 : "<span style=\"color:" + rest + "\">" + run + "</span>"
            run = ""
        }
        const n = typed.length
        for (let i = 0; i < n; i++) {
            const c = typed[i] === target[i] ? "ok" : "bad"
            if (c !== cls) { flush(); cls = c }
            run += esc(target[i])
        }
        flush()
        if (n < target.length)
            out += "<span style=\"color:" + Theme.css(Theme.text) + ";background-color:" + caretBg + "\">" + esc(target[n]) + "</span>"
        cls = "rest"
        run = target.slice(n + 1).replace(/[&<>]/g, esc)
        flush()
        return out
    }

    // ------------------------------------------------------------------ pieces
    component Stat: Column {
        property string label
        property string value
        property color tint: Theme.text
        property bool big: false
        spacing: 2
        Text {
            text: parent.value
            color: parent.tint
            font.family: Theme.fontFamily
            font.pixelSize: parent.big ? 30 : 16
            font.bold: true
        }
        Text {
            text: parent.label
            color: Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: 9
            font.letterSpacing: 2
        }
    }

    Column {
        id: col
        width: parent.width
        spacing: 10

        // ---------------- options
        Flow {
            width: parent.width
            spacing: 4
            Repeater {
                model: tt.modes
                HudButton {
                    required property var modelData
                    label: modelData.l
                    on: tt.mode === modelData.m && (modelData.m === "quote" || tt.amount === modelData.a)
                    onClicked: tt.setOptions(modelData.m, modelData.a, tt.content)
                }
            }
            Item { width: 14; height: 26 }
            Repeater {
                model: tt.contents
                HudButton {
                    required property var modelData
                    label: modelData.l
                    on: tt.content === modelData.v
                    onClicked: tt.setOptions(tt.mode, tt.amount, modelData.v)
                }
            }
        }

        // ---------------- live line
        Row {
            spacing: 22
            height: 20
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tt.mode === "time" ? Math.max(0, Math.ceil(tt.amount - tt.elapsed)) + "s"
                    : tt.mode === "words" ? tt.typed.split(" ").filter(x => x).length + "/" + tt.amount
                    : Math.floor(tt.elapsed) + "s"
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: 16
                font.bold: true
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(tt.liveWpm) + " WPM   " + Math.round(tt.liveAcc) + "%"
                color: tt.running ? Theme.text : Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.letterSpacing: 1
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tt.done ? "" : !tt.focused ? "click the text to start"
                    : tt.running ? "tab: new text  ·  shift+tab: restart" : "start typing  ·  tab: new text"
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }
        }

        // ---------------- the text (3 lines, scrolls with the caret)
        Rectangle {
            id: box
            visible: !tt.done
            width: parent.width
            height: view.height + 28
            radius: Theme.radius
            color: Theme.alpha(Theme.text, 0.03)
            border.color: tt.focused ? Theme.accent : Theme.border

            Item {
                id: catcher
                Keys.onPressed: event => {
                    event.accepted = true
                    const ctrl = event.modifiers & Qt.ControlModifier
                    if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) tt.reset(false)
                    else if (event.key === Qt.Key_Tab) tt.reset(true)
                    else if (event.key === Qt.Key_Backspace) tt.backspace(ctrl || (event.modifiers & Qt.AltModifier))
                    else if (event.text.length === 1 && event.text >= " " && event.text !== "\x7f" && !ctrl && !(event.modifiers & Qt.AltModifier)) tt.type(event.text)
                    else event.accepted = false
                }
            }

            Flickable {
                id: view
                x: 18
                y: 14
                width: parent.width - 36
                height: lineH * 3
                interactive: false
                clip: true
                contentWidth: width
                contentHeight: te.height
                readonly property real lineH: Math.max(1, te.positionToRectangle(0).height)
                // keep the caret on the middle line
                readonly property int caretLine: Math.floor(te.positionToRectangle(tt.typed.length).y / lineH + 0.01)
                Binding on contentY { value: Math.max(0, view.caretLine - 1) * view.lineH }
                Behavior on contentY { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

                TextEdit {
                    id: te
                    width: view.width
                    readOnly: true
                    activeFocusOnPress: false
                    selectByMouse: false
                    textFormat: TextEdit.RichText
                    wrapMode: TextEdit.Wrap
                    text: tt.html()
                    font.family: Theme.fontFamily
                    font.pixelSize: 19
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.IBeamCursor
                onClicked: catcher.forceActiveFocus()
            }
        }

        // ---------------- results
        Rectangle {
            visible: tt.done && tt.result !== null
            width: parent.width
            height: res.implicitHeight + 28
            radius: Theme.radius
            color: "transparent"
            border.color: tt.result && tt.result.pb ? Theme.accent : Theme.border

            Column {
                id: res
                x: 18
                y: 14
                width: parent.width - 36
                spacing: 12

                Row {
                    spacing: 30
                    Stat { big: true; label: tt.result && tt.result.pb ? "WPM  ·  NEW BEST" : "WPM"; value: tt.result ? tt.result.wpm : ""; tint: Theme.accent }
                    Stat { big: true; label: "ACCURACY"; value: tt.result ? tt.result.acc + "%" : "" }
                    Stat { label: "RAW"; value: tt.result ? tt.result.raw : "" }
                    Stat { label: "CONSISTENCY"; value: tt.result ? tt.result.cons + "%" : "" }
                    Stat { label: "CHARACTERS"; value: tt.result ? tt.result.chars : "" }
                    Stat { label: "TIME"; value: tt.result ? tt.result.secs + "s" : "" }
                }

                // raw WPM each second
                Canvas {
                    id: chart
                    width: parent.width
                    height: 70
                    property var per: tt.result ? tt.result.per : []
                    onPerChanged: requestPaint()
                    onPaint: {
                        const c = getContext("2d")
                        c.reset()
                        const p = per
                        if (p.length < 2) return
                        const max = Math.max.apply(null, p.concat([20]))
                        const xs = i => i / (p.length - 1) * (width - 2) + 1
                        const ys = v => height - 2 - v / max * (height - 6)
                        c.strokeStyle = Theme.css(Theme.alpha(Theme.text, 0.12))
                        c.lineWidth = 1
                        c.beginPath(); c.moveTo(0, ys(tt.result.wpm)); c.lineTo(width, ys(tt.result.wpm)); c.stroke()
                        c.strokeStyle = Theme.css(Theme.accent)
                        c.lineWidth = 2
                        c.beginPath()
                        p.forEach((v, i) => i ? c.lineTo(xs(i), ys(v)) : c.moveTo(xs(i), ys(v)))
                        c.stroke()
                    }
                }

                Row {
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: tt.result && tt.result.missed.length ? "MISSED" : "NO MISSED KEYS"
                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.letterSpacing: 2
                    }
                    Repeater {
                        model: tt.result ? tt.result.missed : []
                        Rectangle {
                            required property var modelData
                            width: mk.implicitWidth + 12
                            height: 20
                            radius: Theme.radius
                            color: Theme.alpha(Theme.danger, 0.12)
                            border.color: Theme.alpha(Theme.danger, 0.6)
                            Text {
                                id: mk
                                anchors.centerIn: parent
                                text: (modelData.k === " " ? "space" : modelData.k) + " ×" + modelData.n
                                color: Theme.danger
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                            }
                        }
                    }
                }

                Row {
                    spacing: 6
                    HudButton { label: "NEXT  (TAB)"; on: true; onClicked: { tt.reset(true); catcher.forceActiveFocus() } }
                    HudButton { label: "SAME TEXT  (SHIFT+TAB)"; onClicked: { tt.reset(false); catcher.forceActiveFocus() } }
                }
            }
        }

        // ---------------- history
        Row {
            visible: tt.history.length > 0
            spacing: 28
            Stat { label: "BEST"; value: tt.best ? tt.best.wpm + " wpm" : ""; tint: Theme.accent }
            Stat { label: "LAST 10 AVG"; value: Math.round(tt.avg10) + " wpm" }
            Stat { label: "TESTS"; value: tt.history.length }
            Stat {
                label: "AVG ACCURACY"
                value: (tt.history.slice(-10).reduce((s, r) => s + r.acc, 0) / Math.max(1, tt.history.slice(-10).length)).toFixed(1) + "%"
            }
            // WPM over the last 30 tests
            Canvas {
                id: spark
                width: 220
                height: 34
                property var pts: tt.history.slice(-30).map(r => r.wpm)
                onPtsChanged: requestPaint()
                onPaint: {
                    const c = getContext("2d")
                    c.reset()
                    const p = pts
                    if (p.length < 2) return
                    const lo = Math.min.apply(null, p) - 5, hi = Math.max.apply(null, p) + 5
                    c.strokeStyle = Theme.css(Theme.accent)
                    c.lineWidth = 1.5
                    c.beginPath()
                    p.forEach((v, i) => {
                        const x = i / (p.length - 1) * (width - 4) + 2, y = height - 2 - (v - lo) / (hi - lo) * (height - 4)
                        i ? c.lineTo(x, y) : c.moveTo(x, y)
                    })
                    c.stroke()
                }
            }
        }

        // ---------------- missed-key heatmap, every test so far
        Column {
            visible: Object.keys(tt.keyStats).length > 0
            spacing: 4
            Text {
                text: "MISSED KEYS  ·  ALL TESTS"
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.letterSpacing: 2
                bottomPadding: 2
            }
            Repeater {
                model: ["`1234567890-=", "qwertyuiop[]\\", "asdfghjkl;'", "zxcvbnm,./"]
                Row {
                    id: kr
                    required property string modelData
                    required property int index
                    spacing: 3
                    leftPadding: [0, 14, 22, 36][index]
                    Repeater {
                        model: kr.modelData.split("")
                        Rectangle {
                            required property string modelData
                            // shifted symbols count against their key
                            readonly property var s: {
                                const shift = { "`": "~", "1": "!", "2": "@", "3": "#", "4": "$", "5": "%", "6": "^", "7": "&", "8": "*", "9": "(", "0": ")", "-": "_", "=": "+",
                                                "[": "{", "]": "}", "\\": "|", ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?" }
                                const a = tt.keyStats[modelData] || [0, 0], b = tt.keyStats[shift[modelData]] || [0, 0]
                                return [a[0] + b[0], a[1] + b[1]]
                            }
                            readonly property real rate: s[0] + s[1] > 0 ? s[1] / (s[0] + s[1]) : 0
                            z: keyMouse.containsMouse ? 1 : 0
                            width: 28
                            height: 26
                            radius: Theme.radius
                            color: rate > 0 ? Theme.alpha(Theme.danger, Math.min(0.85, 0.08 + rate * 6)) : Theme.alpha(Theme.text, 0.04)
                            border.color: keyMouse.containsMouse ? Theme.accent : Theme.border
                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData
                                color: parent.rate > 0.06 ? Theme.text : Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                            MouseArea { id: keyMouse; anchors.fill: parent; hoverEnabled: true }
                            Rectangle {
                                visible: keyMouse.containsMouse
                                z: 5
                                anchors.bottom: parent.top
                                anchors.bottomMargin: 4
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: tip.implicitWidth + 12
                                height: 20
                                radius: Theme.radius
                                color: Theme.bgCard
                                border.color: Theme.border
                                Text {
                                    id: tip
                                    anchors.centerIn: parent
                                    text: (parent.parent.rate * 100).toFixed(1) + "% missed  ·  " + (parent.parent.s[0] + parent.parent.s[1]) + " typed"
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                }
                            }
                        }
                    }
                }
            }
            Row {
                leftPadding: 70
                Rectangle {
                    readonly property var s: tt.keyStats[" "] || [0, 0]
                    readonly property real rate: s[0] + s[1] > 0 ? s[1] / (s[0] + s[1]) : 0
                    width: 220
                    height: 22
                    radius: Theme.radius
                    color: rate > 0 ? Theme.alpha(Theme.danger, Math.min(0.85, 0.08 + rate * 6)) : Theme.alpha(Theme.text, 0.04)
                    border.color: Theme.border
                    Text {
                        anchors.centerIn: parent
                        text: "space  " + (parent.rate * 100).toFixed(1) + "%"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                    }
                }
            }
        }
    }
}
