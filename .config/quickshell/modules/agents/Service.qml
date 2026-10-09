import Quickshell
import Quickshell.Io
import QtQuick

// Claude Code sessions, for the bar's agents chip and its dropdown
// (QuickPanel.qml, "agents"). Sessions started from here run in a private
// tmux server (tmux.conf), so closing their terminal only detaches
// them: Claude keeps working, and the dropdown opens it again. Sessions
// started in a plain terminal are listed too (they end with their terminal).
//
// State comes from agents.py, which reads Claude Code's own session
// files: no hooks, nothing to set up.
//
//   qs ipc call agents panel      open the dropdown
//   qs ipc call agents next       open the session that needs you (or the newest)
//   qs ipc call agents start DIR  start a kept session in DIR
Scope {
    id: root

    property bool available: false        // claude is installed
    property string claudeBin: ""
    property var sessions: []             // agents.py scan
    property var recent: []               // agents.py recent (while the dropdown is open)
    property var projects: []             // folders Claude knows (~/.claude.json)
    property bool fast: false             // the dropdown is open: poll faster

    readonly property var waiting: sessions.filter(s => s.status === "waiting")
    readonly property var busy: sessions.filter(s => s.status === "busy")
    readonly property var idle: sessions.filter(s => s.status !== "waiting" && s.status !== "busy")

    readonly property string script: Quickshell.shellPath("modules/agents.py")
    readonly property string conf: Quickshell.shellPath("modules/tmux.conf")
    readonly property string terminal: Quickshell.env("TERMINAL") || "alacritty"
    readonly property string home: Quickshell.env("HOME")

    function tmux(args) { return ["tmux", "-L", "claude", "-f", conf].concat(args) }

    // "~/Development/x"
    function pretty(dir) { return dir.indexOf(home) === 0 ? "~" + dir.slice(home.length) : dir }

    // "3m", "2h", "4d"
    function ago(ms) {
        const s = Math.max(0, (Date.now() - ms) / 1000)
        return s < 60 ? Math.floor(s) + "s" : s < 3600 ? Math.floor(s / 60) + "m"
             : s < 86400 ? Math.floor(s / 3600) + "h" : Math.floor(s / 86400) + "d"
    }

    // start a kept session in `dir` (resuming conversation `sid` when given) and open it
    function newSession(dir, sid) {
        if (!available) return
        const base = (dir.split("/").filter(x => x).pop() || "home").replace(/[^A-Za-z0-9_-]/g, "").slice(0, 20) || "claude"
        const name = "cc-" + base + "-" + (Date.now() % 46656).toString(36)
        const cmd = "exec " + JSON.stringify(claudeBin) + (sid && /^[0-9a-f-]{36}$/.test(sid) ? " --resume " + sid : "")
        // started detached, then a terminal attaches; closing it leaves claude running
        Quickshell.execDetached(["sh", "-c", 't=$1; n=$2; shift 2; "$@" && exec "$t" -e tmux -L claude attach -t "$n"',
            "sh", terminal, name].concat(tmux(["new-session", "-d", "-s", name, "-c", dir, cmd])))
        scanSoon.restart()
    }

    // bring a session up: its terminal if it has one, else a new terminal on the kept session
    function open(s) {
        if (s.tmux !== "") {
            // detached, so a shell restart never takes the terminal with it
            Quickshell.execDetached(["sh", "-c",
                'python3 -I "$1" attached "$2" || exec "$3" -e tmux -L claude attach -t "$2"',
                "sh", script, s.tmux, terminal])
        } else if (s.pid > 0) {
            Quickshell.execDetached(["python3", "-I", script, "focus", String(s.pid)])
        }
    }

    // end a kept session (claude and all)
    function stop(s) {
        if (s.tmux === "") return
        Quickshell.execDetached(tmux(["kill-session", "-t", s.tmux]))
        scanSoon.restart()
    }

    // the one that needs you: waiting longest, else the latest to finish
    function next() {
        const pick = waiting.slice().sort((a, b) => a.since - b.since)[0]
            || idle.slice().sort((a, b) => b.since - a.since)[0]
        if (pick) open(pick)
    }

    function refresh() {
        if (!scan.running) scan.running = true
    }
    function refreshMore() {
        refresh()
        if (!recentProc.running) recentProc.running = true
        projectsFile.reload()
    }

    IpcHandler {
        target: "agents"
        function panel(): void { Quickshell.execDetached(["qs", "ipc", "call", "quick", "agents"]) }
        function next(): void { root.next() }
        function start(dir: string): void { root.newSession(dir || root.home, "") }
    }

    Process {
        running: true
        command: ["sh", "-c", "command -v claude"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.claudeBin = text.trim()
                root.available = root.claudeBin !== ""
                if (root.available) root.refresh()
            }
        }
    }

    Timer {
        interval: root.fast ? 1500 : 4000
        repeat: true
        running: root.available
        onTriggered: root.refresh()
    }
    Timer { id: scanSoon; interval: 800; onTriggered: root.refresh() }

    Process {
        id: scan
        command: ["python3", "-I", root.script, "scan"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.sessions = JSON.parse(text) } catch (e) {}
            }
        }
    }

    Process {
        id: recentProc
        command: ["python3", "-I", root.script, "recent"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.recent = JSON.parse(text) } catch (e) {}
            }
        }
    }

    // folders Claude has been used in, newest config first
    FileView {
        id: projectsFile
        path: root.home + "/.claude.json"
        onLoaded: {
            try {
                const p = Object.keys(JSON.parse(text()).projects || {})
                root.projects = p.filter(d => d !== root.home).sort()
            } catch (e) {}
        }
    }
}
