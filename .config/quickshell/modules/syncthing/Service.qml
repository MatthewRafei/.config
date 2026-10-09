import Quickshell
import Quickshell.Io
import QtQuick
import qs

// Syncthing module: state for the bar chip from its local REST API,
// asked straight from QML (XMLHttpRequest) so a poll forks nothing; a
// one-off shell finds the binary and the API key. Started and stopped through the user's service manager
// (dinit, OpenRC user services), or run directly when it has none.
//
//   qs ipc call syncthing open | start | stop | status
Scope {
    id: root

    readonly property string url: "http://127.0.0.1:8384/"
    property bool installed: false       // the chip only shows when Syncthing is installed
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

    // API key and address from Syncthing's config.xml
    property string _key: ""
    property string _base: ""
    property int _pending: 0              // requests of the current poll still out
    property int _gen: 0                  // poll number; late answers from an older poll are dropped
    property real _pollStart: 0

    function refresh() {
        if (!root._key) { if (!cfg.running) cfg.running = true; return }
        // a poll still waiting after 10 s (Syncthing hung): give up on it
        if (root._pending > 0 && Date.now() - root._pollStart < 10000) return
        poll()
    }

    function _get(path, done) {
        const gen = root._gen
        const x = new XMLHttpRequest()
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE || gen !== root._gen) return
            // a rejected key: the config was regenerated, read it again
            if (x.status === 401 || x.status === 403) root._key = ""
            let d = null
            if (x.status === 200) try { d = JSON.parse(x.responseText) } catch (e) {}
            done(d)
        }
        x.open("GET", root._base + "/rest/" + path)
        x.setRequestHeader("X-API-Key", root._key)
        x.send()
    }

    function poll() {
        root._gen++
        root._pollStart = Date.now()
        const r = {}
        let failed = false
        const need = ["system/status", "config/folders", "config/devices", "system/connections",
                      "db/completion", "system/error"]
        root._pending = need.length
        const finish = () => {
            if (--root._pending > 0) return
            if (failed) { root._down(); return }
            const states = {}
            const folders = r["config/folders"]
            if (!folders.length) { root._apply(r, states); return }
            root._pending = folders.length
            for (const f of folders)
                root._get("db/status?folder=" + encodeURIComponent(f.id), d => {
                    if (d) states[f.id] = { state: d.state, errors: (d.errors || 0) + (d.pullErrors || 0) }
                    if (--root._pending === 0) root._apply(r, states)
                })
        }
        for (const path of need)
            root._get(path, d => {
                if (d === null) failed = true
                r[path] = d
                finish()
            })
    }

    function _down() {
        root.running = false
        root.folders = []; root.devices = []; root.errors = 0
    }

    function _apply(r, states) {
        const me = r["system/status"].myID
        const conns = r["system/connections"].connections || {}
        root.running = true
        root.completion = r["db/completion"].completion
        root.folders = (r["config/folders"] || []).map(f => ({
            id: f.id, label: f.label || f.id, paused: f.paused,
            state: (states[f.id] || {}).state, errors: (states[f.id] || {}).errors || 0 }))
        root.devices = (r["config/devices"] || []).filter(d => d.deviceID !== me).map(d => ({
            name: d.name, paused: d.paused, connected: !!(conns[d.deviceID] && conns[d.deviceID].connected) }))
        root.errors = (r["system/error"].errors || []).length
        root.busy = false
        if (root.openWhenUp) { root.openWhenUp = false; root.open() }
    }

    function open() {
        if (running) Quickshell.execDetached(["xdg-open", url])
        else { openWhenUp = true; start() }
    }
    function start() {
        act(["sh", "-c", "dinitctl --user start syncthing 2>/dev/null || rc-service --user syncthing start 2>/dev/null"
             + " || setsid -f syncthing serve --no-browser >/dev/null 2>&1"])
    }
    function stop() {
        act(["sh", "-c", "dinitctl --user stop syncthing 2>/dev/null || rc-service --user syncthing stop 2>/dev/null"
             + " || pkill -x syncthing"])
    }
    function toggle() { running ? stop() : start() }

    function act(cmd) {
        if (action.running) return
        busy = true
        action.command = cmd
        action.running = true
    }

    Timer {
        interval: !root.installed || !root._key ? 60000 : root.busy || root.syncing ? 1500 : 6000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: cfg
        command: ["sh", "-c",
            "command -v syncthing >/dev/null 2>&1 || { echo none; exit 0; }; " +
            "conf=\"${XDG_STATE_HOME:-$HOME/.local/state}/syncthing/config.xml\"; " +
            "[ -f \"$conf\" ] || conf=\"$HOME/.config/syncthing/config.xml\"; " +
            "sed -n 's:.*<apikey>\\(.*\\)</apikey>.*:key \\1:p' \"$conf\" 2>/dev/null | head -n 1; " +
            "sed -n '/<gui /,/<\\/gui>/s:.*<address>\\(.*\\)</address>.*:gui \\1:p' \"$conf\" 2>/dev/null | head -n 1"]
        stdout: StdioCollector {
            onStreamFinished: {
                let key = "", gui = ""
                for (const l of text.split("\n")) {
                    if (l.startsWith("key ")) key = l.slice(4).trim()
                    else if (l.startsWith("gui ")) gui = l.slice(4).trim()
                }
                root.installed = text.trim() !== "none"
                root._base = "http://" + (gui || "127.0.0.1:8384")
                root._key = key
                if (key) root.poll()
                else root._down()
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
