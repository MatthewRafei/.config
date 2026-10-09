import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick
import qs

// The microphone chain (Settings > Audio FX):
//
//   mic ─▶ NoiseTorch ─▶ mic-effects rack ─▶ "Microphone Effects" ─▶ apps
//
//   noise suppression   NoiseTorch-ng's RNNoise LADSPA plugin with its voice
//                       threshold (~/.local/lib/noisetorch, built from
//                       ~/.local/src/NoiseTorch). The NoiseTorch app loads it
//                       through pipewire-pulse's module-ladspa-source, which
//                       this PipeWire build doesn't have, so the same plugin
//                       runs here as a PipeWire filter-chain ("NoiseTorch
//                       Microphone", node noisetorch_mic).
//   mic effects         WhoIsCalebBrown/mic-effects: a small C++ PipeWire
//                       daemon (~/.local/lib/mic-effects, source in
//                       ~/.local/src/mic-effects) with the effects rack,
//                       driven over its socket (port of its Service.qml).
//
// Apps keep "Microphone Effects" as their mic: switching effects off makes the
// rack pass audio through, and noise suppression only changes what feeds it.
// Both helpers are started detached (a shell reload doesn't cut the mic) and
// restarted if they die.
//
//   qs ipc call micfx noise on|off · rack on|off · mute · status
Scope {
    id: root

    // ---------------------------------------------------------------- settings
    // both optional and off on a new machine (state is per machine): off, the
    // filter / daemon isn't run at all and nothing is polled
    property bool noiseOn: false
    property bool fxEnabled: false        // the mic effects rack
    property bool noiseAvailable: true    // the RNNoise plugin is built
    property bool fxAvailable: true       // the mic-effects daemon is built
    property int threshold: 85            // NoiseTorch's voice activation, 0..95 %
    property string mic: ""               // the real microphone (node name)
    property bool loaded: false

    readonly property string stateDir: Quickshell.env("HOME") + "/.local/share/quickshell"
    FileView {
        id: store
        path: root.stateDir + "/micfx.json"
        onLoaded: {
            try {
                const d = JSON.parse(text())
                if (typeof d.noiseOn === "boolean") root.noiseOn = d.noiseOn
                if (typeof d.fxEnabled === "boolean") root.fxEnabled = d.fxEnabled
                if (typeof d.threshold === "number") root.threshold = d.threshold
                if (typeof d.mic === "string") root.mic = d.mic
            } catch (e) {}
            root.loaded = true
        }
        onLoadFailed: root.loaded = true
    }
    function save() {
        if (!loaded) return
        store.setText(JSON.stringify({ noiseOn: noiseOn, fxEnabled: fxEnabled, threshold: threshold, mic: mic }, null, 1))
    }

    // node names that are ours, never "the microphone"
    readonly property var virtualNames: ["mic-effects", "noisetorch_mic", "easyeffects_source"]
    function isVirtual(name) { return virtualNames.indexOf(name) >= 0 || /\.monitor$/.test(name) }

    // real microphones PipeWire knows about
    // (properties are only filled in for tracked nodes; type always is)
    readonly property var micNodes: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioSource && !isVirtual(n.name))
    function micLabel(name) {
        const n = micNodes.find(x => x.name === name)
        if (!n) return name || "none"
        return n.description || n.nickname || n.name
    }

    function setNoise(on) {
        noiseOn = on
        save()
        applyNoise()
        // without the rack, apps record from NoiseTorch (or the plain mic) directly
        if (!fxEnabled) pendingDefault = on ? "noisetorch_mic" : mic
    }
    function setFx(on) {
        fxEnabled = on
        save()
        if (on) { tookDefault = false; if (!probe.running) probe.running = true }
        else {
            Quickshell.execDetached(["sh", "-c", "\"$1\" quit >/dev/null 2>&1; sleep 1; pkill -f \"^$1 run\"", "sh", daemon])
            daemonRunning = false
            pendingDefault = noiseOn ? "noisetorch_mic" : mic
        }
    }
    // switched off in Settings > Modules: stop both helpers, back to the plain mic
    function moduleStopping() {
        Quickshell.execDetached(["sh", "-c", "\"$1\" quit >/dev/null 2>&1; pkill -f \"^$1 run\"; pkill -f \" -c $2\\$\"; "
            + "[ -n \"$3\" ] && pactl set-default-source \"$3\"", "sh", daemon, ntConf, mic])
    }

    // a default mic to switch to once its node exists
    property string pendingDefault: ""
    Process {
        running: true
        command: ["sh", "-c", "[ -r \"$1\" ] || echo nonoise; [ -x \"$2\" ] || echo nofx", "sh", root.plugin, root.daemon]
        stdout: StdioCollector {
            onStreamFinished: {
                root.noiseAvailable = text.indexOf("nonoise") < 0
                root.fxAvailable = text.indexOf("nofx") < 0
            }
        }
    }
    function setThreshold(t) { threshold = Math.round(Math.max(0, Math.min(95, t))); save(); restartNoise.restart() }
    function setMicSource(name) { mic = name; save(); restartNoise.restart() }

    // ---------------------------------------------------------------- NoiseTorch filter
    readonly property string plugin: Quickshell.env("HOME") + "/.local/lib/noisetorch/rnnoise_ladspa.so"
    readonly property string ntConf: stateDir + "/noisetorch.conf"
    // pipewire under another name: the session's PipeWire launcher won't start
    // while any process called "pipewire" runs, and restarts kill them all
    readonly property string ntBin: Quickshell.env("HOME") + "/.local/lib/noisetorch/noisetorch-filter"
    function ntConfText() {
        return "# written by quickshell (MicFx.qml); NoiseTorch-ng's RNNoise filter\n"
            + "context.spa-libs = { audio.convert.* = audioconvert/libspa-audioconvert support.* = support/libspa-support }\n"
            + "context.modules = [\n"
            + "  { name = libpipewire-module-rt flags = [ ifexists nofail ] }\n"
            + "  { name = libpipewire-module-protocol-native }\n"
            + "  { name = libpipewire-module-client-node }\n"
            + "  { name = libpipewire-module-adapter }\n"
            + "  { name = libpipewire-module-filter-chain\n"
            + "    args = {\n"
            + "      node.description = \"NoiseTorch Microphone\"\n"
            + "      media.name = \"NoiseTorch Microphone\"\n"
            + "      filter.graph = { nodes = [ { type = ladspa name = rnnoise plugin = \"" + plugin + "\" label = noisetorch\n"
            + "                                   control = { \"VAD %%\" = " + threshold + " } } ] }\n"
            + "      audio.rate = 48000\n"
            + "      audio.channels = 1\n"
            + "      audio.position = [ MONO ]\n"
            + "      capture.props = { node.name = \"noisetorch_mic.capture\" node.passive = true target.object = \"" + mic + "\" }\n"
            + "      playback.props = { node.name = \"noisetorch_mic\" media.class = Audio/Source }\n"
            + "    }\n"
            + "  }\n"
            + "]\n"
    }
    // (re)start it with the current mic and threshold; stop it when off
    function applyNoise() {
        ntProc.command = ["sh", "-c",
            "pkill -f \" -c $2\\$\"; "
            + "[ \"$4\" = on ] || exit 0; "
            + "mkdir -p \"$(dirname \"$2\")\" && printf '%s' \"$1\" > \"$2\" && "
            + "[ -r \"$3\" ] && setsid -f \"$5\" -c \"$2\" >/dev/null 2>&1",
            "sh", ntConfText(), ntConf, plugin, noiseOn && mic ? "on" : "off", ntBin]
        ntProc.running = true
    }
    Process { id: ntProc; onExited: wireSoon.restart() }
    Timer { id: restartNoise; interval: 500; onTriggered: root.applyNoise() }

    // ---------------------------------------------------------------- mic-effects daemon
    readonly property string daemon: Quickshell.env("HOME") + "/.local/lib/mic-effects/mic-effects-server"
    readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/mic-effects/ctl.sock"

    // every 5 s: is everything that should run running?
    Timer {
        interval: 5000
        repeat: true
        running: root.loaded && (root.noiseOn || root.fxEnabled || root.pendingDefault !== "" || root.daemonRunning)
        triggeredOnStart: true
        onTriggered: if (!probe.running) probe.running = true
    }
    Process {
        id: probe
        command: ["sh", "-c",
            "pgrep -x pipewire >/dev/null || { echo nopw; exit; }; "
            + "pgrep -f \"^$3 -c $1\\$\" >/dev/null && echo nt; "
            + "pactl list short sources | grep -qw noisetorch_mic && echo ntnode; "
            + "pgrep -f \"^$2 run\" >/dev/null && echo fx; "
            + "pactl list short sources | cut -f2; echo ---; "
            + "pactl get-default-source", "sh", root.ntConf, root.daemon, root.ntBin]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n")
                if (l.indexOf("nopw") >= 0) return
                root.defaultSource = l[l.length - 2] || ""
                // the first time: the mic in use now is the real microphone
                if (!root.mic && root.defaultSource && !root.isVirtual(root.defaultSource)) { root.mic = root.defaultSource; root.save() }
                const nt = l.indexOf("nt") >= 0, fx = l.indexOf("fx") >= 0
                if (nt !== (root.noiseOn && !!root.mic)) root.applyNoise()
                // running but not in PipeWire (PipeWire was restarted): twice in a row, restart it
                else if (nt && l.indexOf("ntnode") < 0) {
                    if (++root.ntLost >= 2) { root.ntLost = 0; console.log("micfx: NoiseTorch filter lost PipeWire, restarting it"); root.applyNoise() }
                } else root.ntLost = 0
                if (!fx && root.fxEnabled && root.fxAvailable) root.startDaemon()
                if (fx && !root.fxEnabled) Quickshell.execDetached(["pkill", "-f", "^" + root.daemon + " run"])
                root.daemonRunning = fx && root.fxEnabled
                if (root.pendingDefault) {
                    const want = root.pendingDefault
                    if (want === root.defaultSource) root.pendingDefault = ""
                    else if (l.indexOf(want) >= 0) {
                        root.pendingDefault = ""
                        Quickshell.execDetached(["pactl", "set-default-source", want])
                    }
                }
            }
        }
    }
    property bool daemonRunning: false
    property int ntLost: 0
    property string defaultSource: ""
    function startDaemon() {
        console.log("micfx: starting mic-effects")
        Quickshell.execDetached(["sh", "-c", "[ -x \"$1\" ] && setsid -f \"$1\" run >/dev/null 2>&1", "sh", daemon])
        tookDefault = false
    }
    function sync() { applyNoise() }

    // what feeds the rack, and "Microphone Effects" as the system mic once
    // after the daemon starts (choose another in Sound and it stays chosen)
    property bool tookDefault: false
    Timer { id: wireSoon; interval: 800; onTriggered: root.wire() }
    function wire() {
        if (!connected) return
        const want = noiseOn ? "noisetorch_mic" : mic
        if (want && wantedSource !== want) selectSource(want)
        if (!tookDefault && mic) {
            tookDefault = true
            Quickshell.execDetached(["pactl", "set-default-source", "mic-effects"])
        }
    }
    onConnectedChanged: if (connected) wireSoon.restart()
    // the daemon saves its monitor (your mic played to the speakers) and
    // starts with it on: keep it off unless it was switched on here
    property bool userListen: false
    function guardListen() { if (listen && !userListen) send({ cmd: "set", mic: { listen: false } }) }
    onNoiseOnChanged: wireSoon.restart()
    onMicChanged: wireSoon.restart()

    // ---------------------------------------------------------------- socket client
    // (port of mic-effects/plugin/Service.qml)
    property var state: ({})
    property string commandError: ""
    readonly property bool connected: sockUp
    readonly property var m: state.mic || ({})
    readonly property var settings: m.settings || ({})
    readonly property var sources: m.sources || []
    readonly property string wantedSource: m.wanted || ""
    readonly property bool muted: !!m.muted
    readonly property bool listen: !!m.listen
    readonly property bool active: !!m.active          // an app is recording from it
    readonly property real inLevel: m.inLevel || 0
    readonly property real outLevel: m.outLevel || 0
    readonly property bool enabled: settings.enabled !== false
    readonly property var stageOptions: m.stages || ["hpf", "hum", "nr", "gate", "comp", "deess", "eq", "pitch", "fx", "verb", "limit"]
    readonly property var eqTypeOptions: m.eqTypes || ["bell", "lowshelf", "highshelf", "highpass", "lowpass", "notch"]
    readonly property var spaceOptions: m.spaces || ["none", "room", "hall", "cathedral", "echo", "underwater"]
    readonly property var tuneKeyOptions: m.tuneKeys || []
    readonly property var tuneScaleOptions: m.tuneScales || []
    readonly property var userPresets: m.userPresets || []
    readonly property var chain: settings.chain && settings.chain.length ? settings.chain : stageOptions

    function send(obj) {
        if (!sockUp || !sock) return false
        commandError = ""
        sock.write(JSON.stringify(obj) + "\n")
        sock.flush()
        return true
    }
    function setMic(patch) { return send({ cmd: "set", mic: patch }) }
    function setSetting(key, value) { const p = {}; p[key] = value; return setMic({ settings: p }) }
    function setSettings(patch) { return setMic({ settings: patch }) }
    function selectSource(name) { return setMic({ source: name }) }
    function setMuted(v) { return setMic({ muted: !!v }) }
    function setListen(v) { userListen = !!v; return setMic({ listen: !!v }) }
    function refresh() { return send({ cmd: "get" }) }
    function saveUserPreset(key, name) { return send({ cmd: "presetSave", key: key, name: name }) }
    function renameUserPreset(key, name) { return send({ cmd: "presetRename", key: key, name: name }) }
    function deleteUserPreset(key) { return send({ cmd: "presetDelete", key: key }) }
    function moveStage(id, delta) {
        const c = chain.slice(), from = c.indexOf(id)
        if (from < 0) return
        const to = Math.max(0, Math.min(c.length - 1, from + delta))
        if (from === to) return
        c.splice(from, 1)
        c.splice(to, 0, id)
        setSetting("chain", c)
    }

    // the meters only run (and the real mic only opens) while someone looks
    property int meterHolders: 0
    function holdMeter(on) {
        meterHolders = Math.max(0, meterHolders + (on ? 1 : -1))
        send({ cmd: "micpreview", on: meterHolders > 0 || active })
    }

    // a fresh Socket per attempt: one that failed to connect doesn't retry
    property var sock: null
    property bool sockUp: false
    Component {
        id: sockComp
        Socket {
            path: root.socketPath
            connected: true
            parser: SplitParser {
                onRead: line => {
                    try {
                        const msg = JSON.parse(line)
                        if (msg && msg.type === "state") { root.state = msg; root.guardListen() }
                        else if (msg && msg.type === "error") root.commandError = String(msg.error || "command failed")
                    } catch (e) {}
                }
            }
            onConnectionStateChanged: {
                root.sockUp = connected
                if (connected && root.meterHolders > 0) root.send({ cmd: "micpreview", on: true })
                if (!connected) root.state = ({})
            }
        }
    }
    function reconnect() {
        if (sock) sock.destroy()
        sockUp = false
        sock = sockComp.createObject(root)
    }
    Component.onCompleted: reconnect()
    Timer {
        interval: 2000
        repeat: true
        running: !root.sockUp && root.fxEnabled
        onTriggered: root.reconnect()
    }

    IpcHandler {
        target: "micfx"
        function noise(state: string): void { root.setNoise(state !== "off") }
        function rack(state: string): void { root.setFx(state !== "off") }
        function mute(): void { root.setMuted(!root.muted) }
        function source(name: string): void { root.setMicSource(name) }
        function mics(): string { return root.micNodes.map(n => n.name).join("\n") }
        function status(): string {
            return "noise " + (root.noiseOn ? "on (" + root.threshold + "%)" : "off") + " · mic " + root.mic
                + " · rack " + (!root.fxEnabled ? "disabled" : root.connected ? (root.enabled ? "on" : "bypassed") + " ← " + root.wantedSource : "not connected")
                + (root.muted ? " · MUTED" : "") + " · default source " + root.defaultSource
        }
    }
}
