import Quickshell
import Quickshell.Io
import QtQuick
import qs

// Disk space for Settings > Disks (SettingsPages/DiskSpace.qml), after
// mtolhuys/omarchy-disk-lens: what's using the space, as a treemap or a list.
// disklens.py scans (one filesystem, hardlinks once, allocated size)
// and returns the whole tree, so drilling in is instant. Nothing scans in the
// background; the last result is kept in ~/.cache/quickshell/disklens.json.
Scope {
    id: root

    readonly property string script: Quickshell.shellPath("modules/disks/disklens.py")

    property var mounts: []
    property var result: null         // { root, tree, files, dirs, errors, seconds, at }
    property var path: []             // names from the scan root to the folder on screen
    property bool scanning: false
    property var progress: null       // { files, dirs, bytes, at }
    property string scanTarget: ""
    property string error: ""

    // a folder's child by name (a loop: stored lists aren't always real JS arrays)
    function kid(n, name) {
        const c = n && n.c ? n.c : []
        for (let i = 0; i < c.length; i++) if (c[i].n === name) return c[i]
        return null
    }
    // the folder on screen
    readonly property var node: {
        if (!result) return null
        let n = result.tree
        for (let i = 0; i < path.length; i++) {
            const next = kid(n, path[i])
            if (!next) break
            n = next
        }
        return n
    }
    readonly property string nodePath: result ? (path.length ? result.root.replace(/\/$/, "") + "/" + path.join("/") : result.root) : ""

    function fmt(b) {
        if (!(b >= 0)) return "—"
        const u = ["B", "KB", "MB", "GB", "TB"]
        let i = 0
        while (b >= 1000 && i < u.length - 1) { b /= 1000; i++ }
        return (i === 0 ? Math.round(b) : b.toFixed(b < 10 ? 1 : b < 100 ? 1 : 0)) + " " + u[i]
    }

    function refreshMounts() { if (!mountProc.running) mountProc.running = true }
    function scan(target) {
        if (scanning) return
        error = ""
        progress = null
        scanTarget = target
        scanProc.command = ["python3", "-I", script, "scan", target]
        scanning = true
        scanProc.running = true
    }
    function cancel() { if (scanProc.running) scanProc.signal(15) }
    function enter(name) { path = path.concat([name]) }
    function up(levels) { path = path.slice(0, Math.max(0, path.length - (levels || 1))) }
    function goTo(depth) { path = path.slice(0, depth) }
    function open(p) { Quickshell.execDetached(["xdg-open", p]) }
    function childPath(name) { return nodePath.replace(/\/$/, "") + "/" + name }

    // trash one entry, then take it out of the tree (no rescan)
    property var _trashing: null
    function trash(name) {
        if (trashProc.running || !node) return
        _trashing = { path: path.slice(), name: name }
        trashProc.command = ["python3", "-I", script, "trash", childPath(name)]
        trashProc.running = true
    }
    function _removeTrashed() {
        const t = _trashing
        const chain = [result.tree]
        for (let i = 0; i < t.path.length; i++) chain.push(kid(chain[chain.length - 1], t.path[i]))
        const parent = chain[chain.length - 1]
        const gone = kid(parent, t.name)
        if (!parent || !gone) return
        const rest = []
        for (let i = 0; i < parent.c.length; i++) if (parent.c[i].n !== t.name) rest.push(parent.c[i])
        parent.c = rest
        for (let i = 0; i < chain.length; i++) chain[i].s -= gone.s
        result = Object.assign({}, result)      // let bindings see the change
        save()
    }
    function save() { cache.setText(JSON.stringify(result)) }

    Process {
        id: mountProc
        command: ["python3", "-I", root.script, "mounts"]
        running: true
        stdout: StdioCollector { onStreamFinished: { try { root.mounts = JSON.parse(text) } catch (e) {} } }
    }

    Process {
        id: scanProc
        stdout: StdioCollector { id: scanOut }
        stderr: SplitParser {
            onRead: line => { try { root.progress = JSON.parse(line) } catch (e) {} }
        }
        onExited: code => {
            root.scanning = false
            if (code !== 0) {
                // cancelled (keep the previous result) or failed
                if (code !== 143 && code !== -1) {
                    try { root.error = JSON.parse(scanOut.text).error } catch (e) { root.error = "The scan failed" }
                }
                return
            }
            // the output can land after the exit: read it when it's complete
            root._pendingResult = true
            Qt.callLater(root._takeResult)
        }
    }
    property bool _pendingResult: false
    function _takeResult() {
        if (!_pendingResult) return
        try {
            const r = JSON.parse(scanOut.text)
            _pendingResult = false
            result = r
            path = []
            save()
        } catch (e) {
            retry.restart()
        }
    }
    Timer { id: retry; interval: 150; onTriggered: root._takeResult() }

    Process {
        id: trashProc
        stdout: StdioCollector { id: trashOut }
        onExited: code => {
            if (code === 0) root._removeTrashed()
            else { try { root.error = JSON.parse(trashOut.text).error } catch (e) { root.error = "Couldn't move it to the Trash" } }
            root._trashing = null
            root.refreshMounts()
        }
    }

    // qs ipc call disklens scan ~/Downloads   (opens Settings > Disks too)
    IpcHandler {
        target: "disklens"
        function scan(target: string): void {
            root.scan(target || Quickshell.env("HOME"))
            Quickshell.execDetached(["qs", "ipc", "call", "settings", "page", "Disks"])
        }
        function cancel(): void { root.cancel() }
    }

    FileView {
        id: cache
        path: Quickshell.env("HOME") + "/.cache/quickshell/disklens.json"
        onLoaded: { try { if (!root.result) root.result = JSON.parse(text()) } catch (e) {} }
    }
}
