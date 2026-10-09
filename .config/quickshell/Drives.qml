pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Removable drives (USB sticks, SD cards, external disks), after
// Wian47/omarchy-removable-drives. For the bar's drive chip (shown only while
// one is plugged in) and Settings > Disks. disks/drives.py does the work
// through udisks, so nothing needs a password.
//
// Watches udev, so drives appear and vanish at once. Tracks the kernel's
// writes in flight: a copy dialog at 100% is not the moment to pull a stick,
// so the chip turns red while data is still going out, and an eject asked for
// meanwhile waits until the drive goes quiet.
//
//   qs ipc call drives ejectAll | open | list
Singleton {
    id: root

    readonly property string script: Quickshell.shellPath("disks/drives.py")

    property var drives: []                 // drives.py list
    property var rates: ({})                // drive name -> bytes/s written
    property var pendingEject: ({})         // drive path -> true, waiting for writes to finish
    property string busyDev: ""             // a volume that refused to unmount
    property var busyHolders: []            // ... and who holds it
    property string error: ""
    property string errorDev: ""
    property var working: ({})              // device path -> "mount" / "eject" / ...

    readonly property bool present: drives.length > 0
    // set from each fresh list (plain loops: list properties aren't always real JS arrays)
    property bool writing: false
    property real writeRate: 0
    property var mounted: []

    function fmtBytes(b) {
        if (!(b >= 0)) return "—"
        const u = ["B", "KB", "MB", "GB", "TB"]
        let i = 0
        while (b >= 1000 && i < u.length - 1) { b /= 1000; i++ }
        return (i === 0 ? Math.round(b) : b.toFixed(b < 10 ? 1 : 0)) + " " + u[i]
    }
    function fmtRate(b) { return fmtBytes(b) + "/s" }

    // ------------------------------------------------------------ list
    property var _last: ({})                // name -> { sectors, t }
    property var _known: null               // drive names -> { title, mounted } last time
    function refresh() { if (!lister.running) lister.running = true; else _again = true }
    property bool _again: false

    Process {
        id: lister
        command: ["python3", "-I", root.script, "list"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let list
                try { list = JSON.parse(text) } catch (e) { return }
                const now = Date.now(), last = root._last, rates = {}, seen = {}
                for (const d of list) {
                    const p = last[d.name]
                    if (p && now > p.t) rates[d.name] = Math.max(0, (d.sectorsWritten - p.sectors) * 512 / ((now - p.t) / 1000))
                    seen[d.name] = { sectors: d.sectorsWritten, t: now }
                }
                root._last = seen
                root.rates = rates
                root.announce(list)
                let busy = false, rate = 0
                const mounted = []
                for (const d of list) {
                    if (d.writing > 0) busy = true
                    rate += rates[d.name] || 0
                    for (const v of d.volumes) if (v.mountpoint) mounted.push(v)
                }
                root.writing = busy
                root.writeRate = rate
                root.mounted = mounted
                root.drives = list
                // waiting ejects fire once the drive has nothing in flight
                for (const path in root.pendingEject) {
                    const d = list.find(x => x.path === path)
                    if (!d) root.clearPending(path)
                    else if (d.writing === 0 && (rates[d.name] || 0) < 4096) { root.clearPending(path); root.ejectNow(d) }
                }
            }
        }
        onExited: if (root._again) { root._again = false; running = true }
    }

    // plugged in / pulled out, as notifications
    function announce(list) {
        const now = {}
        for (const d of list) now[d.name] = { title: d.title, mounted: d.volumes.some(v => v.mountpoint) }
        if (_known !== null) {
            for (const n in now) if (!_known[n])
                notify("Drive connected", now[n].title)
            for (const n in _known) if (!now[n])
                notify(_known[n].mounted ? "Drive pulled out while mounted" : "Drive removed", _known[n].title
                       + (_known[n].mounted ? " — anything still being written may be lost" : ""), _known[n].mounted)
        }
        _known = now
    }
    function notify(title, body, urgent) {
        Quickshell.execDetached(["notify-send", "-a", "Drives", "-i", "drive-removable-media",
                                 "-u", urgent ? "critical" : "normal", title, body || ""])
    }

    // udev says a block device came or went: look again (debounced, a stick
    // with partitions sends a burst)
    Process {
        running: true
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=block"]
        stdout: SplitParser { onRead: line => { if (/ (add|remove|change) /.test(line)) settle.restart() } }
    }
    Timer { id: settle; interval: 500; onTriggered: root.refresh() }
    // fast while something is being written or waits to eject, slow otherwise
    Timer {
        interval: root.writing || Object.keys(root.pendingEject).length ? 1000 : 5000
        repeat: true
        running: root.present
        onTriggered: root.refresh()
    }

    // ------------------------------------------------------------ actions
    property var queue: []
    function act(args, dev, kind, after, input) {
        const w = Object.assign({}, working); w[dev] = kind; working = w
        if (errorDev === dev) { error = ""; errorDev = "" }
        if (busyDev === dev) { busyDev = ""; busyHolders = [] }
        queue = queue.concat([{ args: args, dev: dev, after: after || null, input: input || "" }])
        pump()
    }
    function pump() {
        if (doer.running || !queue.length) return
        const job = queue[0]
        queue = queue.slice(1)
        doer.job = job
        doer.command = ["python3", "-I", script].concat(job.args)
        doer.stdinEnabled = job.input !== ""
        doer.running = true
    }
    Process {
        id: doer
        property var job: null
        stdout: StdioCollector { id: doOut }
        onStarted: if (stdinEnabled) { write(job.input + "\n"); stdinEnabled = false }
        onExited: code => {
            const job = doer.job
            const w = Object.assign({}, root.working); delete w[job.dev]; root.working = w
            let r = {}
            try { r = JSON.parse(doOut.text) } catch (e) {}
            if (code !== 0) {
                if (r.error === "busy") { root.busyDev = job.dev; root.busyHolders = r.holders || [] }
                else { root.error = r.error || "Something went wrong"; root.errorDev = job.dev }
            } else if (job.after) job.after(r)
            root.refresh()
            Qt.callLater(root.pump)
        }
    }

    function mount(v, thenOpen) {
        act(["mount", v.path], v.path, "mount", r => { if (thenOpen && r.mountpoint) open(r.mountpoint) })
    }
    function unmount(v) { act(["unmount", v.path], v.path, "unmount") }
    function unmountLazy(v) { act(["unmount-lazy", v.path], v.path, "unmount") }
    // passphrase over stdin only
    function unlock(v, pass) { act(["unlock", v.path], v.path, "unlock", null, pass) }
    function lock(v) { act(["lock", v.path], v.path, "lock") }
    function open(path) { if (path) Quickshell.execDetached(["xdg-open", path]) }

    function eject(d) {
        if (d.writing > 0 || (rates[d.name] || 0) > 4096) {
            const p = Object.assign({}, pendingEject); p[d.path] = true; pendingEject = p
            return
        }
        ejectNow(d)
    }
    function ejectNow(d) {
        act(["eject", d.path], d.path, "eject", r => notify("Safe to remove", d.title
            + (r.poweredOff ? "" : " (unmounted; this reader can't be powered off)")))
    }
    function clearPending(path) { const p = Object.assign({}, pendingEject); delete p[path]; pendingEject = p }
    function ejectAll() { for (const d of drives) eject(d) }

    IpcHandler {
        target: "drives"
        function ejectAll(): void { root.ejectAll() }
        function open(): void { if (root.mounted.length) root.open(root.mounted[0].mountpoint) }
        function list(): string { return JSON.stringify(root.drives) }
    }
}
