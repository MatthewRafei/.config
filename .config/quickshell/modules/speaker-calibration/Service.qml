import Quickshell
import Quickshell.Io
import QtQuick
import qs

// Speaker calibration, adapted from thefreshoffice/omarchy-speaker-calibrator:
// measure the speakers with a microphone (sine sweeps), fit a protective
// parametric EQ, and run it as a PipeWire filter-chain sink ("Calibrated
// Speakers") in front of the real output. Shown at the bottom of Settings >
// Sound (SettingsPages/SpeakerCalibration.qml).
//
// All the work is done by speaker-calibrate.py, run with the venv in
// ~/.local/share/speaker-calibrator-venv (numpy + scipy). The filter graph runs
// as the OpenRC user service speaker-tuning (and speaker-loudness for volume-
// following loudness compensation), scripts in ~/.config/rc/init.d.
// Profiles and recordings: ~/.local/share/speaker-calibrator.
//
//   qs ipc call speaker panel      open Settings > Sound
//   qs ipc call speaker bypass     calibration on / off
Scope {
    id: root

    readonly property string helper: Quickshell.shellPath("modules/speaker-calibration/speaker-calibrate.py")
    readonly property string venv: Quickshell.env("HOME") + "/.local/share/speaker-calibrator-venv"

    property var sinks: []
    property var microphones: []
    property var status: ({ service: "unknown", enabled: false, profile: null, bypass: false })
    property var proposal: null
    property var chosen: ({})              // hand-picked { sink, mic, channel }, kept by the helper
    property string phase: ""
    property string error: ""
    property string message: ""
    property var offer: null               // a failure's suggested microphone
    // from start until the result is handled (the process can exit before its output is read)
    property bool _pending: false
    readonly property bool busy: _pending

    // switches that land in a fraction of a second don't count as working
    readonly property var _quickPhases: ["relevel", "deepbass", "loudness", "bypass", "compare",
        "status", "devices", "cache", "output", "previewapply", "previewdiscard", "remember"]
    readonly property bool working: busy && _quickPhases.indexOf(phase) < 0
    readonly property bool measuring: busy && phase === "measure"

    // ------------------------------------------------ derived state
    readonly property var profile: status.profile || null
    readonly property bool calibrated: profile !== null
    readonly property bool enabled: status.enabled === true      // sound flows through the filter
    readonly property bool bypassed: status.bypass === true
    readonly property bool previewing: status.previewing === true
    readonly property var support: status.measurementSupport || ({ available: true, missing: [] })
    readonly property bool canMeasure: support.available !== false

    // the devices picked for the next measurement (indices into sinks / microphones)
    property int sinkIndex: -1
    property int micIndex: -1
    property int channel: 0
    readonly property var sink: sinkIndex >= 0 ? sinks[sinkIndex] : null
    readonly property var mic: micIndex >= 0 ? microphones[micIndex] : null
    readonly property int micChannels: mic ? Math.max(1, Number(mic.channels || 1)) : 1
    // a built-in array is measured on every channel at once
    readonly property bool micArray: mic !== null && mic.internal === true && micChannels > 1

    // the sound options; they follow the installed profile until changed here
    property string voicing: "neutral"     // neutral (flat) | warm
    property string bass: "normal"         // normal | full ("Loudness")
    property string loudness: "protected"  // protected | balanced | matched ("Make it louder")
    property bool _adopted: false

    function options() {
        return { voicing: voicing, bass: bass, loudness: loudness, channelTrim: "off" }
    }

    // "Calibrated · Loudness on · Louder off"
    function simpleLabel(p) {
        if (!p) return ""
        const parts = [p.bass === "full" ? "loudness on" : "loudness off"]
        const l = p.loudness || "protected"
        parts.push(l === "matched" ? "louder on" : l === "balanced" ? "louder halfway" : "louder off")
        if (p.voicing === "warm") parts.push("warm")
        return parts.join(" · ")
    }
    function playingSummary() {
        const c = status.compare
        if (c && c.available && c[c.active]) return c[c.active]
        if (c && c.current) return c.current
        return null
    }
    // one line about where the sound is going
    function summary() {
        if (working) return message
        if (previewing) return "New calibration playing: apply it or keep the previous one"
        if (!enabled) {
            if (calibrated && status.service === "active")
                return "Playing to " + (status.defaultSinkDescription || "another output") + ", not through the calibration"
            return calibrated ? "Calibration stopped" : "Not calibrated yet"
        }
        if (bypassed) return "Calibration off: hearing the plain speakers"
        const s = playingSummary()
        return "Calibrated · " + simpleLabel(s && s.bass !== undefined ? s : profile)
    }
    function verificationSummary(check) {
        if (!check) return ""
        if (check.stale) return "The calibration has changed since it was last checked."
        if (check.verdict === "inconclusive")
            return "The check could not measure cleanly, so it says nothing about the calibration."
        const errors = check.target_error_db || {}
        const gained = Number(errors.before || 0) - Number(errors.measured || 0)
        const off = Number((check.model_error_db || {}).rms || 0).toFixed(1)
        if (check.verdict === "pass")
            return "Checked: follows the plan within " + off + " dB, " + gained.toFixed(1)
                + " dB closer to the target than the plain speakers."
        return "Check " + check.verdict + ": " + ((check.notes && check.notes.length) ? check.notes[0] : "off plan by " + off + " dB.")
    }
    function qualityText() {
        const q = proposal && proposal.quality
        if (!q || q.accepted !== false) return ""
        return (q.failures || []).concat(q.warnings || []).concat(q.guidance || []).join("\n")
    }
    // the calibration's own microphone must make the check
    readonly property var profileMic: profile ? (profile.microphone || null) : null
    readonly property bool profileMicConnected: profileMic !== null && firstWhere(microphones, m => m.name === profileMic.name) >= 0

    // ------------------------------------------------ device choice
    function indexOf(list, name) {
        if (!name) return -1
        for (let i = 0; i < list.length; i++) if (list[i].name === name) return i
        return -1
    }
    // index of the first match; a loop because these lists aren't always real JS arrays
    function firstWhere(list, pred) {
        for (let i = 0; i < (list ? list.length : 0); i++) if (pred(list[i])) return i
        return -1
    }
    function firstUsable(list, internalOnly) {
        for (let i = 0; i < list.length; i++)
            if ((!internalOnly || list[i].internal) && list[i].available !== false) return i
        return -1
    }
    // hand pick while connected, else the calibration's own devices, else
    // the default / first usable one
    function selectDevices() {
        const p = profile || {}
        let s = indexOf(sinks, chosen.sink)
        if (s < 0) s = indexOf(sinks, (p.speaker || {}).name)
        if (s < 0) s = indexOf(sinks, status.defaultSink)
        if (s < 0) s = firstWhere(sinks, x => x.default)
        if (s < 0) s = firstUsable(sinks, false)
        sinkIndex = s
        const before = mic ? mic.name : ""
        let m = indexOf(microphones, chosen.mic)
        if (m < 0) m = indexOf(microphones, (p.microphone || {}).name)
        if (m < 0) m = firstWhere(microphones, x => x.default && x.available !== false)
        if (m < 0) m = firstUsable(microphones, false)
        micIndex = m
        const after = mic ? mic.name : ""
        if (after === chosen.mic) channel = Math.max(0, Number(chosen.channel) || 0)
        else if (before !== after) channel = 0
        if (channel >= micChannels) channel = 0
    }
    function pickSink(i) {
        sinkIndex = i
        remember()
    }
    function pickMic(i) {
        if (i === micIndex && micChannels > 1 && !micArray) channel = (channel + 1) % micChannels
        else { micIndex = i; channel = 0 }
        remember()
    }
    function remember() {
        const args = ["remember-selection-json"]
        if (sink) args.push("--sink", sink.name)
        if (mic) args.push("--mic", mic.name)
        args.push("--channel", String(channel))
        chosen = { sink: sink ? sink.name : "", mic: mic ? mic.name : "", channel: channel }
        if (busy) { _rememberPending = args; return }
        start("remember", args)
    }
    property var _rememberPending: null

    // ------------------------------------------------ actions
    function refresh() {
        if (busy) { _refreshPending = true; return }
        start("devices", ["devices-json"])
    }
    property bool _refreshPending: false
    function refreshStatus() { if (!busy) start("status", ["status-json"]) }

    function optionArgs(o) {
        return ["--voicing", o.voicing, "--loudness", o.loudness, "--bass", o.bass, "--channel-trim", o.channelTrim]
    }
    // measure and, when it passes, play it straight away as a preview
    function calibrate(micName, ch) {
        if (!sink) return
        const m = micName || (mic ? mic.name : "")
        if (!m) return
        proposal = null
        const c = ch !== undefined ? ch : (micArray ? "all" : channel)
        start("measure", ["calibrate-json", "--sink", sink.name, "--mic", m, "--channel", String(c)]
            .concat(optionArgs(options())).concat(["--preview"]))
    }
    // bass / loudness move live; a different voicing needs a refit of the saved sweeps
    function applyOptions() {
        if (profile && enabled && (profile.voicing || "neutral") === voicing)
            start("relevel", ["relevel-json", "--bass", bass, "--loudness", loudness])
        else if (proposal && proposal.measurement)
            start("refit", ["reanalyze-saved-json"].concat(optionArgs(options())).concat(["--install"]))
    }
    function setBass(full) { if (busy) return; bass = full ? "full" : "normal"; applyOptions() }
    function setLouder(on) { if (busy) return; loudness = on ? "matched" : "protected"; applyOptions() }
    function setVoicing(v) { if (busy || v === voicing) return; voicing = v; applyOptions() }

    function applyPreview() { start("previewapply", ["preview-apply-json"]) }
    function discardPreview() { start("previewdiscard", ["preview-discard-json"]) }
    function install() { start("install", ["install-proposal"]) }
    function compare() { start("compare", ["compare-toggle"]) }
    function bypass() { if (calibrated) start("bypass", ["bypass-toggle"]) }
    function deepBass() { start("deepbass", ["deep-bass-toggle"]) }
    function loudnessCompensation() { start("loudness", ["loudness-toggle"]) }
    function useCalibratedOutput() { start("output", ["use-calibrated-output"]) }
    function verify() { start("verify", ["verify-json"]) }
    function refine() { start("refine", ["refine-json", "--install"]) }
    function disable() { start("disable", ["disable"]) }
    function installSupport() { start("support", ["install-measurement-support"]) }
    function copy(text) { Quickshell.execDetached(["wl-copy", "--", text]) }

    readonly property var _ownPhases: ["status", "devices", "cache", "remember"]
    readonly property var _messages: ({
        measure: "Measuring: a short level check, then six sweeps, about 30 seconds. Keep quiet…",
        compare: "Switching profiles…", bypass: "Switching…", relevel: "Switching…",
        verify: "Checking: playing the sweeps through the calibration…",
        refine: "Improving from the last check…", deepbass: "Switching deep bass…",
        loudness: "Switching loudness compensation…", refit: "Applying…", install: "Installing…",
        support: "Installing numpy and scipy into the venv…", disable: "Removing the calibration…",
        previewapply: "Applying…", previewdiscard: "Restoring…", output: "Moving the sound…"
    })
    function start(op, args) {
        if (busy) return
        phase = op
        if (_ownPhases.indexOf(op) < 0) { error = ""; offer = null; message = _messages[op] || "Working…" }
        _pending = true; _exited = false; _code = 0; _outDone = false; _errDone = false
        // the venv's interpreter when it exists; system python can still do
        // everything but measuring, and the helper then offers to make the venv
        proc.command = ["sh", "-c",
            'p="$1/bin/python"; [ -x "$p" ] || p=python3; shift; exec env -u PYTHONHOME -u PYTHONPATH "$p" -B -s "$@"',
            "sh", venv, helper].concat(args)
        proc.running = true
    }

    // a result is handled once the process has exited and both streams are read
    property bool _exited: false
    property int _code: 0
    property bool _outDone: false
    property bool _errDone: false
    function _maybeFinish() {
        if (!_pending || !_exited || !_outDone || !_errDone) return
        finish(_code)
        _pending = false
    }

    onStatusChanged: {
        if (!_adopted && profile) {
            voicing = profile.voicing === "warm" ? "warm" : "neutral"
            bass = profile.bass === "full" ? "full" : "normal"
            loudness = profile.loudness || "protected"
            _adopted = true
        }
        selectDevices()
    }
    onBusyChanged: if (!busy) Qt.callLater(() => {
        if (root.busy) return
        if (root._rememberPending) { const a = root._rememberPending; root._rememberPending = null; root.start("remember", a) }
        else if (root._refreshPending) { root._refreshPending = false; root.start("devices", ["devices-json"]) }
    })

    function merge(extra) { status = Object.assign({}, status, extra) }

    function finish(code) {
        const raw = outC.text.trim(), stderr = errC.text.trim()
        const op = phase
        phase = ""
        if (code !== 0) {
            try {
                const f = JSON.parse(raw)
                if (f && typeof f.error === "string") {
                    offer = f.offer && typeof f.offer.microphone === "string" ? f.offer : null
                    error = f.error; message = ""
                    return
                }
            } catch (e) {}
            // background polls stay quiet
            if (op !== "status" && op !== "cache") { error = stderr || raw || "Operation failed"; message = "" }
            return
        }
        let d
        try { d = raw === "" ? {} : JSON.parse(raw) } catch (e) {
            // a few verbs (install-proposal, disable) answer in plain text
            d = null
        }
        if (d === null && ["disable"].indexOf(op) < 0) { error = "Invalid response from the calibration helper"; message = ""; return }

        if (op === "devices") {
            chosen = d.chosen || ({}); sinks = d.sinks || []; microphones = d.microphones || []
            Qt.callLater(refreshStatus)
        } else if (op === "cache") {
            if (d && d.service && status.service === "unknown") { status = d; proposal = d.proposal || null }
            Qt.callLater(refresh)
        } else if (op === "status") {
            status = d
            proposal = d.proposal || null
            if (message === "Working…") message = ""
        } else if (op === "remember") {
            chosen = d.chosen || chosen
        } else if (op === "measure" || op === "refit" || op === "refine") {
            proposal = d
            const ok = d.quality && d.quality.accepted
            if (ok && d.installed) {
                merge({ enabled: true, profile: d, bypass: false })
                message = op === "measure"
                    ? (d.previewing ? "New calibration measured and playing. Apply it or keep the previous one?"
                                    : "Calibrated and playing: " + simpleLabel(d))
                    : op === "refine" ? "Improved from the check. Check it again to see if it helped."
                    : "Applied: " + simpleLabel(d)
            } else if (ok) {
                message = "Measurement accepted; nothing changes until you install it"
            } else {
                message = ""
                error = "The measurement was rejected; see why below and try again"
            }
            Qt.callLater(refreshStatus)
        } else if (op === "install") {
            message = "Installed and playing"
            Qt.callLater(refreshStatus)
        } else if (op === "relevel") {
            merge({ profile: d.profile, bypass: false })
            if (d.proposal) proposal = d.proposal
            message = d.message || ""
            Qt.callLater(refreshStatus)
        } else if (op === "previewapply" || op === "previewdiscard") {
            if (d.profile) merge({ profile: d.profile, previewing: false, bypass: false })
            message = d.message || ""
            Qt.callLater(refreshStatus)
        } else if (op === "compare") {
            const p = d[d.active]
            merge({ compare: d, bypass: false })
            message = "Now playing: " + (p && p.label ? p.label : d.active)
        } else if (op === "bypass") {
            merge({ compare: d, bypass: d.bypass })
            const match = Number(d.level_match_db || 0)
            message = d.bypass ? "Calibration off: the plain speakers"
                + (match < -0.05 ? ", " + Math.abs(match).toFixed(1) + " dB quieter to match loudness" : "")
                : "Calibration on"
        } else if (op === "verify") {
            merge({ verification: d })
            message = verificationSummary(d)
        } else if (op === "deepbass") {
            merge({ deepBass: d.deep_bass !== undefined ? d.deep_bass : status.deepBass })
            message = d.message || ""
            Qt.callLater(refreshStatus)
        } else if (op === "loudness") {
            merge({ loudnessCompensation: d.loudness_compensation, loudnessTracker: d.tracker })
            message = d.message || ""
            Qt.callLater(refreshStatus)
        } else if (op === "output") {
            status = d
            message = d.message || ""
        } else if (op === "support") {
            message = d.message || ""
            Qt.callLater(refreshStatus)
        } else if (op === "disable") {
            merge({ service: "inactive", enabled: false })
            message = "Calibration stopped and removed from the output"
            Qt.callLater(refreshStatus)
        }
    }

    Process {
        id: proc
        stdout: StdioCollector { id: outC; onStreamFinished: { root._outDone = true; root._maybeFinish() } }
        stderr: StdioCollector { id: errC; onStreamFinished: { root._errDone = true; root._maybeFinish() } }
        onExited: code => { root._code = code; root._exited = true; root._maybeFinish() }
    }

    // draw from the last known state, then ask for the real one
    Component.onCompleted: start("cache", ["status-cache-json"])
    Component.onDestruction: if (proc.running) proc.signal(15)

    // the output can move under us (headphones, an app switching it)
    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: root.refreshStatus()
    }

    IpcHandler {
        target: "speaker"
        function panel(): void { Quickshell.execDetached(["qs", "ipc", "call", "settings", "page", "Sound"]) }
        function bypass(): void { root.bypass() }
        function refresh(): void { root.refresh() }
    }
}
