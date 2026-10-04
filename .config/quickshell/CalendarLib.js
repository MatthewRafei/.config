.pragma library

// iCalendar parsing / writing and repeat expansion for Calendar.qml.
// Plain JS (no QML types) so it can be tested with node:
//   sed 1d CalendarLib.js > /tmp/lib.js && node -e 'eval(require("fs").readFileSync("/tmp/lib.js","utf8")); ...'
//
// An event looks like:
//   { uid, title, location, notes, start: Date, end: Date, allDay,
//     reminder (minutes before, -1 none), repeat (none|daily|weekly|monthly|yearly),
//     interval, count?, until?, byday: [{ n, wd }], bymonthday: [int],
//     exdates: [Date], recurrenceId: Date|null, rrule: raw RRULE or "",
//     approx (RRULE has parts we don't expand), stamp: Date|null, seq,
//     extra: [unfolded lines we don't understand, written back untouched],
//     index (n-th VEVENT in its file), blocks (VEVENTs in the file), text (file text) }

var WD = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
var DAY = 86400000

// properties parse() understands; everything else goes to ev.extra
var KNOWN = ["UID", "SUMMARY", "LOCATION", "DESCRIPTION", "DTSTART", "DTEND", "DURATION",
             "RRULE", "EXDATE", "RECURRENCE-ID", "DTSTAMP", "LAST-MODIFIED", "SEQUENCE"]

function pad(n) { return (n < 10 ? "0" : "") + n }
function fmtDate(d) { return d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate()) }
function fmtDateTime(d) { return fmtDate(d) + "T" + pad(d.getHours()) + pad(d.getMinutes()) + pad(d.getSeconds()) }
function fmtUtc(d) {
    return d.getUTCFullYear() + pad(d.getUTCMonth() + 1) + pad(d.getUTCDate()) + "T"
        + pad(d.getUTCHours()) + pad(d.getUTCMinutes()) + pad(d.getUTCSeconds()) + "Z"
}
function dayOf(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }
function addDays(d, n) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n, d.getHours(), d.getMinutes(), d.getSeconds()) }
// whole calendar days from a to b (DST-safe)
function daysBetween(a, b) { return Math.round((dayOf(b) - dayOf(a)) / DAY) }

function unescape(s) {
    return s.replace(/\\n/gi, "\n").replace(/\\([,;\\])/g, "$1")
}

function escape(s) {
    return String(s || "").replace(/\\/g, "\\\\").replace(/;/g, "\\;")
        .replace(/,/g, "\\,").replace(/\r?\n/g, "\\n")
}

// "20261003" / "20261003T093000" / "20261003T143000Z" -> { date, allDay }
// TZID is ignored: such times are read as local ("floating") time.
function parseDate(value, params) {
    var m = String(value).trim().match(/^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$/)
    if (!m) return null
    if (!m[4] || /VALUE=DATE(?!-)/.test(params || ""))
        return { date: new Date(+m[1], +m[2] - 1, +m[3]), allDay: true }
    if (m[7])
        return { date: new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +(m[6] || 0))), allDay: false }
    return { date: new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +(m[6] || 0)), allDay: false }
}

// "-P1DT2H30M" / "PT15M" / "P1W" -> minutes (sign dropped), or null
function parseDuration(value) {
    var m = String(value).trim().match(/^[+-]?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/)
    if (!m) return null
    return (+(m[1] || 0)) * 10080 + (+(m[2] || 0)) * 1440 + (+(m[3] || 0)) * 60 + (+(m[4] || 0)) + Math.round(+(m[5] || 0) / 60)
}

function unfold(text) {
    return text.replace(/\r\n/g, "\n").replace(/\n[ \t]/g, "").split("\n")
}

function fold(line) {
    var out = ""
    while (line.length > 74) { out += line.slice(0, 74) + "\r\n "; line = line.slice(74) }
    return out + line
}

