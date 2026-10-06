import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import QtQuick

// Lock screen (ext-session-lock, so niri keeps the session locked even if
// this process dies) with PAM password auth via pam/password.conf, and
// fingerprint auth (fprintd) via pam/fingerprint.conf running alongside it.
//
//   qs ipc call lock lock       lock now (bound to Mod+Shift+L in niri)
//   qs ipc call lock preview    show the UI in a normal window (Esc closes)
//
// Locks automatically after 5 minutes idle (screensaver at 3); apps that inhibit idle (video
// players, games) prevent that. Also locks before suspend (lid close etc.).
//
// There is deliberately no IPC to unlock: only the password or a finger does that.
Scope {
    id: root

    property bool locked: false
    property bool previewing: false

    property string password: ""
    property string status: "idle"   // idle | checking | failed | error
    property string errorText: ""
    property int failures: 0
    property string fingerStatus: "off"   // off | waiting | failed

    // retries after a scan that didn't match; stops after a few quick
    // give-ups in a row (no reader / nothing enrolled) until the next lock
    property int fingerGiveUps: 0

    signal shake()

    function lock() {
        password = ""
        status = "idle"
        previewing = false
        fingerGiveUps = 0
        locked = true
        fingerRetry.restart()
    }

    function unlocked() {
        root.status = "idle"
        root.failures = 0
        root.fingerStatus = "off"
        fingerRetry.stop()
        if (finger.active) finger.abort()
        root.locked = false
    }

    function tryUnlock() {
        if (password === "" || pam.active)
            return
        status = "checking"
        pam.start()
    }

    PamContext {
        id: pam
        configDirectory: Quickshell.shellPath("pam")
        config: "password.conf"

        onPamMessage: {
            if (responseRequired)
                respond(root.password)
        }

        onCompleted: result => {
            root.password = ""
            if (result === PamResult.Success) {
                root.unlocked()
            } else {
                root.status = "failed"
                root.failures++
                root.shake()
            }
        }

        onError: err => {
            root.password = ""
            root.status = "error"
            root.errorText = PamError.toString(err)
            root.shake()
        }
    }

    PamContext {
        id: finger
        configDirectory: Quickshell.shellPath("pam")
        config: "fingerprint.conf"
        property double startedAt: 0

        onActiveChanged: if (active) { startedAt = Date.now(); root.fingerStatus = "waiting" }

        onCompleted: result => {
            if (result === PamResult.Success) {
                root.unlocked()
                Fingerprint.event("unlock", "")   // the bar does a little skit
                return
            }
            if (!root.locked) return
            // ended within a couple of seconds = no reader or no enrolled finger
            if (Date.now() - startedAt < 2000) root.fingerGiveUps++
            else root.fingerGiveUps = 0
            if (result === PamResult.Failed) { root.fingerStatus = "failed"; root.shake() }
            else root.fingerStatus = "off"
            fingerRetry.restart()
        }

        onError: err => {
            root.fingerGiveUps++
            root.fingerStatus = "off"
            if (root.locked) fingerRetry.restart()
        }
    }

    Timer {
        id: fingerRetry
        interval: 1500
        onTriggered: {
            if (root.locked && !finger.active && root.fingerGiveUps < 3)
                finger.start()
            else if (root.fingerGiveUps >= 3)
                root.fingerStatus = "off"
        }
    }

    WlSessionLock {
        id: sessionLock
        locked: root.locked

        WlSessionLockSurface {
            color: "black"
            LockSurface {
                anchors.fill: parent
                lock: root
            }
        }
    }

    // Preview: same UI, ordinary overlay window, never authenticates.
    LazyLoader {
        active: root.previewing

        PanelWindow {
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell-lock-preview"
            color: "black"

            LockSurface {
                anchors.fill: parent
                lock: root
                preview: true
                onClosePreview: root.previewing = false
            }
        }
    }

    IpcHandler {
        target: "lock"
        function lock(): void { root.lock() }
        function preview(): void { root.previewing = !root.previewing }
        function isLocked(): bool { return root.locked }
    }

    // ---------------- lock before suspend ----------------
    // Hold an elogind "delay" sleep inhibitor. When PrepareForSleep(true)
    // arrives, lock, wait until niri confirms the lock is on screen, then
    // release the inhibitor so the machine can sleep. Re-acquire on resume.
    property bool sleepPending: false
    property bool sleeping: false

    function releaseForSleep() {
        if (!sleepPending) return
        sleepPending = false
        sleeping = true
    }

    Process {
        running: !root.sleeping
        // the lock's "process" exits with the shell (checked every 5 s), so a
        // restarted shell doesn't leave old delay locks behind
        command: ["sh", "-c", "exec elogind-inhibit --what=sleep --mode=delay --who=quickshell "
                  + "--why='Lock the screen before sleeping' sh -c 'while kill -0 \"$1\" 2>/dev/null; do sleep 5; done' sh \"$PPID\""]
    }

    Process {
        id: sleepWatch
        property bool armed: false
        running: true
        command: ["dbus-monitor", "--system",
                  "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"]
        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf("member=PrepareForSleep") >= 0) {
                    sleepWatch.armed = true
                } else if (sleepWatch.armed) {
                    sleepWatch.armed = false
                    if (line.indexOf("boolean true") >= 0) {
                        root.sleepPending = true
                        if (root.locked && sessionLock.secure) root.releaseForSleep()
                        else { root.lock(); sleepFallback.restart() }
                    } else if (line.indexOf("boolean false") >= 0) {
                        root.sleepPending = false
                        root.sleeping = false
                    }
                }
            }
        }
        onRunningChanged: if (!running) watchRetry.start()
    }

    Timer { id: watchRetry; interval: 3000; onTriggered: sleepWatch.running = true }

    // never hold up suspend for long, even if the lock is slow to appear
    Timer { id: sleepFallback; interval: 1500; onTriggered: root.releaseForSleep() }

    Connections {
        target: sessionLock
        function onSecureStateChanged() {
            if (sessionLock.secure) root.releaseForSleep()
        }
    }

    // lock after Idle.lockMin idle minutes (Settings > Screensaver), 0 = never
    IdleMonitor {
        enabled: Idle.lockMin > 0
        timeout: Math.max(1, Idle.lockMin) * 60
        respectInhibitors: true
        onIsIdleChanged: if (enabled && isIdle && !root.locked) root.lock()
    }
}
