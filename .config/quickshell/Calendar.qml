pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "CalendarLib.js" as Lib

// Calendar store: one iCalendar file per event in a folder (~/.calendar by
// default), so the folder can be synced between PCs with Syncthing without
// edit conflicts, and any .ics-aware app can read it too.
//
// Folder, first one set wins:
//   $QS_CALENDAR_DIR
//   "dir" in ~/.cache/quickshell/calendar.json   e.g. {"dir": "~/Sync/calendar"}
//   ~/.calendar
// The folder gets a .stignore line for the hidden temp files saves use
// (.stignore isn't synced, so each machine adds its own).
//
// Times are stored as "floating" local time (no time zone), which is what you
// want when every synced machine is in the same zone (TZID on imported events
// is ignored). Supports all-day, timed and multi-day events, location, notes,
// one reminder, and repeats (daily / weekly / monthly / yearly with interval,
// end date, count, BYDAY such as "Mon/Wed/Fri" or "2nd Tuesday", skipped days
// and moved occurrences). Parsing and repeat logic live in CalendarLib.js.
// Anything an imported file has that we don't edit (other VEVENTs in the same
// file, VTIMEZONE, CATEGORIES, ...) is written back unchanged.
//
// The folder is re-read every 15s and after every change, so edits arriving
// through Syncthing show up on their own. Writes go to a hidden temp file and
// are renamed into place, so Syncthing never picks up half a file. Syncthing's
// "*.sync-conflict-*.ics" copies are hidden and listed in `conflicts`, which
// CalendarWindow.qml shows so you can pick a side. Reminders pop up as
// notifications.
//
//   qs ipc call calendar toggle      open/close the dropdown (CalendarPanel.qml)
//   qs ipc call calendar open        open/close the big window (CalendarWindow.qml)
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string dir: {
        const d = Quickshell.env("QS_CALENDAR_DIR") || cfg.dir || "~/.calendar"
        return (d.startsWith("~/") ? home + d.slice(1) : d).replace(/\/+$/, "")
    }
    onDirChanged: Qt.callLater(reload)    // after the loader picks up the new path

    FileView {
        path: root.home + "/.cache/quickshell/calendar.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoadFailed: cfg.dir = ""   // file deleted: back to the default
        JsonAdapter {
            id: cfg
            property string dir: ""
        }
    }

    property var events: []       // parsed events, see CalendarLib.js
    property var conflicts: []    // [{ kept, other }] Syncthing conflict copies
    property int fileCount: 0
    property int lastConflicts: 0
    onConflictsChanged: {
        if (conflicts.length > lastConflicts)
            Quickshell.execDetached(["busctl", "--user", "call",
                "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
                "org.freedesktop.Notifications", "Notify", "susssasa{sv}i",
                "Calendar", "0", "x-office-calendar", "Calendar sync conflict",
                "An event was changed on two machines. Open the calendar (Super+C) to pick a version.",
                "0", "0", "0"])
        lastConflicts = conflicts.length
    }
    property int revision: 0      // bumps on every reload so views re-evaluate
    property bool panelOpen: false
    property bool windowOpen: false      // CalendarWindow.qml

    // ================================================================ loading
    Process {
        id: loader
        command: ["sh", "-c",
            'd="$1"; mkdir -p "$d"; '
            + 'grep -qxF ".*.tmp" "$d/.stignore" 2>/dev/null || printf "// quickshell calendar: temp files from saves\\n.*.tmp\\n" >> "$d/.stignore"; '
            + 'for f in "$d"/*.ics; do [ -f "$f" ] || continue; '
            + 'printf "\\036FILE %s\\n" "$f"; cat "$f"; echo; done', "sh", root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                let files = 0
                for (const chunk of text.split("\u001eFILE ")) {
                    if (!chunk.trim()) continue
                    const nl = chunk.indexOf("\n")
                    const file = chunk.slice(0, nl)
                    const body = chunk.slice(nl + 1).replace(/\n$/, "")   // the loader's trailing echo
                    files++
                    for (const ev of Lib.parse(body)) {
                        ev.file = file
                        ev.text = body
                        if (!ev.uid) ev.uid = file
                        out.push(ev)
                    }
                }
                const r = Lib.resolveConflicts(out)
                root.events = r.events
                root.conflicts = r.conflicts
                root.fileCount = files
                root.revision++
            }
        }
    }

    // a reload asked for mid-read runs again right after, so a save is never missed
    property bool reloadPending: false
    function reload() {
        if (loader.running) reloadPending = true
        else loader.running = true
    }
    Connections {
        target: loader
        function onRunningChanged() {
            if (!loader.running && root.reloadPending) { root.reloadPending = false; loader.running = true }
        }
    }

    Timer {
        interval: 15000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.reload()
    }

    Timer { id: reloadSoon; interval: 250; onTriggered: root.reload() }

    // ================================================================ changes
    function newUid() {
        return Date.now().toString(36) + "-" + Math.floor(Math.random() * 1e9).toString(36) + "@quickshell"
    }

    // atomic write: hidden temp file in the same folder, then rename
    function writeFile(file, text) {
        Quickshell.execDetached(["sh", "-c",
            'd="$(dirname "$1")"; t="$d/.$(basename "$1").tmp"; mkdir -p "$d" && printf "%s" "$2" > "$t" && mv -f "$t" "$1"',
            "sh", file, text])
    }

    // ev: an event from `events` with fields changed (Object.assign({}, ev, {...}))
    // or a new one: { title, start: Date, end: Date, allDay, location, notes,
    // reminder (minutes, -1 = none), repeat, interval, until? }
    function save(ev) {
        if (!ev.uid) ev.uid = newUid()
        if (ev.interval === undefined) ev.interval = 1
        const file = ev.file || (root.dir + "/" + ev.uid.replace(/[^A-Za-z0-9._-]/g, "_") + ".ics")
        // files with several VEVENTs (imports with moved occurrences): replace only ours
        const text = ev.file && ev.blocks > 1 && ev.text
            ? Lib.spliceEvent(ev.text, ev.index, Lib.veventBlock(ev))
            : Lib.toIcs(ev)
        writeFile(file, text)
        reloadSoon.restart()
        return ev.uid
    }

    // deletes the event; for a series that also removes its moved occurrences
    function remove(ev) {
        if (!ev || !ev.file) return
        let rest = ""
        if (ev.blocks > 1 && ev.text)
            rest = ev.recurrenceId ? Lib.spliceEvent(ev.text, ev.index, "") : Lib.removeUid(ev.text, ev.uid)
        if (Lib.hasEvents(rest)) writeFile(ev.file, rest)
        else Quickshell.execDetached(["rm", "-f", ev.file])
        reloadSoon.restart()
    }

    // skip one occurrence of a repeating event (EXDATE)
    function skip(o) {
        if (!o || o.ev.repeat === "none" || o.ev.recurrenceId) return
        save(Object.assign({}, o.ev, { exdates: o.ev.exdates.concat([o.start]), origRepeat: o.ev.repeat }))
    }

    // Syncthing conflict: keep this machine's version, or take the other one
    function keepConflict(c) {
        Quickshell.execDetached(["rm", "-f", c.other.file])
        reloadSoon.restart()
    }
    function useConflict(c) {
        Quickshell.execDetached(["mv", "-f", c.other.file, c.kept.file])
        reloadSoon.restart()
    }

    // ================================================================ queries
    // every occurrence overlapping [from, to), sorted by start
    function occurrences(from, to) { return Lib.occurrences(events, from, to) }

    function onDay(d) {
        const a = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        const b = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1)
        return occurrences(a, b)
    }

    // { dayOfMonth: count } for a month view
    function monthCounts(year, month) {
        const counts = {}
        const a = new Date(year, month, 1), b = new Date(year, month + 1, 1)
        for (const o of occurrences(a, b)) {
            const first = o.start < a ? a : o.start
            const last = new Date(Math.max(first, Math.min(o.end - 1, b - 1)))
            for (let d = new Date(first.getFullYear(), first.getMonth(), first.getDate()); d <= last; d.setDate(d.getDate() + 1))
                counts[d.getDate()] = (counts[d.getDate()] || 0) + 1
        }
        return counts
    }

    function next(limit) {
        const now = new Date()
        return occurrences(now, new Date(now.getTime() + 60 * 86400000)).slice(0, limit || 5)
    }

    // plain text -> StyledText with clickable http(s) links
    function linkify(s) {
        return String(s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
            .replace(/https?:\/\/[^\s<]*[^\s<.,;:!?)\]'"]/g, u => '<a href="' + u + '">' + u + '</a>')
            .replace(/\n/g, "<br>")
    }

    // close the calendar (it sits above other windows) and open the link in the browser
    function openLink(url) {
        windowOpen = false
        panelOpen = false
        Qt.openUrlExternally(url.replace(/&amp;/g, "&"))
    }

    function timeLabel(o) {
        const days = Lib.daysBetween(o.start, new Date(o.end - (o.ev.allDay ? 1 : 0)))
        if (o.ev.allDay) return days > 0 ? "ALL DAY  ·  " + (days + 1) + " DAYS" : "ALL DAY"
        if (o.end - o.start === 0) return Qt.formatTime(o.start, "h:mm AP")
        return Qt.formatTime(o.start, "h:mm AP") + " – " + Qt.formatTime(o.end, "h:mm AP")
            + (days > 0 ? " +" + days + "D" : "")
    }

    // ================================================================ reminders
    property var fired: ({})

    Timer {
        interval: 20000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            const now = new Date()
            for (const o of root.occurrences(new Date(now.getTime() - 86400000), new Date(now.getTime() + 8 * 86400000))) {
                if (o.ev.reminder < 0) continue
                const at = o.start.getTime() - o.ev.reminder * 60000
                const key = o.ev.uid + "@" + o.start.getTime()
                // only if it's due within the last 90s, so restarts don't replay old ones
                if (at <= now.getTime() && at > now.getTime() - 90000 && !root.fired[key]) {
                    root.fired[key] = true
                    const when = o.ev.allDay ? "today"
                        : o.ev.reminder === 0 ? "now"
                        : "at " + Qt.formatTime(o.start, "h:mm AP")
                    Quickshell.execDetached(["busctl", "--user", "call",
                        "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
                        "org.freedesktop.Notifications", "Notify", "susssasa{sv}i",
                        "Calendar", "0", "x-office-calendar", o.ev.title || "(untitled)",
                        when + (o.ev.location ? "  ·  " + o.ev.location : ""), "0", "0", "20000"])
                }
            }
        }
    }

    IpcHandler {
        target: "calendar"
        function toggle(): void { root.panelOpen = !root.panelOpen }
        function open(): void { root.panelOpen = false; root.windowOpen = !root.windowOpen }
        function reload(): void { root.reload() }
    }
}