function splitLine(line) {
    var colon = line.indexOf(":")
    if (colon < 0) return null
    var head = line.slice(0, colon)
    var semi = head.indexOf(";")
    return {
        name: (semi < 0 ? head : head.slice(0, semi)).toUpperCase(),
        params: semi < 0 ? "" : head.slice(semi + 1).toUpperCase(),
        value: line.slice(colon + 1)
    }
}

function parseRrule(ev, value) {
    var r = {}
    var parts = value.split(";")
    for (var i = 0; i < parts.length; i++) {
        var kv = parts[i].split("=")
        if (kv[0]) r[kv[0].toUpperCase()] = (kv[1] || "").toUpperCase()
    }
    var freq = (r.FREQ || "").toLowerCase()
    if (["daily", "weekly", "monthly", "yearly"].indexOf(freq) < 0) { ev.approx = true; return }
    ev.repeat = freq
    ev.rrule = value
    ev.interval = Math.max(1, parseInt(r.INTERVAL) || 1)
    if (r.COUNT) ev.count = parseInt(r.COUNT)
    if (r.UNTIL) { var u = parseDate(r.UNTIL, ""); if (u) ev.until = u.date }
    if (r.WKST && WD.indexOf(r.WKST) >= 0) ev.wkst = WD.indexOf(r.WKST)
    if (r.BYDAY && (freq === "weekly" || freq === "monthly")) {
        var days = r.BYDAY.split(",")
        for (var j = 0; j < days.length; j++) {
            var m = days[j].match(/^([+-]?\d+)?([A-Z]{2})$/)
            if (m && WD.indexOf(m[2]) >= 0) ev.byday.push({ n: parseInt(m[1]) || 0, wd: WD.indexOf(m[2]) })
            else ev.approx = true
        }
    }
    if (r.BYMONTHDAY && freq === "monthly") {
        var md = r.BYMONTHDAY.split(",")
        for (var k = 0; k < md.length; k++) { var n = parseInt(md[k]); if (n) ev.bymonthday.push(n) }
    }
    var handled = ["FREQ", "INTERVAL", "COUNT", "UNTIL", "WKST", "BYDAY", "BYMONTHDAY"]
    for (var key in r) {
        if (handled.indexOf(key) >= 0) continue
        // BYMONTH matching the start month is what a plain yearly repeat does anyway
        if (key === "BYMONTH" && freq === "yearly") continue
        ev.approx = true
    }
    if ((r.BYDAY && freq !== "weekly" && freq !== "monthly") || (r.BYMONTHDAY && freq !== "monthly")) ev.approx = true
}

// every VEVENT in one .ics file
function parse(text) {
    var lines = unfold(text)
    var out = []
    var ev = null, inAlarm = false, alarms = 0, duration = null, index = -1
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i]
        if (line === "BEGIN:VEVENT") {
            index++
            ev = { uid: "", title: "", location: "", notes: "", reminder: -1, repeat: "none", interval: 1,
                   byday: [], bymonthday: [], exdates: [], recurrenceId: null, rrule: "", approx: false,
                   stamp: null, seq: 0, extra: [], index: index }
            alarms = 0; duration = null
            continue
        }
        if (line === "END:VEVENT") {
            if (ev && ev.start) {
                if (!ev.end)
                    ev.end = duration !== null ? new Date(ev.start.getTime() + duration * 60000)
                           : ev.allDay ? addDays(ev.start, 1)
                           : new Date(ev.start.getTime())   // RFC 5545: no DTEND/DURATION = instant
                if (ev.end <= ev.start && ev.allDay) ev.end = addDays(ev.start, 1)
                out.push(ev)
            }
            ev = null
            continue
        }
        if (!ev) continue
        if (line === "BEGIN:VALARM") { inAlarm = true; alarms++; continue }
        if (line === "END:VALARM") { inAlarm = false; continue }

        var p = splitLine(line)
        if (!p) continue

        if (inAlarm) {
            // the first alarm is the reminder; relative-to-end and absolute triggers are skipped
            if (alarms === 1 && p.name === "TRIGGER" && p.params.indexOf("RELATED=END") < 0
                    && p.params.indexOf("VALUE=DATE-TIME") < 0) {
                var t = parseDuration(p.value)
                if (t !== null) ev.reminder = /^\s*-/.test(p.value) || t === 0 ? t : -1
            }
            continue
        }

        switch (p.name) {
        case "UID": ev.uid = p.value.trim(); break
        case "SUMMARY": ev.title = unescape(p.value); break
        case "LOCATION": ev.location = unescape(p.value); break
        case "DESCRIPTION": ev.notes = unescape(p.value); break
        case "DTSTART": {
            var d = parseDate(p.value, p.params)
            if (d) { ev.start = d.date; ev.allDay = d.allDay }
            break
        }
        case "DTEND": {
            var e = parseDate(p.value, p.params)
            if (e) ev.end = e.date
            break
        }
        case "DURATION": duration = parseDuration(p.value); break
        case "RRULE": parseRrule(ev, p.value); break
        case "EXDATE": {
            var vals = p.value.split(",")
            for (var j = 0; j < vals.length; j++) {
                var x = parseDate(vals[j], p.params)
                if (x) ev.exdates.push(x.date)
            }
            break
        }
        case "RECURRENCE-ID": {
            var r = parseDate(p.value, p.params)
            if (r) ev.recurrenceId = r.date
            break
        }
        case "DTSTAMP":
        case "LAST-MODIFIED": {
            var s = parseDate(p.value, "")
            if (s && (!ev.stamp || s.date > ev.stamp)) ev.stamp = s.date
            break
        }
        case "SEQUENCE": ev.seq = parseInt(p.value) || 0; break
        default:
            if (KNOWN.indexOf(p.name) < 0) ev.extra.push(line)
        }
    }
    for (var k = 0; k < out.length; k++) out[k].blocks = index + 1
    return out
}

