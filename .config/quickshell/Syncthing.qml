pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Syncthing state for the bar chip, from its local REST API
// (syncthing/status.sh). Started and stopped through the dinit user service.
//
//   qs ipc call syncthing open | start | stop | status
Singleton {
    id: root

    readonly property string url: "http://127.0.0.1:8384/"
    property bool running: false
    property real completion: 100        // local completion over all folders, %
    property var folders: []             // [{ id, label, state, paused, errors }]
    property var devices: []             // [{ name, connected, paused }], not this machine
    property int errors: 0               // Syncthing's own error list
    property bool busy: false            // starting / stopping
    property bool openWhenUp: false      // open the web UI once it answers

    readonly property int connected: devices.filter(d => d.connected).length
    readonly property bool syncing: folders.some(f => f.state === "syncing" || f.state === "sync-preparing")
    readonly property bool scanning: folders.some(f => f.state === "scanning")
    readonly property int folderErrors: folders.reduce((n, f) => n + (f.errors || 0) + (f.state === "error" ? 1 : 0), 0)
    readonly property bool failing: errors > 0 || folderErrors > 0

    function refresh() { if (!status.running) status.running = true }

    function open() {
        if (running) Quickshell.execDetached(["xdg-open", url])
        else { openWhenUp = true; start() }
    }
    function start() { act(["dinitctl", "--user", "start", "syncthing"]) }
    function stop() { act(["dinitctl", "--user", "stop", "syncthing"]) }
    function toggle() { running ? stop() : start() }

    function act(cmd) {
        if (action.running) return
        busy = true
        action.command = cmd
        action.running = true
    }

    Timer {
        interval: root.busy || root.syncing ? 1500 : 6000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: status
        command: ["sh", Quickshell.shellDir + "/syncthing/status.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(text) } catch (e) {}
                root.running = !!(d && d.running)
                if (!root.running) { root.folders = []; root.devices = []; root.errors = 0; return }
                root.completion = d.completion
                root.folders = d.folders || []
                root.devices = d.devices || []
                root.errors = d.errors || 0
                root.busy = false
                if (root.openWhenUp) { root.openWhenUp = false; root.open() }
            }
        }
    }

    Process {
        id: action
        // syncthing takes a moment to answer after the service starts
        onExited: { settle.restart(); root.refresh() }
    }
    Timer { id: settle; interval: 8000; onTriggered: root.busy = false }

    IpcHandler {
        target: "syncthing"
        function open(): void { root.open() }
        function start(): void { root.start() }
        function stop(): void { root.stop() }
        function status(): string {
            return !root.running ? "stopped"
                : (root.failing ? "errors" : root.syncing ? "syncing " + Math.floor(root.completion) + "%" : "idle")
                  + ", " + root.connected + "/" + root.devices.length + " devices"
        }
    }
}
