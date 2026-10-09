pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Internet speed test for Settings > Network (netspeed/speedtest.py, curl
// against speed.cloudflare.com). Only runs when asked: it moves a few hundred
// MB. The last result is kept in ~/.cache/quickshell/speedtest.json, so the
// page shows it until the next test.
//
//   qs ipc call speedtest run
Singleton {
    id: root

    property real down: -1          // bits/s, -1 = not measured
    property real up: -1
    property real ping: -1          // ms
    property real at: 0             // unix seconds of the last complete test
    property string phase: ""       // "", "ping", "down", "up" while running
    property string error: ""
    readonly property bool running: proc.running

    readonly property string script: Quickshell.shellPath("netspeed/speedtest.py")

    // "463 Mb/s", "1.2 Gb/s"
    function mbps(bits) {
        if (!(bits >= 0)) return "--"
        const m = bits / 1e6
        return m >= 1000 ? (m / 1000).toFixed(2) + " Gb/s" : m >= 100 ? Math.round(m) + " Mb/s" : m.toFixed(1) + " Mb/s"
    }
    function ago() {
        if (!at) return "never"
        const s = Math.max(0, Date.now() / 1000 - at)
        return s < 60 ? "just now" : s < 3600 ? Math.floor(s / 60) + " min ago"
             : s < 86400 ? Math.floor(s / 3600) + " h ago" : Math.floor(s / 86400) + " d ago"
    }

    function run() {
        if (proc.running) return
        error = ""
        down = -1; up = -1; ping = -1
        phase = "ping"
        proc.running = true
    }

    Process {
        id: proc
        command: ["python3", "-I", root.script]
        stdout: SplitParser {
            onRead: line => {
                let d
                try { d = JSON.parse(line) } catch (e) { return }
                if (d.error) root.error = d.error
                if (d.ping !== undefined) { root.ping = d.ping; root.phase = "down" }
                if (d.down !== undefined) { root.down = d.down === null ? -1 : d.down; root.phase = "up" }
                if (d.up !== undefined) root.up = d.up === null ? -1 : d.up
                if (d.done) {
                    root.at = d.at
                    cache.setText(JSON.stringify({ down: root.down, up: root.up, ping: root.ping, at: root.at }))
                }
            }
        }
        onExited: code => {
            root.phase = ""
            if (code !== 0 && root.error === "") root.error = "Speed test failed"
        }
    }

    IpcHandler {
        target: "speedtest"
        function run(): void { root.run() }
    }

    FileView {
        id: cache
        path: Quickshell.env("HOME") + "/.cache/quickshell/speedtest.json"
        onLoaded: {
            try {
                const d = JSON.parse(text())
                root.down = d.down; root.up = d.up; root.ping = d.ping; root.at = d.at
            } catch (e) {}
        }
    }
}