// ------------------------------------------------------------------ writing
function rruleFor(ev) {
    if (!ev.repeat || ev.repeat === "none") return ""
    // an untouched imported rule (BYDAY, COUNT, ...) is written back as it was
    if (ev.rrule && ev.origRepeat === ev.repeat) return ev.rrule
    var rule = "FREQ=" + ev.repeat.toUpperCase()
    if (ev.interval > 1) rule += ";INTERVAL=" + ev.interval
    if (ev.until) rule += ";UNTIL=" + (ev.allDay ? fmtDate(ev.until) : fmtDate(ev.until) + "T235959")
    return rule
}

function dateLine(name, d, allDay) {
    return allDay ? name + ";VALUE=DATE:" + fmtDate(d) : name + ":" + fmtDateTime(d)
}

// one BEGIN:VEVENT ... END:VEVENT block (CRLF, folded, trailing CRLF)
function veventBlock(ev, now) {
    now = now || new Date()
    var L = ["BEGIN:VEVENT", "UID:" + ev.uid, "DTSTAMP:" + fmtUtc(now), "LAST-MODIFIED:" + fmtUtc(now)]
    if (ev.seq || ev.file) L.push("SEQUENCE:" + ((ev.seq || 0) + 1))
    L.push(dateLine("DTSTART", ev.start, ev.allDay))
    L.push(dateLine("DTEND", ev.end, ev.allDay))
    if (ev.recurrenceId) L.push(dateLine("RECURRENCE-ID", ev.recurrenceId, ev.allDay))
    L.push("SUMMARY:" + escape(ev.title))
    if (ev.location) L.push("LOCATION:" + escape(ev.location))
    if (ev.notes) L.push("DESCRIPTION:" + escape(ev.notes))
    var rule = rruleFor(ev)
    if (rule) {
        L.push("RRULE:" + rule)
        if (ev.exdates && ev.exdates.length)
            L.push((ev.allDay ? "EXDATE;VALUE=DATE:" : "EXDATE:")
                   + ev.exdates.map(function (d) { return ev.allDay ? fmtDate(d) : fmtDateTime(d) }).join(","))
    }
    if (ev.extra) for (var i = 0; i < ev.extra.length; i++) L.push(ev.extra[i])
    if (ev.reminder >= 0)
        L.push("BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:" + escape(ev.title),
               "TRIGGER:-PT" + ev.reminder + "M", "END:VALARM")
    L.push("END:VEVENT")
    return L.map(fold).join("\r\n") + "\r\n"
}

