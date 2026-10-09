import Quickshell
import Quickshell.Io
import QtQuick
import qs

// Tailscale state for the bar chip and the VPN dropdown (QuickPanel.qml).
// Polls `tailscale status --json`; faster while the dropdown is open.
//
// Changing state (up / down / exit node) needs the user to be Tailscale's
// operator, once: doas tailscale set --operator=$USER
Scope {
    id: root

    property bool installed: false       // tailscale CLI found and daemon answered
    property string state: ""            // Running, Stopped, NeedsLogin, Starting, ...
    readonly property bool running: state === "Running"
    property string selfName: ""
    property string selfIp: ""
    property string tailnet: ""
    property string exitNode: ""         // host name of the exit node in use, "" = none
    property var peers: []               // [{ name, ip, os, online, exitOption, exit }]
    readonly property int onlineCount: peers.filter(p => p.online).length
    property string busy: ""             // what we're waiting for: "up", "down", "exit"
    property string error: ""
    property bool fast: false            // the dropdown is open

    function refresh() { if (!status.running) status.running = true }

    function up()   { act("up", ["tailscale", "up"]) }
    function down() { act("down", ["tailscale", "down"]) }
    function toggle() { running ? down() : up() }
    // ip of a peer, or "" for no exit node
    function useExit(ip) { act("exit", ["tailscale", "set", "--exit-node=" + ip]) }
    function copy(text) { Quickshell.execDetached(["wl-copy", text]) }

    function act(what, cmd) {
        if (action.running) return
        busy = what
        error = ""
        action.command = cmd
        action.running = true
    }

    Timer {
        interval: root.fast ? 2000 : 8000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: status
        command: ["tailscale", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(text) } catch (e) {}
                if (!d) { root.installed = false; root.state = ""; return }
                root.installed = true
                root.state = d.BackendState || ""
                const self = d.Self || {}
                root.selfName = self.HostName || ""
                root.selfIp = (self.TailscaleIPs || [])[0] || ""
                root.tailnet = (d.CurrentTailnet || {}).Name || ""
                const list = []
                let exit = ""
                for (const k in (d.Peer || {})) {
                    const p = d.Peer[k]
                    const name = p.HostName || (p.DNSName || "").split(".")[0]
                    if (p.ExitNode) exit = name
                    list.push({ name: name, ip: (p.TailscaleIPs || [])[0] || "", os: p.OS || "",
                                online: !!p.Online, exitOption: !!p.ExitNodeOption, exit: !!p.ExitNode })
                }
                // online first, then by name
                list.sort((a, b) => (b.online - a.online) || a.name.localeCompare(b.name))
                root.peers = list
                root.exitNode = exit
            }
        }
        // not installed / daemon not running
        onExited: code => { if (code !== 0 && root.state === "") root.installed = false }
    }

    Process {
        id: action
        stderr: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                if (t === "") return
                root.error = t.indexOf("operator") >= 0 || t.indexOf("Access denied") >= 0
                    ? "Not allowed yet. Run once:  doas tailscale set --operator=$USER"
                    : t.split("\n")[0]
            }
        }
        onExited: {
            root.busy = ""
            root.refresh()
        }
    }
}
