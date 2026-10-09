pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// The module registry (MODULES.md). Reads modules/*/module.json, checks what
// each needs on this machine, keeps the per-machine on/off choices
// (~/.local/share/quickshell/modules.json), and creates / destroys each
// active module's service and windows. The bar, the settings window and the
// quick panel ask it what to show.
//
//   qs ipc call modules list | enable ID | disable ID | rescan
Singleton {
    id: root

    readonly property string dir: Quickshell.shellPath("modules")
    readonly property string stateFile: Quickshell.env("HOME") + "/.local/share/quickshell/modules.json"

    property var manifests: ({})         // id -> parsed module.json
    property var missing: ({})           // id -> ["easyeffects", ...] (requirements this machine lacks)
    property var choices: ({})           // id -> bool (saved switches)
    property bool scanned: false
    property bool choicesLoaded: false
    readonly property bool ready: scanned && choicesLoaded

    // bumped whenever instances change, so bindings on service() re-evaluate
    property int version: 0
    property var instances: ({})         // id -> { service, windows: [] }

    // ---------------------------------------------------------------- queries
    function enabled(id) {
        const m = manifests[id]
        if (!m) return false
        return choices[id] !== undefined ? choices[id] : m.default === true
    }
    function available(id) { return !!manifests[id] && (missing[id] || []).length === 0 }
    // on, available, and every module it needs is active too
    function active(id) {
        version
        if (!enabled(id) || !available(id)) return false
        const need = (manifests[id].requires || {}).modules || []
        return need.every(n => n !== id && active(n))
    }
    // active and already created: what the core should show
    function live(id) { version; return !!instances[id] }
    function service(id) {
        version
        const i = instances[id]
        return i ? i.service : null
    }
    function url(id, file) { return "file://" + dir + "/" + id + "/" + file }

    // everything for Settings > Modules, sorted by name
    readonly property var list: {
        version; choices; missing
        return Object.keys(manifests).sort((a, b) => manifests[a].name.localeCompare(manifests[b].name)).map(id => {
            const m = manifests[id]
            const need = (m.requires || {}).modules || []
            return { id: id, name: m.name, description: m.description || "", icon: m.icon || "",
                     cost: m.cost || "", credit: m.credit || "", enabled: enabled(id), active: active(id),
                     missing: (missing[id] || []).concat(need.filter(n => !active(n)).map(n => "the " + (manifests[n] ? manifests[n].name : n) + " module")) }
        })
    }
    // what the core shows for active modules
    readonly property var chips: {
        version; choices
        return Object.keys(manifests).filter(id => manifests[id].chip && live(id))
            .map(id => ({ id: id, url: url(id, manifests[id].chip.file), order: manifests[id].chip.order || 50 }))
            .sort((a, b) => a.order - b.order)
    }
    readonly property var pages: {
        version; choices
        return Object.keys(manifests).filter(id => manifests[id].page && live(id)).sort()
            .map(id => { const p = manifests[id].page
                return { id: id, name: p.title || manifests[id].name, icon: p.icon || manifests[id].icon || "",
                         url: url(id, p.file), after: p.after || "" } })
    }
    readonly property var quickPages: {
        version; choices
        return Object.keys(manifests).filter(id => manifests[id].quick && live(id))
            .map(id => ({ id: id, quick: manifests[id].quick.id || id, url: url(id, manifests[id].quick.file) }))
    }
    function sections(page) {
        version; choices
        const out = []
        for (const id of Object.keys(manifests).sort()) {
            if (!live(id)) continue
            for (const s of manifests[id].sections || [])
                if (s.page === page) out.push({ id: id, url: url(id, s.file) })
        }
        return out
    }

    // ---------------------------------------------------------------- switches
    function setEnabled(id, on) {
        if (!manifests[id]) return
        const c = Object.assign({}, choices)
        c[id] = on
        choices = c
        store.setText(JSON.stringify(choices, null, 1))
        sync()
    }

    FileView {
        id: store
        path: root.stateFile
        onLoaded: { try { root.choices = JSON.parse(text()) || {} } catch (e) { root.choices = {} } root.choicesLoaded = true }
        onLoadFailed: root.choicesLoaded = true
    }
    // (FileView.setText doesn't create the folder)
    Process { running: true; command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/share/quickshell"] }

    // ---------------------------------------------------------------- scanning
    function rescan() { if (!scan.running) scan.running = true }
    Process {
        id: scan
        running: true
        command: ["sh", "-c", "cd \"$1\" 2>/dev/null || exit 0; for f in */module.json; do [ -r \"$f\" ] || continue; "
                  + "printf '\\036%s\\n' \"${f%/module.json}\"; cat \"$f\"; done", "sh", root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = {}
                for (const part of text.split("\x1e")) {
                    const nl = part.indexOf("\n")
                    if (nl < 0) continue
                    const id = part.slice(0, nl).trim()
                    try { found[id] = JSON.parse(part.slice(nl + 1)) }
                    catch (e) { console.log("modules: bad module.json in", id, e) }
                }
                root.manifests = found
                root.checkRequirements()
            }
        }
    }

    // which commands / files each module needs that this machine lacks
    function checkRequirements() {
        const cmds = {}, files = {}
        for (const id in manifests) {
            const r = manifests[id].requires || {}
            for (const c of r.commands || []) cmds[c] = true
            for (const f of r.files || []) files[f] = true
        }
        req.command = ["sh", "-c",
            "for c in $1; do command -v \"$c\" >/dev/null 2>&1 || echo \"cmd $c\"; done; "
            + "shift; for f in \"$@\"; do case $f in \"~\"/*) f=\"$HOME${f#\\~}\" ;; esac; [ -e \"$f\" ] || echo \"file $f\"; done; "
            + "ls /sys/class/power_supply/ 2>/dev/null | grep -q '^BAT' || echo nobattery",
            "sh", Object.keys(cmds).join(" ")].concat(Object.keys(files))
        req.running = true
    }
    Process {
        id: req
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n").filter(l => l)
                const home = Quickshell.env("HOME")
                const gone = new Set(lines.map(l => l.replace(/^(cmd|file) /, "")))
                const noBattery = lines.indexOf("nobattery") >= 0
                const out = {}
                for (const id in root.manifests) {
                    const r = root.manifests[id].requires || {}
                    const miss = []
                    for (const c of r.commands || []) if (gone.has(c)) miss.push(c)
                    for (const f of r.files || []) if (gone.has(f.replace(/^~/, home))) miss.push(f)
                    if (r.compositor && r.compositor.indexOf(Compositor.name) < 0) miss.push(r.compositor.join(" or "))
                    if (r.battery && noBattery) miss.push("a battery")
                    out[id] = miss
                }
                root.missing = out
                root.scanned = true
                root.sync()
            }
        }
    }

    // ---------------------------------------------------------------- instances
    onReadyChanged: sync()
    function sync() {
        if (!ready) return
        const inst = Object.assign({}, instances)
        let changed = false
        // off first (dependents before what they depend on), then on
        for (const id in inst) {
            if (active(id) && manifests[id]) continue
            const i = inst[id]
            // switched off (not the shell exiting): let it stop what it started
            if (i.service && typeof i.service.moduleStopping === "function") i.service.moduleStopping()
            for (const w of i.windows) w.destroy()
            if (i.service) i.service.destroy()
            delete inst[id]
            changed = true
            console.log("modules: stopped", id)
        }
        if (changed) { instances = inst; version++ }
        const order = Object.keys(manifests).sort((a, b) => ((manifests[a].requires || {}).modules || []).length
                                                           - ((manifests[b].requires || {}).modules || []).length)
        for (const id of order) {
            if (instances[id] || !active(id)) continue
            const m = manifests[id]
            const i = { service: null, windows: [] }
            if (m.service) i.service = create(id, m.service, {})
            const next = Object.assign({}, instances)
            next[id] = i
            instances = next
            version++
            for (const w of m.windows || []) {
                const o = create(id, w, { service: i.service })
                if (o) i.windows.push(o)
            }
            console.log("modules: started", id)
        }
    }
    function create(id, file, props) {
        const c = Qt.createComponent(url(id, file))
        if (c.status !== Component.Ready) { console.log("modules:", id + "/" + file, c.errorString()); return null }
        const o = c.createObject(root, props)
        if (!o) console.log("modules: couldn't create", id + "/" + file)
        return o
    }

    IpcHandler {
        target: "modules"
        function list(): string {
            return root.list.map(m => (m.active ? "● " : m.enabled ? "◐ " : "○ ") + m.id
                + (m.missing.length ? "  (needs " + m.missing.join(", ") + ")" : "")).join("\n")
        }
        function enable(id: string): void { root.setEnabled(id, true) }
        function disable(id: string): void { root.setEnabled(id, false) }
        function rescan(): void { root.rescan() }
    }
}
