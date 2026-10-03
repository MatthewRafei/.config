pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Calendar store: one iCalendar file per event in ~/Calendar, so the folder
// can be synced between PCs with Syncthing without edit conflicts, and any
// .ics-aware app can read it too.
//
// Times are stored as "floating" local time (no time zone), which is what you
// want when every synced machine is in the same zone. Supports all-day and
// timed events, location, notes, one reminder, and simple repeats
// (daily / weekly / monthly / yearly, optional end date).
//
// The folder is re-read every 30s and after every change, so edits arriving
// through Syncthing show up on their own. Reminders pop up as notifications.
//
//   qs ipc call calendar toggle      open/close the dropdown (CalendarPanel.qml)
//   qs ipc call calendar open        open/close the big window (CalendarWindow.qml)
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/Calendar"

    property var events: []       // parsed events, see parse()
    property int revision: 0      // bumps on every reload so views re-evaluate
    property bool panelOpen: false
    property bool windowOpen: false      // CalendarWindow.qml

    // ================================================================ loading
    Process {
        id: loader
        command: ["sh", "-c",
            'd="$1"; mkdir -p "$d"; for f in "$d"/*.ics; do [ -f "$f" ] || continue; '
            + 'printf "\\036FILE %s\\n" "$f"; cat "$f"; echo; done', "sh", root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                for (const chunk of text.split("\u001eFILE ")) {
                    if (!chunk.trim()) continue
                    const nl = chunk.indexOf("\n")
                    const file = chunk.slice(0, nl)
                    for (const ev of root.parseIcs(chunk.slice(nl + 1))) {
                        ev.file = file
                        out.push(ev)
                    }
                }
                root.events = out
                root.revision++
            }
        }
    }

    function reload() { if (!loader.running) loader.running = true }

    Timer {
        interval: 30000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.reload()
    }

    Timer { id: reloadSoon; interval: 250; onTriggered: root.reload() }

    // ================================================================ iCalendar
    function icsUnescape(s) {
        return s.replace(/\\n/gi, "\n").replace(/\\([,;\\])/g, "$1")
    }

    function icsEscape(s) {
        return String(s || "").replace(/\\/g, "\\\\").replace(/;/g, "\\;")
            .replace(/,/g, "\\,").replace(/\r?\n/g, "\\n")
    }

    // "20261003" / "20261003T093000" / "20261003T143000Z" -> { date, allDay }
    function parseDate(value, params) {
        const m = value.match(/^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$/)
        if (!m) return null
        if (!m[4] || /VALUE=DATE(?!-)/.test(params))
            return { date: new Date(+m[1], +m[2] - 1, +m[3]), allDay: true }
        if (m[7])
            return { date: new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +(m[6] || 0))), allDay: false }
        return { date: new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +(m[6] || 0)), allDay: false }
    }

    function pad(n) { return (n < 10 ? "0" : "") + n }

    function fmtDate(d) { return d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate()) }
    function fmtDateTime(d) { return fmtDate(d) + "T" + pad(d.getHours()) + pad(d.getMinutes()) + "00" }

    function parseIcs(text) {
        // unfold continuation lines
        const lines = text.replace(/\r\n/g, "\n").replace(/\n[ \t]/g, "").split("\n")
        const out = []
        let ev = null, inAlarm = false
        for (const line of lines) {
            if (line === "BEGIN:VEVENT") { ev = { reminder: -1, repeat: "none", interval: 1, location: "", notes: "", title: "" }; continue }
            if (line === "END:VEVENT") {
                if (ev && ev.start) {
                    if (!ev.end)
                        ev.end = ev.allDay ? new Date(ev.start.getFullYear(), ev.start.getMonth(), ev.start.getDate() + 1)
                                           : new Date(ev.start.getTime() + 3600000)
                    out.push(ev)
                }
                ev = null
                continue
            }
            if (!ev) continue
            if (line === "BEGIN:VALARM") { inAlarm = true; continue }
            if (line === "END:VALARM") { inAlarm = false; continue }

            const colon = line.indexOf(":")
            if (colon < 0) continue
            const head = line.slice(0, colon)
            const value = line.slice(colon + 1)
            const semi = head.indexOf(";")
            const name = (semi < 0 ? head : head.slice(0, semi)).toUpperCase()
            const params = semi < 0 ? "" : head.slice(semi + 1).toUpperCase()

            if (inAlarm) {
                if (name === "TRIGGER") {
                    const t = value.match(/^-?P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?/)
                    if (t) ev.reminder = (+(t[1] || 0)) * 1440 + (+(t[2] || 0)) * 60 + (+(t[3] || 0))
                }
                continue
            }

            switch (name) {
            case "UID": ev.uid = value; break
            case "SUMMARY": ev.title = icsUnescape(value); break
            case "LOCATION": ev.location = icsUnescape(value); break
            case "DESCRIPTION": ev.notes = icsUnescape(value); break
            case "DTSTART": {
                const d = parseDate(value, params)
                if (d) { ev.start = d.date; ev.allDay = d.allDay }
                break
            }
            case "DTEND": {
                const d = parseDate(value, params)
                if (d) ev.end = d.date
                break
            }
            case "RRULE": {
                const r = {}
                for (const part of value.split(";")) {
                    const kv = part.split("=")
                    r[kv[0].toUpperCase()] = kv[1]
                }
                const freq = (r.FREQ || "").toLowerCase()
                if (["daily", "weekly", "monthly", "yearly"].indexOf(freq) >= 0) ev.repeat = freq
                ev.interval = parseInt(r.INTERVAL) || 1
                if (r.COUNT) ev.count = parseInt(r.COUNT)
                if (r.UNTIL) { const u = parseDate(r.UNTIL, ""); if (u) ev.until = u.date }
                break
            }
            }
        }
        return out
    }

    function fold(line) {
        let out = ""
        while (line.length > 74) { out += line.slice(0, 74) + "\r\n "; line = line.slice(74) }
        return out + line
    }

    function toIcs(ev) {
        const now = new Date()
        const stamp = now.getUTCFullYear() + pad(now.getUTCMonth() + 1) + pad(now.getUTCDate()) + "T"
            + pad(now.getUTCHours()) + pad(now.getUTCMinutes()) + pad(now.getUTCSeconds()) + "Z"
        const L = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//quickshell-hud//calendar//EN",
                   "BEGIN:VEVENT", "UID:" + ev.uid, "DTSTAMP:" + stamp]
        if (ev.allDay) {
            L.push("DTSTART;VALUE=DATE:" + fmtDate(ev.start))
            L.push("DTEND;VALUE=DATE:" + fmtDate(ev.end))
        } else {
            L.push("DTSTART:" + fmtDateTime(ev.start))
            L.push("DTEND:" + fmtDateTime(ev.end))
        }
        L.push("SUMMARY:" + icsEscape(ev.title))
        if (ev.location) L.push("LOCATION:" + icsEscape(ev.location))
        if (ev.notes) L.push("DESCRIPTION:" + icsEscape(ev.notes))
        if (ev.repeat && ev.repeat !== "none") {
            let rule = "FREQ=" + ev.repeat.toUpperCase()
            if (ev.interval > 1) rule += ";INTERVAL=" + ev.interval
            if (ev.until) rule += ";UNTIL=" + fmtDate(ev.until)
            L.push("RRULE:" + rule)
        }
        if (ev.reminder >= 0)
            L.push("BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:" + icsEscape(ev.title),
                   "TRIGGER:-PT" + ev.reminder + "M", "END:VALARM")
        L.push("END:VEVENT", "END:VCALENDAR")
        return L.map(fold).join("\r\n") + "\r\n"
    }

    // ================================================================ changes
    function newUid() {
        return Date.now().toString(36) + "-" + Math.floor(Math.random() * 1e9).toString(36) + "@quickshell"
    }

    // ev: { uid?, title, start: Date, end: Date, allDay, location, notes,
    //       reminder (minutes, -1 = none), repeat, interval, until? }
    function save(ev) {
        if (!ev.uid) ev.uid = newUid()
        const file = ev.file || (root.dir + "/" + ev.uid.replace(/[^A-Za-z0-9._-]/g, "_") + ".ics")
        Quickshell.execDetached(["sh", "-c",
            'mkdir -p "$(dirname "$1")" && printf "%s" "$2" > "$1.tmp" && mv "$1.tmp" "$1"',
            "sh", file, toIcs(ev)])
        reloadSoon.restart()
        return ev.uid
    }

    function remove(ev) {
        if (ev && ev.file)
            Quickshell.execDetached(["rm", "-f", ev.file])
        reloadSoon.restart()
    }

    // ================================================================ queries
    // every occurrence overlapping [from, to), sorted by start
    function occurrences(from, to) {
        const out = []
        for (const ev of events) {
            const dur = ev.end - ev.start
            if (ev.repeat === "none") {
                if (ev.start < to && ev.end > from) out.push({ ev: ev, start: ev.start, end: ev.end })
                continue
            }
            const d0 = ev.start
            for (let i = 0, n = 0; i < 4000; i++) {
                const k = i * ev.interval
                let s
                switch (ev.repeat) {
                case "daily": s = new Date(d0.getFullYear(), d0.getMonth(), d0.getDate() + k, d0.getHours(), d0.getMinutes()); break
                case "weekly": s = new Date(d0.getFullYear(), d0.getMonth(), d0.getDate() + 7 * k, d0.getHours(), d0.getMinutes()); break
                case "monthly":
                    s = new Date(d0.getFullYear(), d0.getMonth() + k, d0.getDate(), d0.getHours(), d0.getMinutes())
                    if (s.getDate() !== d0.getDate()) continue   // no 31st this month
                    break
                case "yearly":
                    s = new Date(d0.getFullYear() + k, d0.getMonth(), d0.getDate(), d0.getHours(), d0.getMinutes())
                    if (s.getDate() !== d0.getDate()) continue   // Feb 29
                    break
                }
                if (s >= to) break
                if (ev.until && s > new Date(ev.until.getFullYear(), ev.until.getMonth(), ev.until.getDate(), 23, 59)) break
                if (ev.count && ++n > ev.count) break
                const e = new Date(s.getTime() + dur)
                if (e > from) out.push({ ev: ev, start: s, end: e })
            }
        }
        out.sort((a, b) => (a.start - b.start) || ((b.ev.allDay ? 1 : 0) - (a.ev.allDay ? 1 : 0)))
        return out
    }

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
            const last = new Date(Math.min(o.end - 1, b - 1))
            for (let d = new Date(first.getFullYear(), first.getMonth(), first.getDate()); d <= last; d.setDate(d.getDate() + 1))
                counts[d.getDate()] = (counts[d.getDate()] || 0) + 1
        }
        return counts
    }

    function next(limit) {
        const now = new Date()
        return occurrences(now, new Date(now.getTime() + 60 * 86400000)).slice(0, limit || 5)
    }

    function timeLabel(o) {
        if (o.ev.allDay) return "ALL DAY"
        return Qt.formatTime(o.start, "h:mm AP") + " – " + Qt.formatTime(o.end, "h:mm AP")
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
