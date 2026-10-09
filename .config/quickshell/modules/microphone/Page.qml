import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs
import qs.widgets
import "Presets.js" as Presets

// Settings > Audio FX: switches for the music EQ (AudioFx.qml) and the
// microphone chain (page.service.qml), each optional, and the chain's controls.
//
//   noise suppression   NoiseTorch's RNNoise filter: on/off, which microphone,
//                       voice threshold
//   mic effects         the mic-effects rack (port of its console panel):
//                       bypass, mute, monitor, level and meters; channel
//                       presets (save your own); the signal chain (click a
//                       stage to edit it, ◀ ▶ to move it); the stage's
//                       controls. Knobs: drag up/down, double-click resets.
//
// The music EQ itself is the bar's EQ chip (EqPanel.qml).
Item {
    id: page
    property var service

    property int rightMargin: 36
    readonly property var m: page.service.settings
    readonly property bool live: page.service.connected

    // the meters run (and the real mic opens) while this page is showing
    Component.onCompleted: page.service.holdMeter(true)
    Component.onDestruction: page.service.holdMeter(false)

    function num(key, fallback) { const v = m ? m[key] : undefined; return v === undefined ? fallback : v }
    function set(key, value) { page.service.setSetting(key, value) }
    function db(v) { return (v > 0 ? "+" : "") + v.toFixed(1) }
    function semis(v) { return (v > 0 ? "+" : "") + v.toFixed(1) + " st" }
    function hz(f) { return f >= 1000 ? (f / 1000).toFixed(f >= 10000 ? 0 : 1) + "k" : Math.round(f) + "" }
    function freqToPos(f) { return Math.log(Math.max(20, f) / 20) / Math.log(1000) }
    function posToFreq(p) { return 20 * Math.pow(1000, p) }
    // the daemon's own mappings, so readouts are what the DSP uses
    function gateThresholdDb(t) { return -60 + 45 * t }
    function compRatio(t) { return 2 + 4 * t }
    function compThresholdDb(t) { return -14 - 18 * t }
    function retuneMs(t) { return 200 * Math.pow(0.01, t) }
    function limiterBoostDb(t) { return 18 * t }
    function limiterCeilingDb(t) { return -12 + 12 * t }
    function limiterReleaseMs(t) { return 20 + 280 * t }
    function levelDb(v) { const g = v * 2; return g > 0.0001 ? 20 * Math.log10(g) : -96 }

    // ---------------------------------------------------------------- the chain
    property string stage: "comp"
    readonly property var stageLabels: ({ hpf: "HPF", hum: "HUM", nr: "NR", gate: "GATE", comp: "COMP",
        deess: "DE-S", eq: "EQ", pitch: "PITCH", fx: "FX", verb: "VERB", limit: "LIMIT" })
    readonly property var stageTitles: ({ hpf: "HIGH-PASS FILTER", hum: "HUM NOTCH", nr: "NOISE REDUCTION", gate: "GATE",
        comp: "COMPRESSOR", deess: "DE-ESSER", eq: "EQ", pitch: "PITCH & AUTO-TUNE",
        fx: "VOICE FX", verb: "REVERB & DELAY", limit: "LIMITER / LEVEL" })
    function stageOn(id) {
        const s = m
        if (!s) return false
        if (id === "hpf") return !!s.highPass
        if (id === "hum") return !!s.humFilter
        if (id === "nr") return !!s.voiceIsolation
        if (id === "gate") return !!s.noiseGate
        if (id === "comp") return !!(s.autoLevel || s.glueComp)
        if (id === "deess") return !!s.deEsser
        if (id === "eq") return !!(s.eq && s.eq.length)
        if (id === "pitch") return !!(s.autoTune || s.pitch || s.formant || s.doubler)
        if (id === "fx") return !!(s.tape || s.ringMod || s.megaphone)
        if (id === "verb") return !!((s.space && s.space !== "none") || s.slapDelay || s.longDelay)
        if (id === "limit") return !!s.limiter
        return false
    }

    // ---------------------------------------------------------------- channel presets
    readonly property var micPresets: Presets.mic
    readonly property var eqPresets: Presets.eq
    property string selectedPreset: ""
    readonly property string userKey: JSON.stringify(page.service.userPresets)
    readonly property var channelPresets: {
        const user = JSON.parse(userKey), out = [], used = {}
        for (const f of micPresets) {
            const o = user.find(u => u.key === f.key)
            out.push({ key: f.key, label: o ? o.name : f.label, user: !!o, builtin: true, settings: o ? o.settings : null, factory: f })
            used[f.key] = true
        }
        for (const u of user) if (!used[u.key]) out.push({ key: u.key, label: u.name, user: true, builtin: false, settings: u.settings, factory: null })
        return out
    }
    function presetBase() {
        return {
            voiceIsolation: false, voiceIsolationIntensity: 0.6, noiseGate: false, noiseGateIntensity: 0.55,
            autoLevel: false, autoLevelIntensity: 0.6, autoLevelRatio: 0.6, autoLevelThreshold: 0.6,
            glueComp: false, glueCompIntensity: 0.4,
            limiter: false, limiterBoost: 1 / 3, limiterCeiling: 11 / 12, limiterRelease: 3 / 14,
            deEsser: false, deEsserIntensity: 0.5, highPass: true, humFilter: false,
            chain: [], voice: "none", tape: false, tapeMix: 0.45, ringMod: false, ringModMix: 1.0, megaphone: false, megaphoneMix: 1.0,
            autoTune: false, autoTuneSpeed: 0.5, autoTuneAmount: 1.0,
            pitch: 0, formant: 0, doubler: false, doublerMix: 0.35, compMix: 1.0, pitchMix: 1.0,
            space: "none", spaceSize: 0.5, spaceDecay: 0.5, spaceTone: 0.5, spacePreDelay: 0, spaceDiffusion: 0.5, spaceLowCut: 0,
            spaceModRate: 0.5, spaceModDepth: 0, spaceMix: 1.0,
            slapDelay: false, slapDelayMix: 0.18, slapDelayTime: 0.4,
            longDelay: false, longDelayMix: 0.28, longDelayTime: 0.4, longDelayFeedback: 0.32, longDelayTone: 0.45
        }
    }
    function eqBandsOf(key) { const p = eqPresets.find(x => x.key === key); return p ? p.bands : null }
    function applyChannelPreset(p) {
        selectedPreset = p.key
        if (p.user) { page.service.setSettings(p.settings); return }
        const patch = presetBase()
        for (const k in p.factory.set) if (k !== "eqPreset") patch[k] = p.factory.set[k]
        patch.eq = (eqBandsOf(p.factory.set.eqPreset) || []).map(b => ({ on: true, type: b.type, freq: b.freq, gain: b.gain, q: b.q }))
        patch.enabled = true
        page.service.setSettings(patch)
    }
    function saveNewPreset(name) {
        name = name.trim() || "My preset"
        const key = "user-" + Date.now()
        selectedPreset = key
        page.service.saveUserPreset(key, name)
    }

    // ---------------------------------------------------------------- reverb spaces
    readonly property var spacePresets: ({
        room:       { spaceSize: 0.30, spaceDecay: 0.30, spaceTone: 0.58, spacePreDelay: 0.02, spaceDiffusion: 0.52, spaceLowCut: 0.08, spaceModRate: 0.30, spaceModDepth: 0.03, spaceMix: 1.0 },
        hall:       { spaceSize: 0.58, spaceDecay: 0.58, spaceTone: 0.50, spacePreDelay: 0.10, spaceDiffusion: 0.65, spaceLowCut: 0.12, spaceModRate: 0.40, spaceModDepth: 0.08, spaceMix: 1.0 },
        cathedral:  { spaceSize: 0.82, spaceDecay: 0.82, spaceTone: 0.40, spacePreDelay: 0.22, spaceDiffusion: 0.78, spaceLowCut: 0.18, spaceModRate: 0.32, spaceModDepth: 0.12, spaceMix: 1.0 },
        echo:       { spaceSize: 0.55, spaceDecay: 0.42, spaceTone: 0.65, spacePreDelay: 0.28, spaceDiffusion: 0.50, spaceLowCut: 0.06, spaceModRate: 0.50, spaceModDepth: 0.00, spaceMix: 1.0 },
        underwater: { spaceSize: 0.45, spaceDecay: 0.60, spaceTone: 0.15, spacePreDelay: 0.06, spaceDiffusion: 0.60, spaceLowCut: 0.20, spaceModRate: 0.35, spaceModDepth: 0.45, spaceMix: 1.0 }
    })
    function applySpace(kind) {
        const patch = { space: kind }
        const p = spacePresets[kind]
        if (p) for (const k in p) patch[k] = p[k]
        page.service.setSettings(patch)
    }
    function setFx(key, on) { const p = { voice: "none" }; p[key] = on; page.service.setSettings(p) }

    // ---------------------------------------------------------------- auto-tune notes
    function scaleNotes() {
        const notes = page.service.tuneKeyOptions.length ? page.service.tuneKeyOptions : ["c", "c#", "d", "d#", "e", "f", "f#", "g", "g#", "a", "a#", "b"]
        const sc = m.autoTuneScale || "chromatic"
        const steps = sc === "major" ? [0, 2, 4, 5, 7, 9, 11] : sc === "minor" ? [0, 2, 3, 5, 7, 8, 10]
            : sc === "pentatonic" ? [0, 2, 4, 7, 9] : sc === "blues" ? [0, 3, 5, 6, 7, 10] : [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
        const r = Math.max(0, notes.indexOf(m.autoTuneKey || "c"))
        return steps.map(s => notes[(r + s) % 12])
    }
    function latched() { return m.autoTuneNotes && m.autoTuneNotes.length ? m.autoTuneNotes : null }
    function noteAllowed(n) { return (latched() || scaleNotes()).indexOf(n) >= 0 }
    function toggleNote(n) {
        const notes = (latched() || scaleNotes()).slice()
        const i = notes.indexOf(n)
        if (i < 0) notes.push(n); else notes.splice(i, 1)
        set("autoTuneNotes", notes)
    }

    // ---------------------------------------------------------------- mic EQ
    readonly property var eqBands: m.eq || []
    property int eqSel: 0
    readonly property var eqTypeLabels: ({ bell: "BELL", lowshelf: "LO SHELF", highshelf: "HI SHELF", highpass: "HI-PASS", lowpass: "LO-PASS", notch: "NOTCH" })
    readonly property var eqGainless: ({ highpass: true, lowpass: true, notch: true })
    readonly property var eqQless: ({ lowshelf: true, highshelf: true })
    function eqSet(i, key, value) {
        if (i < 0 || i >= eqBands.length) return
        const out = JSON.parse(JSON.stringify(eqBands))
        out[i][key] = value
        set("eq", out)
    }
    function eqAdd() {
        if (eqBands.length >= 8) return
        const out = JSON.parse(JSON.stringify(eqBands))
        out.push({ on: true, type: "bell", freq: 1000, gain: 0, q: 0.707 })
        eqSel = out.length - 1
        set("eq", out)
    }
    function eqRemove(i) {
        if (i < 0 || i >= eqBands.length) return
        const out = JSON.parse(JSON.stringify(eqBands))
        out.splice(i, 1)
        if (eqSel >= out.length) eqSel = Math.max(0, out.length - 1)
        set("eq", out)
    }
    // RBJ cookbook as in the daemon's Biquad (fixed 0.9 shelf slope), so the
    // curve is the filter that's running
    function eqCoeffs(type, rate, f, q, gainDb) {
        const w = 2 * Math.PI * Math.min(f, rate * 0.45) / rate
        const c = Math.cos(w), sn = Math.sin(w), al = sn / (2 * q)
        let a0
        if (type === "highpass") { a0 = 1 + al; return { b0: (1 + c) / 2 / a0, b1: -(1 + c) / a0, b2: (1 + c) / 2 / a0, a1: -2 * c / a0, a2: (1 - al) / a0 } }
        if (type === "lowpass") { a0 = 1 + al; return { b0: (1 - c) / 2 / a0, b1: (1 - c) / a0, b2: (1 - c) / 2 / a0, a1: -2 * c / a0, a2: (1 - al) / a0 } }
        if (type === "notch") { a0 = 1 + al; return { b0: 1 / a0, b1: -2 * c / a0, b2: 1 / a0, a1: -2 * c / a0, a2: (1 - al) / a0 } }
        const A = Math.pow(10, gainDb / 40)
        if (type === "lowshelf" || type === "highshelf") {
            const sa = sn / 2 * Math.sqrt((A + 1 / A) * (1 / 0.9 - 1) + 2), sq = 2 * Math.sqrt(A) * sa
            if (type === "lowshelf") {
                a0 = (A + 1) + (A - 1) * c + sq
                return { b0: A * ((A + 1) - (A - 1) * c + sq) / a0, b1: 2 * A * ((A - 1) - (A + 1) * c) / a0, b2: A * ((A + 1) - (A - 1) * c - sq) / a0,
                         a1: -2 * ((A - 1) + (A + 1) * c) / a0, a2: ((A + 1) + (A - 1) * c - sq) / a0 }
            }
            a0 = (A + 1) - (A - 1) * c + sq
            return { b0: A * ((A + 1) + (A - 1) * c + sq) / a0, b1: -2 * A * ((A - 1) + (A + 1) * c) / a0, b2: A * ((A + 1) + (A - 1) * c - sq) / a0,
                     a1: 2 * ((A - 1) - (A + 1) * c) / a0, a2: ((A + 1) - (A - 1) * c - sq) / a0 }
        }
        a0 = 1 + al / A
        return { b0: (1 + al * A) / a0, b1: -2 * c / a0, b2: (1 - al * A) / a0, a1: -2 * c / a0, a2: (1 - al / A) / a0 }
    }
    function bandDb(co, w) {
        const c1 = Math.cos(w), s1 = Math.sin(w), c2 = Math.cos(2 * w), s2 = Math.sin(2 * w)
        const nr = co.b0 + co.b1 * c1 + co.b2 * c2, ni = -(co.b1 * s1 + co.b2 * s2)
        const dr = 1 + co.a1 * c1 + co.a2 * c2, di = -(co.a1 * s1 + co.a2 * s2)
        const den = dr * dr + di * di
        return 10 * Math.log10((nr * nr + ni * ni) / (den > 1e-20 ? den : 1e-20))
    }
    function eqCurveDb(f) {
        let total = 0
        for (const b of eqBands) {
            if (!b || b.on === false) continue
            total += bandDb(eqCoeffs(b.type, 48000, b.freq, b.q, b.gain), 2 * Math.PI * Math.min(f, 48000 * 0.49) / 48000)
        }
        return total
    }

    // ================================================================ pieces
    component Section: Text {
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.bold: true
        font.letterSpacing: 2
        topPadding: 6
    }
    component Hint: Text {
        width: parent ? parent.width : 0
        wrapMode: Text.Wrap
        color: Theme.textFaint
        font.family: Theme.fontFamily
        font.pixelSize: 10
    }
    component Switch: Item {
        id: sw
        property string label
        property string hint
        property bool on: false
        signal toggled()
        width: parent ? parent.width : 0
        height: hint ? 40 : 28
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 60
            spacing: 3
            Text { text: sw.label; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 12 }
            Text {
                visible: sw.hint !== ""
                width: parent.width
                elide: Text.ElideRight
                text: sw.hint
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }
        }
        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 44; height: 22; radius: 11
            color: sw.on ? Theme.accent : Theme.trackBg
            border.color: Theme.border
            Rectangle {
                width: 16; height: 16; radius: 8
                anchors.verticalCenter: parent.verticalCenter
                x: sw.on ? parent.width - width - 3 : 3
                color: Theme.text
                Behavior on x { NumberAnimation { duration: Theme.animFast } }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sw.toggled() }
        }
    }
    // a knob: drag up/down (shift = fine), double-click = default; commits on release
    component Knob: Item {
        id: kb
        property string label
        property real value: 0
        property real defaultValue: 0
        property string readout: ""
        property real live: value
        property bool dragging: false
        signal released(real v)
        signal moved(real v)
        onValueChanged: if (!dragging) live = value
        width: 70
        height: 84
        Canvas {
            id: dial
            width: 46; height: 46
            anchors.horizontalCenter: parent.horizontalCenter
            property real v: kb.live
            onVChanged: requestPaint()
            Component.onCompleted: requestPaint()
            onPaint: {
                const c = getContext("2d")
                c.reset()
                const cx = width / 2, cy = height / 2, r = width / 2 - 4
                const a0 = Math.PI * 0.75, a1 = Math.PI * 2.25, av = a0 + (a1 - a0) * Math.max(0, Math.min(1, v))
                c.lineWidth = 4
                c.lineCap = "round"
                c.strokeStyle = Theme.css(Theme.text, 0.10)
                c.beginPath(); c.arc(cx, cy, r, a0, a1); c.stroke()
                c.strokeStyle = Theme.css(Theme.accent, 0.95)
                c.beginPath(); c.arc(cx, cy, r, a0, av); c.stroke()
                c.fillStyle = Theme.css(Theme.text, 0.9)
                c.beginPath(); c.arc(cx + Math.cos(av) * (r - 8), cy + Math.sin(av) * (r - 8), 2.5, 0, Math.PI * 2); c.fill()
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.SizeVerCursor
                property real startY
                property real startV
                onPressed: mouse => { startY = mouse.y; startV = kb.live; kb.dragging = true }
                onPositionChanged: mouse => {
                    const span = (mouse.modifiers & Qt.ShiftModifier) ? 600 : 160
                    kb.live = Math.max(0, Math.min(1, startV + (startY - mouse.y) / span))
                    kb.moved(kb.live)
                }
                onReleased: { kb.dragging = false; kb.released(kb.live) }
                onDoubleClicked: { kb.live = kb.defaultValue; kb.released(kb.defaultValue) }
                onWheel: wheel => { kb.live = Math.max(0, Math.min(1, kb.live + (wheel.angleDelta.y > 0 ? 0.02 : -0.02))); kb.released(kb.live) }
            }
        }
        Text {
            y: 48
            anchors.horizontalCenter: parent.horizontalCenter
            text: kb.readout
            color: kb.dragging ? Theme.accent : Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 10
        }
        Text {
            y: 64
            anchors.horizontalCenter: parent.horizontalCenter
            text: kb.label.toUpperCase()
            color: Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: 8
            font.letterSpacing: 1
        }
    }
    component Meter: Item {
        property real level: 0          // linear peak 0..1
        property string label
        width: parent ? parent.width : 0
        height: 14
        readonly property real dbv: level > 0.00001 ? Math.max(-60, 20 * Math.log10(level)) : -60
        Text {
            id: ml
            width: 30
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: 9
            font.letterSpacing: 1
        }
        Rectangle {
            x: 34
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 34 - 54
            height: 6
            radius: 3
            color: Theme.alpha(Theme.text, 0.07)
            Rectangle {
                width: parent.width * (parent.parent.dbv + 60) / 60
                height: parent.height
                radius: 3
                color: parent.parent.dbv > -3 ? Theme.danger : parent.parent.dbv > -12 ? Theme.accent2 : Theme.accent
                Behavior on width { NumberAnimation { duration: 60 } }
            }
        }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: parent.dbv <= -60 ? "−∞ dB" : Math.round(parent.dbv) + " dB"
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 9
        }
    }
    component Knobs: Flow {
        width: parent ? parent.width : 0
        spacing: 6
    }
    component Buttons: Flow {
        width: parent ? parent.width : 0
        spacing: 4
    }

    // ================================================================ layout
    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width - page.rightMargin
            spacing: 12

            Item {
                width: parent.width
                height: 28
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "MICROPHONE"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    font.bold: true
                    font.letterSpacing: 3
                }
            }
            Rectangle { width: parent.width; height: 1; color: Theme.border }
            Hint { text: "Each feature runs a background program only while it's switched on, so leave off what you don't use (on battery, especially). Settings are kept per machine." }

            // ------------------------------------------------ noise suppression
            Section { text: "NOISE SUPPRESSION" }
            Switch {
                label: "NoiseTorch"
                hint: !page.service.noiseAvailable ? "Not built: ~/.local/lib/noisetorch/rnnoise_ladspa.so is missing (see INSTALL.md)"
                    : "RNNoise removes fans, keyboards and room noise · about 10 ms"
                on: page.service.noiseOn
                onToggled: if (page.service.noiseAvailable || page.service.noiseOn) page.service.setNoise(!page.service.noiseOn)
            }
            Row {
                visible: page.service.noiseOn
                spacing: 8
                width: parent.width
                Text {
                    width: 110
                    anchors.verticalCenter: parent.verticalCenter
                    text: "MICROPHONE"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.letterSpacing: 2
                }
                Buttons {
                    width: parent.width - 118
                    Repeater {
                        model: page.service.micNodes
                        HudButton {
                            required property var modelData
                            label: page.service.micLabel(modelData.name).toUpperCase()
                            on: page.service.mic === modelData.name
                            onClicked: page.service.setMicSource(modelData.name)
                        }
                    }
                }
            }
            Item {
                visible: page.service.noiseOn
                width: parent.width
                height: 50
                Slider {
                    anchors.fill: parent
                    property real v: page.service.threshold
                    label: "VOICE THRESHOLD  ·  " + Math.round(v) + "%"
                    icon: "󰍬"
                    value: v / 95
                    onMoved: value => v = Math.round(value * 95)
                    onCommitted: value => page.service.setThreshold(value * 95)
                }
            }
            Hint { visible: page.service.noiseOn; text: "How sure RNNoise must be that you're talking before it lets sound through. Higher cuts more between words; too high clips quiet speech. NoiseTorch's default is 95." }

            // ------------------------------------------------ mic effects
            Item {
                width: parent.width
                height: 34
                Section { anchors.bottom: parent.bottom; text: "MIC EFFECTS" }
                Text {
                    visible: page.service.fxEnabled
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    text: !page.live ? "STARTING…" : page.service.active ? "● IN USE" : "IDLE"
                    color: !page.live ? Theme.danger : page.service.active ? Theme.accent : Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.letterSpacing: 2
                }
            }
            Switch {
                label: "Effects rack"
                hint: !page.service.fxAvailable ? "Not built: ~/.local/lib/mic-effects/mic-effects-server is missing (see INSTALL.md)"
                    : "Compressor, EQ, de-esser, reverb, auto-tune… as a “Microphone Effects” mic"
                on: page.service.fxEnabled
                onToggled: if (page.service.fxAvailable || page.service.fxEnabled) page.service.setFx(!page.service.fxEnabled)
            }
            Hint {
                visible: page.service.fxEnabled
                text: "Apps use “Microphone Effects” as the mic (it's the system default). Signal: "
                    + page.service.micLabel(page.service.mic) + (page.service.noiseOn ? "  →  NoiseTorch" : "") + "  →  rack  →  apps."
                    + (page.service.commandError ? "   ⚠ " + page.service.commandError : "")
            }

            Column {
                visible: page.service.fxEnabled
                width: parent.width
                spacing: 12
                enabled: page.live
                opacity: page.live ? 1 : 0.5

                Switch {
                    label: "Effects"
                    hint: "Off passes the microphone through untouched (apps keep the same mic)"
                    on: page.service.enabled
                    onToggled: page.set("enabled", !page.service.enabled)
                }
                Row {
                    spacing: 6
                    HudButton {
                        label: page.service.muted ? "MUTED" : "MUTE"
                        danger: true
                        on: page.service.muted
                        onClicked: page.service.setMuted(!page.service.muted)
                    }
                    HudButton {
                        label: "MONITOR"
                        on: page.service.listen
                        onClicked: page.service.setListen(!page.service.listen)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: page.service.listen
                        text: "  hear yourself · use headphones (speakers will feed back)"
                        color: Theme.danger
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                }
                Meter { label: "IN"; level: page.service.inLevel }
                Meter { label: "OUT"; level: page.service.outLevel }
                Item {
                    width: parent.width
                    height: 50
                    Slider {
                        anchors.fill: parent
                        property real v: page.num("volume", 0.5)
                        label: "OUTPUT LEVEL  ·  " + page.db(page.levelDb(v)) + " dB"
                        icon: "󰕾"
                        value: v
                        onMoved: value => v = value
                        onCommitted: value => page.set("volume", value)
                    }
                }

                // ---------------- channel presets
                Text {
                    text: "PRESETS"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.letterSpacing: 2
                }
                Buttons {
                    Repeater {
                        model: page.channelPresets
                        HudButton {
                            required property var modelData
                            label: modelData.label.toUpperCase() + (modelData.user && modelData.builtin ? " *" : "")
                            on: page.selectedPreset === modelData.key
                            onClicked: page.applyChannelPreset(modelData)
                        }
                    }
                }
                Row {
                    spacing: 6
                    HudField {
                        id: presetName
                        width: 180
                        placeholder: "name this setup ↵"
                        onAccepted: { page.saveNewPreset(text); text = "" }
                    }
                    HudButton { label: "SAVE NEW"; onClicked: { page.saveNewPreset(presetName.text); presetName.text = "" } }
                    HudButton {
                        readonly property var sel: page.channelPresets.find(p => p.key === page.selectedPreset)
                        visible: !!sel
                        label: "UPDATE " + (sel ? sel.label.toUpperCase() : "")
                        onClicked: page.service.saveUserPreset(sel.key, sel.label)
                    }
                    HudButton {
                        readonly property var sel: page.channelPresets.find(p => p.key === page.selectedPreset)
                        visible: !!sel && sel.user
                        danger: true
                        label: sel && sel.builtin ? "RESTORE" : "DELETE"
                        onClicked: {
                            const s = sel
                            page.service.deleteUserPreset(s.key)
                            if (s.builtin) page.applyChannelPreset({ key: s.key, user: false, factory: s.factory })
                            else page.selectedPreset = ""
                        }
                    }
                }
                Hint { text: "* your saved version of a built-in preset (RESTORE puts the original back)." }

                // ---------------- signal chain
                Text {
                    text: "SIGNAL CHAIN  ·  " + page.service.chain.filter(id => page.stageOn(id)).length + " ENGAGED"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.letterSpacing: 2
                }
                Row {
                    id: rail
                    width: parent.width
                    spacing: 3
                    Repeater {
                        model: page.service.chain
                        Rectangle {
                            id: mod
                            required property string modelData
                            required property int index
                            readonly property bool sel: page.stage === modelData
                            readonly property bool engaged: page.stageOn(modelData)
                            width: (rail.width - rail.spacing * (page.service.chain.length - 1)) / page.service.chain.length
                            height: 46
                            radius: Theme.radius
                            color: sel ? Theme.alpha(Theme.accent, 0.15) : modMouse.containsMouse ? Theme.bgCard : Theme.alpha(Theme.text, 0.03)
                            border.color: sel ? Theme.accent : Theme.border
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 8
                                width: 6; height: 6; radius: 3
                                color: mod.engaged ? Theme.accent : Theme.alpha(Theme.text, 0.15)
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 20
                                text: page.stageLabels[mod.modelData] || mod.modelData
                                color: mod.sel ? Theme.accent : mod.engaged ? Theme.text : Theme.textFaint
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.bold: mod.sel
                            }
                            MouseArea {
                                id: modMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.stage = mod.modelData
                            }
                        }
                    }
                }

                // ---------------- the selected stage
                Rectangle {
                    width: parent.width
                    height: stageCol.implicitHeight + 28
                    radius: Theme.radius
                    color: "transparent"
                    border.color: Theme.border

                    Column {
                        id: stageCol
                        x: 14
                        y: 14
                        width: parent.width - 28
                        spacing: 10

                        Item {
                            width: parent.width
                            height: 24
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: page.stageTitles[page.stage] || page.stage
                                color: page.stageOn(page.stage) ? Theme.accent : Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                                font.letterSpacing: 2
                            }
                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                HudButton { label: "◀ EARLIER"; onClicked: page.service.moveStage(page.stage, -1) }
                                HudButton { label: "LATER ▶"; onClicked: page.service.moveStage(page.stage, 1) }
                            }
                        }

                        Loader {
                            width: parent.width
                            sourceComponent: page.stage === "hpf" || page.stage === "hum" ? switchUnit
                                : page.stage === "nr" ? nrUnit : page.stage === "gate" ? gateUnit
                                : page.stage === "comp" ? compUnit : page.stage === "deess" ? deessUnit
                                : page.stage === "eq" ? eqUnit : page.stage === "pitch" ? pitchUnit
                                : page.stage === "fx" ? fxUnit : page.stage === "verb" ? verbUnit
                                : page.stage === "limit" ? limitUnit : null
                        }
                    }
                }
            }
        }
    }

    // ================================================================ stage editors
    Component {
        id: switchUnit
        Column {
            spacing: 6
            readonly property string key: page.stage === "hpf" ? "highPass" : "humFilter"
            Switch {
                width: parent.width
                label: "Engage"
                hint: page.stage === "hpf" ? "80 Hz · rumble and handling noise" : "50/60 Hz and first harmonic · mains buzz"
                on: !!page.m[parent.key]
                onToggled: page.set(parent.key, !page.m[parent.key])
            }
        }
    }
    Component {
        id: nrUnit
        Column {
            spacing: 6
            Switch {
                width: parent.width
                label: "Engage"
                hint: "The rack's own spectral denoiser · adds about 40 ms · usually off when NoiseTorch is on"
                on: !!page.m.voiceIsolation
                onToggled: page.set("voiceIsolation", !page.m.voiceIsolation)
            }
            Knobs {
                Knob { label: "Amount"; defaultValue: 0.6; value: page.num("voiceIsolationIntensity", 0.6)
                       readout: Math.round(live * 100) + "%"; onReleased: v => page.set("voiceIsolationIntensity", v) }
            }
        }
    }
    Component {
        id: gateUnit
        Column {
            spacing: 6
            Switch { width: parent.width; label: "Engage"; hint: "Closes the mic below the threshold"
                     on: !!page.m.noiseGate; onToggled: page.set("noiseGate", !page.m.noiseGate) }
            Knobs {
                Knob { label: "Thresh"; defaultValue: 0.55; value: page.num("noiseGateIntensity", 0.55)
                       readout: Math.round(page.gateThresholdDb(live)) + " dB"; onReleased: v => page.set("noiseGateIntensity", v) }
            }
        }
    }
    Component {
        id: compUnit
        Column {
            spacing: 6
            Buttons {
                HudButton { label: "MAIN"; on: !!page.m.autoLevel; onClicked: page.set("autoLevel", !page.m.autoLevel) }
                HudButton { label: "GLUE"; on: !!page.m.glueComp; onClicked: page.set("glueComp", !page.m.glueComp) }
            }
            Knobs {
                Knob { label: "Ratio"; defaultValue: 0.6; value: page.num("autoLevelRatio", page.num("autoLevelIntensity", 0.6))
                       readout: page.compRatio(live).toFixed(1) + ":1"; onReleased: v => page.set("autoLevelRatio", v) }
                Knob { label: "Thresh"; defaultValue: 0.6; value: page.num("autoLevelThreshold", page.num("autoLevelIntensity", 0.6))
                       readout: Math.round(page.compThresholdDb(live)) + " dB"; onReleased: v => page.set("autoLevelThreshold", v) }
                Knob { label: "Mix"; defaultValue: 1.0; value: page.num("compMix", 1.0)
                       readout: Math.round(live * 100) + "%"; onReleased: v => page.set("compMix", v) }
                Knob { visible: !!page.m.glueComp; label: "Glue"; defaultValue: 0.4; value: page.num("glueCompIntensity", 0.4)
                       readout: Math.round(live * 100) + "%"; onReleased: v => page.set("glueCompIntensity", v) }
            }
            Hint { text: "Main catches peaks; Glue holds the voice steady in the mix." }
        }
    }
    Component {
        id: deessUnit
        Column {
            spacing: 6
            Switch { width: parent.width; label: "Engage"; hint: "Softens harsh S and T sounds"
                     on: !!page.m.deEsser; onToggled: page.set("deEsser", !page.m.deEsser) }
            Knobs {
                Knob { label: "Amount"; defaultValue: 0.5; value: page.num("deEsserIntensity", 0.5)
                       readout: Math.round(live * 100) + "%"; onReleased: v => page.set("deEsserIntensity", v) }
            }
        }
    }
    Component {
        id: limitUnit
        Column {
            spacing: 6
            Switch { width: parent.width; label: "Engage"; hint: "At the end of the chain: Ceiling caps the final level"
                     on: !!page.m.limiter; onToggled: page.set("limiter", !page.m.limiter) }
            Knobs {
                Knob { label: "Boost"; defaultValue: 1 / 3; value: page.num("limiterBoost", 1 / 3)
                       readout: page.db(page.limiterBoostDb(live)) + " dB"; onReleased: v => page.set("limiterBoost", v) }
                Knob { label: "Ceiling"; defaultValue: 11 / 12; value: page.num("limiterCeiling", 11 / 12)
                       readout: page.db(page.limiterCeilingDb(live)) + " dB"; onReleased: v => page.set("limiterCeiling", v) }
                Knob { label: "Release"; defaultValue: 3 / 14; value: page.num("limiterRelease", 3 / 14)
                       readout: Math.round(page.limiterReleaseMs(live)) + " ms"; onReleased: v => page.set("limiterRelease", v) }
            }
        }
    }
    Component {
        id: fxUnit
        Column {
            spacing: 6
            Buttons {
                HudButton { label: "TAPE"; on: !!page.m.tape; onClicked: page.setFx("tape", !page.m.tape) }
                HudButton { label: "RING MOD"; on: !!page.m.ringMod; onClicked: page.setFx("ringMod", !page.m.ringMod) }
                HudButton { label: "MEGAPHONE"; on: !!page.m.megaphone; onClicked: page.setFx("megaphone", !page.m.megaphone) }
            }
            Knobs {
                Knob { visible: !!page.m.tape; label: "Tape"; defaultValue: 0.45; value: page.num("tapeMix", 0.45)
                       readout: Math.round(live * 100) + "%"; onReleased: v => page.set("tapeMix", v) }
                Knob { visible: !!page.m.ringMod; label: "Ring"; defaultValue: 1.0; value: page.num("ringModMix", 1.0)
                       readout: Math.round(live * 100) + "%"; onReleased: v => page.set("ringModMix", v) }
                Knob { visible: !!page.m.megaphone; label: "Mega"; defaultValue: 1.0; value: page.num("megaphoneMix", 1.0)
                       readout: Math.round(live * 100) + "%"; onReleased: v => page.set("megaphoneMix", v) }
            }
            Hint { text: "Independent parallel effects · stack any combination." }
        }
    }
    Component {
        id: verbUnit
        Column {
            spacing: 8
            Buttons {
                Repeater {
                    model: page.service.spaceOptions.filter(s => s !== "trap")
                    HudButton {
                        required property string modelData
                        label: modelData === "none" ? "OFF" : modelData.toUpperCase()
                        on: (page.m.space || "none") === modelData
                        onClicked: page.applySpace(modelData)
                    }
                }
            }
            Knobs {
                Knob { label: "Size"; defaultValue: 0.5; value: page.num("spaceSize", 0.5); readout: Math.round(live * 100) + "%"; onReleased: v => page.set("spaceSize", v) }
                Knob { label: "Decay"; defaultValue: 0.5; value: page.num("spaceDecay", 0.5); readout: Math.round(live * 100) + "%"; onReleased: v => page.set("spaceDecay", v) }
                Knob { label: "Tone"; defaultValue: 0.5; value: page.num("spaceTone", 0.5)
                       readout: live < 0.34 ? "Dark" : live > 0.66 ? "Bright" : "Warm"; onReleased: v => page.set("spaceTone", v) }
                Knob { label: "Pre"; defaultValue: 0; value: page.num("spacePreDelay", 0); readout: Math.round(live * 120) + " ms"; onReleased: v => page.set("spacePreDelay", v) }
                Knob { label: "Diffuse"; defaultValue: 0.5; value: page.num("spaceDiffusion", 0.5); readout: Math.round(live * 100) + "%"; onReleased: v => page.set("spaceDiffusion", v) }
                Knob { label: "Lo Cut"; defaultValue: 0; value: page.num("spaceLowCut", 0)
                       readout: live < 0.02 ? "Off" : Math.round(35 + live * 465) + " Hz"; onReleased: v => page.set("spaceLowCut", v) }
                Knob { label: "Mod Rate"; defaultValue: 0.5; value: page.num("spaceModRate", 0.5)
                       readout: (0.08 + live * 0.92).toFixed(2) + " Hz"; onReleased: v => page.set("spaceModRate", v) }
                Knob { label: "Mod Depth"; defaultValue: 0; value: page.num("spaceModDepth", page.num("spaceMod", 0))
                       readout: Math.round(live * 100) + "%"; onReleased: v => page.set("spaceModDepth", v) }
                Knob { label: "Room Mix"; defaultValue: 1.0; value: page.num("spaceMix", 1.0); readout: Math.round(live * 100) + "%"; onReleased: v => page.set("spaceMix", v) }
            }
            Rectangle { width: parent.width; height: 1; color: Theme.border }
            Text { text: "PARALLEL DELAY SENDS"; color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 10; font.letterSpacing: 2 }
            Buttons {
                HudButton { label: "SLAP"; on: !!page.m.slapDelay; onClicked: page.set("slapDelay", !page.m.slapDelay) }
                HudButton { label: "LONG"; on: !!page.m.longDelay; onClicked: page.set("longDelay", !page.m.longDelay) }
            }
            Knobs {
                Knob { label: "Slap"; defaultValue: 0.18; value: page.num("slapDelayMix", 0.18); readout: Math.round(live * 100) + "%"; onReleased: v => page.set("slapDelayMix", v) }
                Knob { label: "Slap Time"; defaultValue: 0.4; value: page.num("slapDelayTime", 0.4); readout: Math.round(70 + live * 90) + " ms"; onReleased: v => page.set("slapDelayTime", v) }
                Knob { label: "Long"; defaultValue: 0.28; value: page.num("longDelayMix", 0.28); readout: Math.round(live * 100) + "%"; onReleased: v => page.set("longDelayMix", v) }
                Knob { label: "Time"; defaultValue: 0.4; value: page.num("longDelayTime", 0.4); readout: Math.round(220 + live * 780) + " ms"; onReleased: v => page.set("longDelayTime", v) }
                Knob { label: "Feedback"; defaultValue: 0.32; value: page.num("longDelayFeedback", 0.32); readout: Math.round(8 + live * 72) + "%"; onReleased: v => page.set("longDelayFeedback", v) }
                Knob { label: "Tail Tone"; defaultValue: 0.45; value: page.num("longDelayTone", 0.45)
                       readout: live < 0.34 ? "Dark" : live > 0.66 ? "Bright" : "Warm"; onReleased: v => page.set("longDelayTone", v) }
            }
        }
    }
    Component {
        id: pitchUnit
        Column {
            spacing: 8
            Knobs {
                Knob { label: "Pitch"; defaultValue: 0.5; value: (page.num("pitch", 0) + 12) / 24; readout: page.semis(live * 24 - 12)
                       onReleased: v => page.set("pitch", Math.round((v * 24 - 12) * 2) / 2) }
                Knob { label: "Formant"; defaultValue: 0.5; value: (page.num("formant", 0) + 12) / 24; readout: page.semis(live * 24 - 12)
                       onReleased: v => page.set("formant", Math.round((v * 24 - 12) * 2) / 2) }
                Knob { label: "Doubler"; defaultValue: 0.35; value: page.num("doublerMix", 0.35); readout: Math.round(live * 100) + "%"
                       onReleased: v => page.set("doublerMix", v) }
            }
            Buttons {
                HudButton { label: "DOUBLER"; on: !!page.m.doubler; onClicked: page.set("doubler", !page.m.doubler) }
                HudButton { label: "AUTO-TUNE"; on: !!page.m.autoTune; onClicked: page.set("autoTune", !page.m.autoTune) }
            }
            Column {
                width: parent.width
                spacing: 8
                visible: !!page.m.autoTune
                Knobs {
                    Knob { label: "Retune"; defaultValue: 0.5; value: page.num("autoTuneSpeed", 0.5)
                           readout: (page.retuneMs(live) >= 10 ? Math.round(page.retuneMs(live)) : page.retuneMs(live).toFixed(1)) + " ms"
                           onReleased: v => page.set("autoTuneSpeed", v) }
                    Knob { label: "Amount"; defaultValue: 1.0; value: page.num("autoTuneAmount", 1.0); readout: Math.round(live * 100) + "%"
                           onReleased: v => page.set("autoTuneAmount", v) }
                }
                Buttons {
                    Repeater {
                        model: page.service.tuneScaleOptions
                        HudButton {
                            required property string modelData
                            label: modelData.toUpperCase()
                            on: (page.m.autoTuneScale || "chromatic") === modelData
                            onClicked: page.service.setSettings({ autoTuneScale: modelData, autoTuneNotes: [] })
                        }
                    }
                }
                Buttons {
                    Repeater {
                        model: page.service.tuneKeyOptions
                        HudButton {
                            required property string modelData
                            label: modelData.toUpperCase()
                            on: (page.m.autoTuneKey || "c") === modelData
                            onClicked: page.service.setSettings({ autoTuneKey: modelData, autoTuneNotes: [] })
                        }
                    }
                }
                // piano: outlined = in the key and scale, lit = allowed; click to latch notes
                Item {
                    id: piano
                    width: Math.min(parent.width, 420)
                    height: 90
                    readonly property real ww: width / 7
                    Repeater {
                        model: ["c", "d", "e", "f", "g", "a", "b"]
                        Rectangle {
                            required property string modelData
                            required property int index
                            readonly property bool allowed: page.noteAllowed(modelData)
                            x: index * piano.ww
                            width: piano.ww - 2
                            height: piano.height
                            radius: 3
                            color: allowed ? Theme.alpha(Theme.text, 0.92) : Theme.alpha(Theme.text, 0.22)
                            border.color: page.scaleNotes().indexOf(modelData) >= 0 ? Theme.accent : Theme.border
                            border.width: page.scaleNotes().indexOf(modelData) >= 0 ? 2 : 1
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 5
                                text: parent.modelData.toUpperCase()
                                color: Theme.bgPanel
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.bold: true
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.toggleNote(parent.modelData) }
                        }
                    }
                    Repeater {
                        model: [{ n: "c#", at: 1 }, { n: "d#", at: 2 }, { n: "f#", at: 4 }, { n: "g#", at: 5 }, { n: "a#", at: 6 }]
                        Rectangle {
                            required property var modelData
                            readonly property bool allowed: page.noteAllowed(modelData.n)
                            z: 2
                            x: modelData.at * piano.ww - width / 2 - 1
                            width: piano.ww * 0.58
                            height: piano.height * 0.6
                            radius: 2
                            color: allowed ? Theme.accent : Qt.darker(Theme.bgPanel, 1.4)
                            border.color: page.scaleNotes().indexOf(modelData.n) >= 0 ? Theme.accent : Theme.border
                            border.width: page.scaleNotes().indexOf(modelData.n) >= 0 ? 2 : 1
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.toggleNote(parent.modelData.n) }
                        }
                    }
                }
                Row {
                    spacing: 8
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.latched() ? "Custom latch · " + page.latched().length + " notes" : "Following " + (page.m.autoTuneKey || "c").toUpperCase() + " " + (page.m.autoTuneScale || "chromatic")
                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                    HudButton { visible: !!page.latched(); label: "USE KEY + SCALE"; onClicked: page.set("autoTuneNotes", []) }
                }
            }
        }
    }
    Component {
        id: eqUnit
        Column {
            spacing: 8
            Buttons {
                Repeater {
                    model: page.eqPresets
                    HudButton {
                        required property var modelData
                        label: modelData.label.toUpperCase()
                        onClicked: { page.eqSel = 0; page.set("eq", modelData.bands.map(b => ({ on: true, type: b.type, freq: b.freq, gain: b.gain, q: b.q }))) }
                    }
                }
            }
            // the response of the filters really running, a dot per band
            Canvas {
                id: curve
                width: parent.width
                height: 110
                property string key: JSON.stringify(page.eqBands) + "|" + page.eqSel
                onKeyChanged: requestPaint()
                onWidthChanged: requestPaint()
                onPaint: {
                    const c = getContext("2d")
                    c.reset()
                    const w = width, h = height, mid = h / 2, range = 18
                    const px = f => page.freqToPos(f) * w
                    const py = d => mid - Math.max(-range, Math.min(range, d)) / range * (h / 2 - 4)
                    c.strokeStyle = Theme.css(Theme.text, 0.07)
                    c.lineWidth = 1
                    for (const g of [50, 100, 200, 500, 1000, 2000, 5000, 10000]) { c.beginPath(); c.moveTo(px(g), 0); c.lineTo(px(g), h); c.stroke() }
                    c.strokeStyle = Theme.css(Theme.text, 0.2)
                    c.beginPath(); c.moveTo(0, mid); c.lineTo(w, mid); c.stroke()
                    c.strokeStyle = Theme.css(Theme.accent, 0.95)
                    c.lineWidth = 2
                    c.beginPath()
                    for (let i = 0; i <= w; i += 2) {
                        const y = py(page.eqCurveDb(page.posToFreq(i / w)))
                        if (i === 0) c.moveTo(i, y); else c.lineTo(i, y)
                    }
                    c.stroke()
                    page.eqBands.forEach((b, i) => {
                        if (!b || b.on === false) return
                        c.beginPath()
                        c.arc(px(b.freq), py(page.eqGainless[b.type] ? 0 : b.gain), i === page.eqSel ? 5 : 3.5, 0, Math.PI * 2)
                        if (i === page.eqSel) { c.fillStyle = Theme.css(Theme.accent, 1); c.fill() }
                        else { c.strokeStyle = Theme.css(Theme.text, 0.55); c.lineWidth = 1.5; c.stroke() }
                    })
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        let best = -1, bestD = 1e9
                        page.eqBands.forEach((b, i) => { const d = Math.abs(page.freqToPos(b.freq) * width - mouse.x); if (d < bestD) { bestD = d; best = i } })
                        if (best >= 0 && bestD < 40) page.eqSel = best
                    }
                }
            }
            Buttons {
                Repeater {
                    model: page.eqBands.length
                    HudButton { required property int index; label: "BAND " + (index + 1); on: page.eqSel === index; onClicked: page.eqSel = index }
                }
                HudButton { label: "+"; visible: page.eqBands.length < 8; onClicked: page.eqAdd() }
                HudButton { label: "−"; visible: page.eqBands.length > 0; danger: true; onClicked: page.eqRemove(page.eqSel) }
            }
            Buttons {
                visible: page.eqSel < page.eqBands.length
                Repeater {
                    model: page.service.eqTypeOptions
                    HudButton {
                        required property string modelData
                        label: page.eqTypeLabels[modelData] || modelData
                        on: page.eqSel < page.eqBands.length && (page.eqBands[page.eqSel].type || "bell") === modelData
                        onClicked: page.eqSet(page.eqSel, "type", modelData)
                    }
                }
            }
            Knobs {
                visible: page.eqSel < page.eqBands.length
                readonly property var b: page.eqSel < page.eqBands.length ? page.eqBands[page.eqSel] : null
                Knob { label: "Freq"; defaultValue: page.freqToPos(1000); value: parent.b ? page.freqToPos(parent.b.freq) : 0.5
                       readout: page.hz(page.posToFreq(live)) + " Hz"; onReleased: v => page.eqSet(page.eqSel, "freq", Math.round(page.posToFreq(v))) }
                Knob { visible: !!parent.b && !page.eqGainless[parent.b.type]; label: "Gain"; defaultValue: 0.5
                       value: parent.b ? (parent.b.gain + 18) / 36 : 0.5; readout: page.db(live * 36 - 18) + " dB"
                       onReleased: v => page.eqSet(page.eqSel, "gain", Math.round((v * 36 - 18) * 2) / 2) }
                Knob { visible: !!parent.b && !page.eqQless[parent.b.type]; label: "Q"; defaultValue: (0.707 - 0.1) / 9.9
                       value: parent.b ? (parent.b.q - 0.1) / 9.9 : 0.06; readout: (0.1 + live * 9.9).toFixed(2)
                       onReleased: v => page.eqSet(page.eqSel, "q", 0.1 + v * 9.9) }
            }
            Hint { visible: !page.eqBands.length; text: "No bands: pick a preset above or add one with +." }
        }
    }
}
