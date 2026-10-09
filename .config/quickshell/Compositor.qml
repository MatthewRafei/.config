pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// The one place that knows which compositor is running (niri or Hyprland).
// Everything else reads workspaces / the focused window from here and calls
// the action functions below, so it works the same on both.
//
// Workspaces are in niri's shape for both:
//   { idx, output, is_active, is_urgent, active_window_id }
// For Hyprland, idx is the workspace id and is_active means "shown on its
// monitor". niri's event stream carries the full state on connect and
// deltas after, so it is applied as it comes (re-querying spawned two
// `niri msg` per event, and a terminal's spinner title fires one a second).
// Hyprland events trigger a debounced re-query.
Singleton {
    id: comp

    readonly property bool hyprland: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") !== null
    readonly property bool niri: !hyprland && Quickshell.env("NIRI_SOCKET") !== null
    readonly property string name: hyprland ? "hyprland" : niri ? "niri" : ""

    property var workspaces: []
    property string windowTitle: ""
    property string windowApp: ""
    property string focusedOutput: ""   // name of the focused monitor, e.g. "DP-1"

    // -------------------------
    // actions
    // -------------------------
    function niriAction(args) {
        Quickshell.execDetached(["niri", "msg", "action"].concat(args))
    }

    // Hyprland's Lua config takes Lua for dispatch: hl.dsp.focus({ ... })
    function hyprDispatch(lua) {
        Quickshell.execDetached(["hyprctl", "dispatch", lua])
    }

    function focusWorkspace(idx) {
        if (hyprland) hyprDispatch('hl.dsp.focus({ workspace = "' + idx + '" })')
        else niriAction(["focus-workspace", String(idx)])
    }

    // up = previous workspace on this monitor
    function workspaceUp() {
        if (hyprland) hyprDispatch('hl.dsp.focus({ workspace = "m-1" })')
        else niriAction(["focus-workspace-up"])
    }

    function workspaceDown() {
        if (hyprland) hyprDispatch('hl.dsp.focus({ workspace = "m+1" })')
        else niriAction(["focus-workspace-down"])
    }

    function quit() {
        if (hyprland) hyprDispatch("hl.dsp.exit()")
        else niriAction(["quit", "--skip-confirmation"])
    }

    // -------------------------
    // events
    // -------------------------
    Process {
        id: niriEvents
        command: ["niri", "msg", "--json", "event-stream"]
        running: comp.niri
        stdout: SplitParser {
            onRead: line => comp.niriEvent(line)
        }
        // niri restarted / socket dropped: reconnect
        onRunningChanged: if (!running && comp.niri) niriRetry.start()
    }

    Timer {
        id: niriRetry
        interval: 2000
        onTriggered: niriEvents.running = true
    }

    // Hyprland's event socket, read directly instead of through the
    // Quickshell.Hyprland module: some distro builds of Quickshell (Chimera's)
    // don't include it, and importing it would stop the whole shell loading.
    Process {
        id: hyprEvents
        command: ["python3", "-uc",
            "import os, socket\n" +
            "p = os.path.join(os.environ.get('XDG_RUNTIME_DIR', '/tmp'), 'hypr', os.environ['HYPRLAND_INSTANCE_SIGNATURE'], '.socket2.sock')\n" +
            "s = socket.socket(socket.AF_UNIX); s.connect(p)\n" +
            "for line in s.makefile(): print(line, end='')\n"]
        running: comp.hyprland
        stdout: SplitParser {
            onRead: debounce.restart()
        }
        onRunningChanged: if (!running && comp.hyprland) hyprRetry.start()
    }

    Timer {
        id: hyprRetry
        interval: 2000
        onTriggered: hyprEvents.running = true
    }

    Timer {
        id: debounce
        interval: 40
        onTriggered: if (!query.running) query.running = true
    }

    Component.onCompleted: if (hyprland) query.running = true

    Process {
        id: query
        command: ["sh", "-c", "hyprctl -j workspaces; echo @@; hyprctl -j monitors; echo @@; hyprctl -j activewindow"]
        stdout: StdioCollector {
            onStreamFinished: comp.parseHyprland(text)
        }
    }

    // niri state, from the event stream
    property var _nWs: []                  // workspaces as niri sends them
    property var _nWins: ({})              // window id -> window

    function niriEvent(line) {
        let ev
        try { ev = JSON.parse(line) } catch (e) { return }
        const k = Object.keys(ev)[0], d = ev[k]
        switch (k) {
        case "WorkspacesChanged":
            _nWs = d.workspaces
            _niriWorkspaces()
            break
        case "WorkspaceActivated": {
            const t = _nWs.find(w => w.id === d.id)
            if (!t) return
            for (const w of _nWs) {
                if (w.output === t.output) w.is_active = w.id === d.id
                if (d.focused) w.is_focused = w.id === d.id
            }
            _niriWorkspaces()
            break
        }
        case "WorkspaceActiveWindowChanged": {
            const t = _nWs.find(w => w.id === d.workspace_id)
            if (t) { t.active_window_id = d.active_window_id; _niriWorkspaces() }
            break
        }
        case "WorkspaceUrgencyChanged": {
            const t = _nWs.find(w => w.id === d.id)
            if (t) { t.is_urgent = d.urgent; _niriWorkspaces() }
            break
        }
        case "WindowsChanged": {
            const m = {}
            for (const w of d.windows) m[w.id] = w
            _nWins = m
            _niriWindow()
            break
        }
        case "WindowOpenedOrChanged":
            if (d.window.is_focused)
                for (const id in _nWins) _nWins[id].is_focused = false
            _nWins[d.window.id] = d.window
            _niriWindow()
            break
        case "WindowClosed":
            delete _nWins[d.id]
            _niriWindow()
            break
        case "WindowFocusChanged":
            for (const id in _nWins) _nWins[id].is_focused = +id === d.id
            _niriWindow()
            break
        }
    }

    function _niriWorkspaces() {
        const ws = _nWs.slice().sort((a, b) => a.idx - b.idx)
        comp.workspaces = ws
        const f = ws.find(w => w.is_focused)
        if (f) comp.focusedOutput = f.output || ""
    }

    function _niriWindow() {
        let win = null
        for (const id in _nWins) if (_nWins[id].is_focused) { win = _nWins[id]; break }
        comp.windowTitle = win ? (win.title || "") : ""
        comp.windowApp = win ? (win.app_id || "") : ""
    }

    function parseHyprland(text) {
        var parts = text.split("\n@@\n")   // hyprctl pretty-prints over many lines
        try {
            var ws = JSON.parse(parts[0])
            var mons = JSON.parse(parts[1])
            var shown = {}
            for (var i = 0; i < mons.length; i++) {
                shown[mons[i].activeWorkspace.id] = true
                if (mons[i].focused) comp.focusedOutput = mons[i].name
            }
            comp.workspaces = ws
                .filter(function (w) { return w.id > 0 })   // skip special workspaces
                .sort(function (a, b) { return a.id - b.id })
                .map(function (w) {
                    return {
                        idx: w.id,
                        output: w.monitor,
                        is_active: shown[w.id] === true,
                        is_urgent: false,
                        active_window_id: w.windows > 0 ? w.lastwindow : null
                    }
                })
        } catch (e) {}
        try {
            // no focused window: hyprctl prints "{}" or "Invalid"
            var win = JSON.parse(parts[2] || "{}")
            comp.windowTitle = win.title || ""
            comp.windowApp = win["class"] || ""
        } catch (e) {
            comp.windowTitle = ""
            comp.windowApp = ""
        }
    }
}
