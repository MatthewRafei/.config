pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Caffeine: keep the machine awake. While on, the bar holds a Wayland idle
// inhibitor (Bar.qml), so the screensaver and the idle lock don't start, and
// an elogind "idle" lock, so no idle action (auto suspend) runs either.
// Closing the lid or picking Suspend still suspends.
//
//   qs ipc call caffeine toggle | on | off
Singleton {
    id: root

    property bool on: false

    function toggle() { on = !on }

    Process {
        // held until caffeine is turned off or the shell goes away
        command: ["sh", "-c", "exec elogind-inhibit --what=idle --who=quickshell --why=caffeine "
                  + "--mode=block sh -c 'while kill -0 \"$1\" 2>/dev/null; do sleep 5; done' sh \"$PPID\""]
        running: root.on
    }

    IpcHandler {
        target: "caffeine"
        function toggle(): void { root.toggle() }
        function on(): void { root.on = true }
        function off(): void { root.on = false }
        function status(): string { return root.on ? "on" : "off" }
    }
}