function toIcs(ev, now) {
    return "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//quickshell-hud//calendar//EN\r\n"
        + veventBlock(ev, now) + "END:VCALENDAR\r\n"
}

// the file text with VEVENT number `index` replaced by `block` ("" removes it)
function spliceEvent(text, index, block) {
    var i = -1
    return text.replace(/BEGIN:VEVENT\r?\n[\s\S]*?END:VEVENT[ \t]*(\r?\n|$)/g, function (m) {
        i++
        return i === index ? block : m
    })
}

// the file text without every VEVENT whose UID is `uid` (a series and its overrides)
function removeUid(text, uid) {
    return text.replace(/BEGIN:VEVENT\r?\n[\s\S]*?END:VEVENT[ \t]*(\r?\n|$)/g, function (m) {
        var lines = unfold(m)
        for (var i = 0; i < lines.length; i++) {
            var p = splitLine(lines[i])
            if (p && p.name === "UID" && p.value.trim() === uid) return ""
        }
        return m
    })
}

function hasEvents(text) { return /BEGIN:VEVENT/.test(text) }

// ------------------------------------------------------------------ repeats
// start times of the k-th period of a repeating event, sorted, before the
// "not before DTSTART" and COUNT/UNTIL checks
function periodStarts(ev, k) {
    var d0 = ev.start
    var h = d0.getHours(), mi = d0.getMinutes(), se = d0.getSeconds()
    var step = k * ev.interval
    var out = []
    switch (ev.repeat) {
    case "daily":
        out.push(new Date(d0.getFullYear(), d0.getMonth(), d0.getDate() + step, h, mi, se))
        break
    case "weekly": {
        if (!ev.byday.length) {
            out.push(new Date(d0.getFullYear(), d0.getMonth(), d0.getDate() + 7 * step, h, mi, se))
            break
        }
        var wkst = ev.wkst === undefined ? 1 : ev.wkst
        var base = d0.getDate() - ((d0.getDay() - wkst + 7) % 7) + 7 * step
        for (var i = 0; i < ev.byday.length; i++)
            out.push(new Date(d0.getFullYear(), d0.getMonth(), base + (ev.byday[i].wd - wkst + 7) % 7, h, mi, se))
        break
    }
    case "monthly": {
        var y = d0.getFullYear(), m = d0.getMonth() + step
        var first = new Date(y, m, 1)
        var len = new Date(y, m + 1, 0).getDate()
        var days = []
        if (ev.byday.length) {
            for (var j = 0; j < ev.byday.length; j++) {
                var b = ev.byday[j]
                var firstWd = 1 + (b.wd - first.getDay() + 7) % 7     // first such weekday
                var all = []
                for (var dd = firstWd; dd <= len; dd += 7) all.push(dd)
                if (b.n === 0) days = days.concat(all)
                else if (b.n > 0 && b.n <= all.length) days.push(all[b.n - 1])
                else if (b.n < 0 && -b.n <= all.length) days.push(all[all.length + b.n])
            }
        } else if (ev.bymonthday.length) {
            for (var q = 0; q < ev.bymonthday.length; q++) {
                var n = ev.bymonthday[q]
                var dm = n > 0 ? n : len + n + 1
                if (dm >= 1 && dm <= len) days.push(dm)
            }
        } else if (d0.getDate() <= len) {
            days.push(d0.getDate())          // no 31st this month: skipped
        }
        for (var z = 0; z < days.length; z++) out.push(new Date(y, m, days[z], h, mi, se))
        break
    }
    case "yearly": {
        var s = new Date(d0.getFullYear() + step, d0.getMonth(), d0.getDate(), h, mi, se)
        if (s.getDate() === d0.getDate()) out.push(s)   // Feb 29
        break
    }
    }
    out.sort(function (a, b) { return a - b })
    // drop duplicates (e.g. BYDAY=MO,MO)
    return out.filter(function (d, i) { return i === 0 || d.getTime() !== out[i - 1].getTime() })
}

