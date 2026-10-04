pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

// The one place that knows which compositor is running (niri or Hyprland).
// Everything else reads workspaces / the focused window from here and calls
// the action functions below, so it works the same on both.
//
// Workspaces are in niri's shape for both:
//   { idx, output, is_active, is_urgent, active_window_id }
// For Hyprland, idx is the workspace id and is_active means "shown on its
// monitor". Any compositor event triggers a debounced re-query, which is
// simpler and more robust than tracking every event type by hand.
Singleton {
    id: comp

    readonly property bool hyprland: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") !== null
    readonly property bool niri: !hyprland && Quickshell.env("NIRI_SOCKET") !== null
    readonly property string name: hyprland ? "hyprland" : niri ? "niri" : ""

    property var workspaces: []
    property string windowTitle: ""
    property string windowApp: ""

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
            onRead: debounce.restart()
        }
        // niri restarted / socket dropped: reconnect
        onRunningChanged: if (!running && comp.niri) niriRetry.start()
    }

    Timer {
        id: niriRetry
        interval: 2000
        onTriggered: niriEvents.running = true
    }

    // the Hyprland singleton connects on first use, so only touch it there
    Connections {
        target: comp.hyprland ? Hyprland : null
        function onRawEvent(event) { debounce.restart() }
    }

    Timer {
        id: debounce
        interval: 40
        onTriggered: if (!query.running) query.running = true
    }

    Component.onCompleted: if (hyprland) query.running = true

    Process {
        id: query
        command: comp.hyprland
            ? ["sh", "-c", "hyprctl -j workspaces; echo @@; hyprctl -j monitors; echo @@; hyprctl -j activewindow"]
            : ["sh", "-c", "niri msg --json workspaces; echo; niri msg --json focused-window"]
        stdout: StdioCollector {
            onStreamFinished: comp.hyprland ? comp.parseHyprland(text) : comp.parseNiri(text)
        }
    }

    function parseNiri(text) {
        var parts = text.split("\n").filter(function (l) { return l.trim() !== "" })
        try {
            var ws = JSON.parse(parts[0])
            ws.sort(function (a, b) { return a.idx - b.idx })
            comp.workspaces = ws
        } catch (e) {}
        try {
            var win = JSON.parse(parts[1] || "null")
            comp.windowTitle = win ? (win.title || "") : ""
            comp.windowApp = win ? (win.app_id || "") : ""
        } catch (e) {
            comp.windowTitle = ""
            comp.windowApp = ""
        }
    }

    function parseHyprland(text) {
        var parts = text.split("\n@@\n")   // hyprctl pretty-prints over many lines
        try {
            var ws = JSON.parse(parts[0])
            var mons = JSON.parse(parts[1])
            var shown = {}
            for (var i = 0; i < mons.length; i++)
                shown[mons[i].activeWorkspace.id] = true
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
