import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick
import qs

// Audio effects around the speaker calibration (Speaker.qml):
//
//   music EQ   EasyEffects, run headless (`easyeffects --gapplication-service`)
//              with one 10-band equalizer (~/.config/easyeffects/output/
//              quickshell-eq.json). Apps play into easyeffects_sink, the EQ
//              plays into the default output, so with the calibration
//              installed (speaker_tuning) the EQ sits on top of it. Gains are
//              written live to EasyEffects' dconf keys; an automatic preamp
//              keeps boosts from clipping. Bar chip + EqPanel.qml.
//
// The helpers need the graphical session's D-Bus, so instead of OpenRC
// services this singleton starts them (detached: a shell reload doesn't stop
// them) and restarts them if they die.
//
// Optional (Settings > Modules): off, EasyEffects isn't run at all.
//
//   qs ipc call eq toggle | on | off | preset NAME | panel | status
Scope {
    id: root

    // ---------------------------------------------------------------- EQ state
    readonly property var freqs: [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    readonly property real maxDb: 12
    // (the module being on is the switch: Settings > Modules)
    readonly property bool enabled: true
    property bool available: true          // easyeffects installed
    property bool eqOn: true
    property var gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property string preset: "Flat"         // "" once the sliders are moved by hand
    property var userPresets: ({})         // name -> gains
    property bool panelOpen: false
    readonly property real preamp: -Math.max(0, Math.max.apply(null, gains))

    // genre curves, 31 Hz .. 16 kHz
    readonly property var genres: [
        { name: "Flat",       g: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0] },
        { name: "Rock",       g: [5, 4, 3, 1, -1, -1, 1, 3, 4, 5] },
        { name: "Metal",      g: [4, 3, 0, -2, -3, -1, 2, 4, 5, 4] },
        { name: "Pop",        g: [-1, 1, 3, 4, 3, 0, -1, -1, 1, 2] },
        { name: "Hip-Hop",    g: [6, 5, 3, 1, -1, -1, 1, 0, 1, 2] },
        { name: "R&B",        g: [3, 6, 4, 1, -2, -1, 2, 2, 3, 3] },
        { name: "Electronic", g: [6, 5, 2, 0, -2, 1, 0, 2, 4, 5] },
        { name: "Jazz",       g: [3, 2, 1, 2, -1, -1, 0, 1, 2, 3] },
        { name: "Classical",  g: [4, 3, 2, 1, -1, -1, 0, 2, 3, 4] },
        { name: "Acoustic",   g: [3, 2, 1, 1, 2, 2, 3, 2, 2, 1] },
        { name: "Country",    g: [2, 2, 1, 0, -1, 0, 2, 3, 3, 2] },
        { name: "Reggae",     g: [3, 4, 2, 0, -2, -1, 1, 2, 1, 0] },
        { name: "Lo-fi",      g: [2, 3, 2, 0, -1, -1, -2, -3, -5, -8] },
        { name: "Vocal",      g: [-3, -2, -1, 1, 3, 4, 4, 3, 1, 0] },
        { name: "Bass Boost", g: [7, 6, 4, 2, 0, 0, 0, 0, 0, 0] },
        { name: "Late Night", g: [4, 3, 1, 0, -1, -1, 0, 1, 2, 3] }
    ]

    function setGain(i, db) {
        const g = gains.slice()
        g[i] = Math.round(Math.max(-maxDb, Math.min(maxDb, db)) * 2) / 2
        gains = g
        preset = ""
        pushSoon.restart()
    }
    function applyPreset(name) {
        const p = genres.find(x => x.name === name)
        const g = p ? p.g : userPresets[name]
        if (!g) return
        gains = g.slice()
        preset = name
        if (!eqOn) eqOn = true
        push()
    }
    function saveUser(name) {
        name = name.trim()
        if (!name || genres.some(x => x.name === name)) return
        const u = Object.assign({}, userPresets)
        u[name] = gains.slice()
        userPresets = u
        preset = name
        save()
    }
    function deleteUser(name) {
        const u = Object.assign({}, userPresets)
        delete u[name]
        userPresets = u
        if (preset === name) preset = ""
        save()
    }
    function setOn(v) {
        eqOn = v
        push()
    }

    // ---------------------------------------------------------------- apply
    readonly property string eqPath: "/com/github/wwmm/easyeffects/streamoutputs/equalizer/0/"
    function keyfile() {
        let l = "", r = ""
        for (let i = 0; i < 10; i++) {
            l += "band" + i + "-gain=" + gains[i].toFixed(1) + "\n"
            r += "band" + i + "-gain=" + gains[i].toFixed(1) + "\n"
        }
        return "[/]\noutput-gain=" + preamp.toFixed(1) + "\n\n[leftchannel]\n" + l + "\n[rightchannel]\n" + r
    }
    function push() {
        pushSoon.stop()
        if (!eeRunning) return
        if (pushProc.running) { pushAgain = true; return }
        pushProc.command = ["sh", "-c",
            "printf '%s' \"$1\" | dconf load \"$2\" && gsettings set com.github.wwmm.easyeffects bypass \"$3\"",
            "sh", keyfile(), eqPath, eqOn ? "false" : "true"]
        pushProc.running = true
        save()
    }
    property bool pushAgain: false
    Process {
        id: pushProc
        onExited: if (root.pushAgain) { root.pushAgain = false; root.push() }
    }
    // slider drags: at most ~15 writes a second
    Timer { id: pushSoon; interval: 60; onTriggered: root.push() }

    // ---------------------------------------------------------------- saved state
    readonly property string stateDir: Quickshell.env("HOME") + "/.local/share/quickshell"
    FileView {
        id: store
        path: root.stateDir + "/eq.json"
        onLoaded: {
            try {
                const d = JSON.parse(text())
                if (d.gains && d.gains.length === 10) root.gains = d.gains
                if (typeof d.on === "boolean") root.eqOn = d.on
                if (typeof d.preset === "string") root.preset = d.preset
                root.userPresets = d.user || {}
            } catch (e) {}
            root.loaded = true
        }
        onLoadFailed: root.loaded = true
    }
    property bool loaded: false
    function save() {
        if (!loaded) return
        mkdir.running = true
        store.setText(JSON.stringify({ on: eqOn, preset: preset, gains: gains, user: userPresets }, null, 1))
    }
    Process { id: mkdir; command: ["mkdir", "-p", root.stateDir] }

    // ---------------------------------------------------------------- EasyEffects
    property bool eeRunning: false
    readonly property string eePreset: Quickshell.env("HOME") + "/.config/easyeffects/output/quickshell-eq.json"

    // the preset EasyEffects loads at start: the equalizer, gains from this file
    function presetJson() {
        const band = (i, f) => ({ frequency: f, gain: gains[i], mode: "RLC (BT)", mute: false, q: 1.41, slope: "x1", solo: false, type: "Bell" })
        const ch = () => { const o = {}; freqs.forEach((f, i) => o["band" + i] = band(i, f)); return o }
        return JSON.stringify({ output: {
            blocklist: [],
            "equalizer#0": { balance: 0, bypass: false, "input-gain": 0, "output-gain": preamp, mode: "IIR",
                             "num-bands": 10, "pitch-left": 0, "pitch-right": 0, "split-channels": false,
                             left: ch(), right: ch() },
            plugins_order: ["equalizer#0"] } }, null, 2)
    }

    // every 10 s: is PipeWire up, is EasyEffects running with our equalizer?
    Timer {
        interval: 10000
        repeat: true
        running: root.loaded && root.enabled && root.available
        triggeredOnStart: true
        onTriggered: if (!check.running) check.running = true
    }
    Process {
        id: check
        command: ["sh", "-c",
            "pgrep -x pipewire >/dev/null || { echo nopw; exit; }; "
            + "pgrep -x easyeffects >/dev/null && echo ee; "
            + "pactl list short sinks | grep -q easyeffects_sink && echo sink; "
            + "gsettings get com.github.wwmm.easyeffects.streamoutputs plugins"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text
                if (t.indexOf("nopw") >= 0) { root.eeRunning = false; return }
                if (t.indexOf("ee\n") < 0) { root.eeRunning = false; root.startEe(); return }
                // running but not in PipeWire (PipeWire was restarted): twice in a row, restart it
                if (t.indexOf("sink\n") < 0) {
                    if (++root.lost >= 2) { root.lost = 0; root.eeRunning = false; root.restartEe() }
                    return
                }
                root.lost = 0
                if (t.indexOf("equalizer#0") < 0) { root.loadEePreset(); return }
                if (!root.eeRunning) { root.eeRunning = true; root.push() }
                if (!reclaim.running) reclaim.running = true
            }
        }
    }
    // apps moved around the EQ (the calibrator's "use calibrated output",
    // a stream moved by hand) go back into it; streams that asked not to be
    // moved (measurement sweeps, filter outputs) stay where they are
    Process {
        id: reclaim
        command: ["python3", "-I", "-c", "
import json, subprocess
run = lambda *a: subprocess.run(['pactl', *a], capture_output=True, text=True).stdout
sinks = {s['index']: s['name'] for s in json.loads(run('-f', 'json', 'list', 'sinks') or '[]')}
ee = [i for i, n in sinks.items() if n == 'easyeffects_sink']
for st in json.loads(run('-f', 'json', 'list', 'sink-inputs') or '[]') if ee else []:
    p = st.get('properties', {})
    if not p.get('application.name') or p.get('application.name') == 'EasyEffects' or p.get('node.dont-move') == 'true':
        continue
    if st.get('sink') != ee[0]:
        print('moving', p.get('application.name'), 'from', sinks.get(st.get('sink')))
        run('move-sink-input', str(st['index']), 'easyeffects_sink')
"]
        stdout: StdioCollector { onStreamFinished: if (text.trim()) console.log("audiofx:", text.trim()) }
    }
    // switched off in Settings > Modules: stop EasyEffects (apps fall back to
    // the default output on their own)
    function moduleStopping() {
        Quickshell.execDetached(["pkill", "-x", "easyeffects"])
    }
    Process {
        running: true
        command: ["sh", "-c", "command -v easyeffects >/dev/null"]
        onExited: code => root.available = code === 0
    }

    function startEe() {
        console.log("audiofx: starting EasyEffects")
        eeStart.command = ["sh", "-c",
            // apps' output only (the microphone chain is NoiseTorch + mic-effects),
            // following the default output, and our preset written fresh
            "gsettings set com.github.wwmm.easyeffects process-all-inputs false; "
            + "gsettings set com.github.wwmm.easyeffects process-all-outputs true; "
            + "gsettings set com.github.wwmm.easyeffects.streamoutputs use-default-output-device true; "
            + "gsettings set com.github.wwmm.easyeffects.streaminputs plugins '[]'; "
            + "mkdir -p \"$(dirname \"$2\")\" && printf '%s' \"$1\" > \"$2\"; "
            + "setsid -f easyeffects --gapplication-service >/dev/null 2>&1; "
            + "for i in 1 2 3 4 5 6 7 8 9 10; do sleep 0.5; easyeffects -l quickshell-eq 2>/dev/null && break; done",
            "sh", presetJson(), eePreset]
        eeStart.running = true
    }
    property int lost: 0
    function restartEe() {
        console.log("audiofx: EasyEffects lost PipeWire, restarting it")
        eeStart.command = ["sh", "-c", "pkill -x easyeffects; sleep 1"]
        eeStart.running = true      // then the next check starts it
    }
    function loadEePreset() {
        eeStart.command = ["sh", "-c", "printf '%s' \"$1\" > \"$2\" && easyeffects -l quickshell-eq", "sh", presetJson(), eePreset]
        eeStart.running = true
    }
    Process {
        id: eeStart
        onExited: { root.eeRunning = false; if (!check.running) check.running = true }
    }

    // where the EQ ends up: the default output (the calibrated one when it's installed)
    readonly property var outputNode: Pipewire.defaultAudioSink
    readonly property bool calibrated: outputNode ? outputNode.name === "speaker_tuning" : false
    readonly property string outputName: outputNode ? (outputNode.description || outputNode.name) : "no output"

    IpcHandler {
        target: "eq"
        function toggle(): void { root.setOn(!root.eqOn) }
        function on(): void { root.setOn(true) }
        function off(): void { root.setOn(false) }
        function preset(name: string): void { root.applyPreset(name) }
        function panel(): void { root.panelOpen = !root.panelOpen }
        function status(): string {
            return (root.eqOn ? "on" : "off") + " · " + (root.preset || "custom") + " · [" + root.gains.join(", ")
                + "] · preamp " + root.preamp + " dB · easyeffects " + (root.eeRunning ? "running" : "not running")
                + " · → " + root.outputName
        }
    }
}