function exKey(d) { return fmtDate(d) + "T" + pad(d.getHours()) + pad(d.getMinutes()) }

// every occurrence of every event overlapping [from, to), sorted by start
// -> [{ ev, start, end }]
function occurrences(events, from, to) {
    var out = []
    // RECURRENCE-ID overrides replace that occurrence of their series
    var overridden = {}
    for (var i = 0; i < events.length; i++)
        if (events[i].recurrenceId) overridden[events[i].uid + "@" + exKey(events[i].recurrenceId)] = true

    for (var e = 0; e < events.length; e++) {
        var ev = events[e]
        var dur = ev.end - ev.start
        if (ev.repeat === "none" || ev.recurrenceId) {
            if (ev.start < to && (ev.end > from || (dur === 0 && ev.start >= from))) out.push({ ev: ev, start: ev.start, end: ev.end })
            continue
        }
        var ex = {}
        for (var x = 0; x < ev.exdates.length; x++) {
            ex[exKey(ev.exdates[x])] = true
        }
        // a date-only EXDATE skips the whole day
        var exDateOnly = {}
        for (var x2 = 0; x2 < ev.exdates.length; x2++)
            if (ev.exdates[x2].getHours() === 0 && ev.exdates[x2].getMinutes() === 0) exDateOnly[fmtDate(ev.exdates[x2])] = true
        var untilEnd = ev.until ? (ev.allDay || (ev.until.getHours() === 0 && ev.until.getMinutes() === 0)
                                   ? new Date(ev.until.getFullYear(), ev.until.getMonth(), ev.until.getDate(), 23, 59, 59)
                                   : ev.until) : null

        // jump close to `from` for long-running daily/weekly repeats without COUNT
        var k0 = 0
        if (!ev.count && (ev.repeat === "daily" || ev.repeat === "weekly")) {
            var period = (ev.repeat === "daily" ? 1 : 7) * ev.interval * DAY
            k0 = Math.max(0, Math.floor((from - ev.start - dur) / period) - 2)
        }
        var n = 0, done = false
        for (var k = k0; k < k0 + 5000 && !done; k++) {
            var starts = periodStarts(ev, k)
            for (var s = 0; s < starts.length; s++) {
                var st = starts[s]
                if (st < ev.start) continue
                if (st >= to || (untilEnd && st > untilEnd)) { done = true; break }
                if (ev.count && ++n > ev.count) { done = true; break }
                if (ex[exKey(st)] || exDateOnly[fmtDate(st)]) continue
                if (overridden[ev.uid + "@" + exKey(st)]) continue
                var en = new Date(st.getTime() + dur)
                if (en > from || (dur === 0 && st >= from)) out.push({ ev: ev, start: st, end: en })
            }
        }
    }
    out.sort(function (a, b) { return (a.start - b.start) || ((b.ev.allDay ? 1 : 0) - (a.ev.allDay ? 1 : 0)) })
    return out
}

// ------------------------------------------------------------------ sync conflicts
// Syncthing keeps the losing side of a conflict as
//   <name>.sync-conflict-YYYYMMDD-HHMMSS-DEVICE.ics
// next to the winner. Those copies are hidden from the views and returned as
// conflicts ({ kept, other }) so the user can pick one.
function isConflictFile(path) { return /\.sync-conflict-[^/]*$/.test(path || "") }

function resolveConflicts(events) {
    var byKey = {}
    for (var i = 0; i < events.length; i++) {
        var ev = events[i]
        if (!isConflictFile(ev.file)) byKey[ev.uid + "@" + (ev.recurrenceId ? exKey(ev.recurrenceId) : "")] = ev
    }
    var shown = [], conflicts = []
    for (var j = 0; j < events.length; j++) {
        var e = events[j]
        if (isConflictFile(e.file)) {
            var kept = byKey[e.uid + "@" + (e.recurrenceId ? exKey(e.recurrenceId) : "")]
            if (kept) { conflicts.push({ kept: kept, other: e }); continue }
        }
        shown.push(e)
    }
    return { events: shown, conflicts: conflicts }
}
