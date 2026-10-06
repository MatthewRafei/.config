pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Fingerprints via fprintd, for Settings > Fingerprint. All the D-Bus work is
// in fingerprint/fpctl.py; this keeps the state, so an enroll keeps going if
// you flip to another settings page and back.
// Enrolling and deleting ask for your password (polkit, see Auth.qml).
Singleton {
    id: root

    readonly property var fingerIds: [
        "left-little-finger", "left-ring-finger", "left-middle-finger", "left-index-finger", "left-thumb",
        "right-thumb", "right-index-finger", "right-middle-finger", "right-ring-finger", "right-little-finger"
    ]
    function label(f) {
        return f.replace(/-finger$/, "").replace("-", " ").toUpperCase()
    }

    property bool loaded: false
    property bool available: false
    property string deviceName: ""
    property int stages: 0
    property var fingers: []

    property string mode: "idle"      // idle | enroll | verify | delete
    property string target: ""        // finger being enrolled / verified / deleted
    property int stage: 0             // enroll stages passed
    property string result: ""        // last result: done | failed | match | nomatch | ""
    property string message: ""
    property bool messageBad: false

    readonly property bool busy: mode !== "idle"
    readonly property real progress: mode === "enroll" || result === "done"
        ? (stages > 0 ? Math.min(1, stage / stages) : 0) : 0

    // one per scan: "ok" | "retry" | "match" | "nomatch" (the glyph flashes)
    signal scan(string kind)

    function has(f) { return fingers.indexOf(f) >= 0 }

    function refresh() {
        if (!busy) run("list", [])
    }
    function enroll(f) {
        if (busy) return
        stage = 0
        run("enroll", [f])
        say("Authenticate, then press your " + label(f).toLowerCase() + " on the reader.", false)
    }
    function verify(f) {
        if (busy) return
        run("verify", f ? [f] : [])
        say("Press " + (f ? "your " + label(f).toLowerCase() : "any enrolled finger") + " on the reader.", false)
    }
    function remove(f) {
        if (busy) return
        run(f ? "delete" : "delete-all", f ? [f] : [])
        say("Authenticate to delete " + (f ? label(f).toLowerCase() : "every fingerprint") + ".", false)
    }
    function cancel() {
        if (proc.running) proc.running = false
        if (demoTimer.running) { demoTimer.stop(); mode = "idle"; stage = 0; say("Demo cancelled.", false) }
    }

    // fake enroll for the right index finger, no reader involved:
    //   qs ipc call fingerprint demo
    function demo() {
        if (busy) return
        if (stages <= 0) stages = 9
        mode = "enroll"
        target = "right-index-finger"
        result = ""
        stage = 0
        say("Demo: pretending to enroll.", false)
        demoTimer.start()
    }
    Timer {
        id: demoTimer
        interval: 1100
        repeat: true
        onTriggered: {
            const r = root.stage + 1 >= root.stages ? "enroll-completed"
                : Math.random() < 0.2 ? "enroll-retry-scan" : "enroll-stage-passed"
            root.handle({ ev: "enroll", result: r, done: r === "enroll-completed" })
            if (r === "enroll-completed") { stop(); root.mode = "idle" }
        }
    }

    IpcHandler {
        target: "fingerprint"
        function demo(): void { root.demo() }
        function refresh(): void { root.refresh() }
    }

    function say(m, bad) { message = m; messageBad = !!bad }

    function run(cmd, args) {
        mode = cmd === "list" ? "idle" : cmd.indexOf("delete") === 0 ? "delete" : cmd
        if (cmd !== "list") {   // a refresh after an action keeps showing its outcome
            target = args.length ? args[0] : ""
            result = ""
        }
        proc.command = ["python3", "-I", Quickshell.shellPath("fingerprint/fpctl.py"), cmd].concat(args)
        proc.running = true
    }

    readonly property var enrollText: ({
        "enroll-stage-passed": "Got it. Lift, then press again, shifting the finger a little.",
        "enroll-retry-scan": "Didn't catch that, press again.",
        "enroll-swipe-too-short": "Too quick, press a bit longer.",
        "enroll-finger-not-centered": "Centre your finger on the reader.",
        "enroll-remove-and-retry": "Lift your finger and try again.",
        "enroll-completed": "Enrolled. It works on the lock screen now.",
        "enroll-duplicate": "The reader already has this finger, maybe for another user (doas fprintd-delete root).",
        "enroll-data-full": "The reader is full. Delete a fingerprint first.",
        "enroll-disconnected": "The reader disconnected.",
        "enroll-failed": "Enrolling failed. Try again.",
        "enroll-unknown-error": "The reader hit an error. Try again."
    })
    readonly property var verifyText: ({
        "verify-match": "Match.",
        "verify-no-match": "No match.",
        "verify-retry-scan": "Didn't catch that, press again.",
        "verify-swipe-too-short": "Too quick, press a bit longer.",
        "verify-finger-not-centered": "Centre your finger on the reader.",
        "verify-remove-and-retry": "Lift your finger and try again.",
        "verify-disconnected": "The reader disconnected.",
        "verify-unknown-error": "The reader hit an error. Try again."
    })
    readonly property var errorText: ({
        "PermissionDenied": "Authentication cancelled.",
        "AlreadyInUse": "The reader is busy (another app is using it).",
        "NoEnrolledPrints": "No fingerprints enrolled yet.",
        "NoSuchDevice": "No fingerprint reader found.",
        "PrintsNotDeleted": "Couldn't delete that fingerprint."
    })

    function handle(o) {
        if (o.ev === "list") {
            loaded = true
            available = true
            deviceName = o.name
            stages = o.stages
            fingers = o.fingers
        } else if (o.ev === "start") {
            if (o.stages) stages = o.stages
            if (mode === "enroll") say("Press your " + label(target).toLowerCase() + " on the reader.", false)
        } else if (o.ev === "enroll") {
            if (o.result === "enroll-stage-passed") { stage++; scan("ok") }
            else if (o.result === "enroll-completed") { stage = stages; result = "done"; scan("match") }
            else if (o.done) { result = "failed"; scan("nomatch") }
            else scan("retry")
            say(enrollText[o.result] || o.result, o.done && o.result !== "enroll-completed"
                || o.result.indexOf("retry") >= 0 || o.result.indexOf("short") >= 0 || o.result.indexOf("centered") >= 0)
        } else if (o.ev === "verify") {
            if (o.result === "verify-match") { result = "match"; scan("match") }
            else if (o.done) { result = "nomatch"; scan("nomatch") }
            else scan("retry")
            say(verifyText[o.result] || o.result, o.result !== "verify-match")
        } else if (o.ev === "deleted") {
            say(o.finger === "all" ? "Deleted every fingerprint." : label(o.finger) + " deleted.", false)
        } else if (o.ev === "error") {
            if (o.stage === "device") { loaded = true; available = false }
            if (mode !== "idle" || o.stage !== "list") say(errorText[o.name] || o.msg, true)
            if (mode === "enroll") { result = "failed"; scan("nomatch") }
        }
    }

    Process {
        id: proc
        stdout: SplitParser {
            onRead: line => {
                try { root.handle(JSON.parse(line)) } catch (e) {}
            }
        }
        onExited: (code, status) => {
            const was = root.mode
            if (was === "enroll" && root.result === "") {
                root.say("Enrolling cancelled.", false)
                root.stage = 0
            }
            root.mode = "idle"
            if (was !== "idle") root.run("list", [])
        }
    }

    Component.onCompleted: refresh()
}
