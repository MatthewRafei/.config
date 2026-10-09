import QtQuick
import qs

// Add / edit form for one calendar event, shared by the bar dropdown
// (CalendarPanel) and the big window (CalendarWindow). Rows wrap to the width
// they're given, so nothing sticks out of a narrow pane.
//
//   form.startNew(day)   blank event on that day (startNew(day, min) at a time)
//   form.edit(ev)        load an existing event (repeating: edits the series)
//                        fields the form doesn't show (imported RRULE parts,
//                        skipped days, CATEGORIES, ...) are kept as they were
//   form.date = d        move the event to another day (e.g. a grid click)
//   closed()             saved / deleted / cancelled; `savedStart` is the day to show after
//
// Times: a timed event is its start plus a length. Changing the start keeps the
// length; changing the end changes the length. An end at or before the start
// only counts as "runs past midnight" when that's 12 hours or less; anything
// else is refused as ending before it starts.
Column {
    id: form
    property var service

    property var editing: null
    property date date: new Date()
    property bool allDay: false
    property int startMin: 9 * 60
    property int durMin: 60            // timed events: length in minutes
    property int days: 1               // all-day events: how many days
    property bool endBad: false        // the typed end is before the start
    property string repeat: "none"
    property int reminder: 10
    property string error: ""
    property date savedStart: new Date()

    readonly property int endMin: (startMin + durMin) % 1440
    readonly property int endDayOffset: Math.floor((startMin + durMin) / 1440)

    // what's wrong with the times, or "" (blocks SAVE)
    readonly property string timeProblem: {
        if (allDay) return days >= 1 ? "" : "an all-day event needs at least 1 day"
        if (endBad) return "ends before it starts"
        if (durMin <= 0) return "ends when it starts"
        return ""
    }

    // live summary under the times: "1h 30m", "4h · ends next day", "in the past"
    readonly property string timeNote: {
        if (allDay) return days === 1 ? "" : "until " + Qt.formatDate(new Date(date.getFullYear(), date.getMonth(), date.getDate() + days - 1), "ddd dd MMM")
        let s = "lasts " + fmtLength(durMin)
        if (endDayOffset === 1) s += "  ·  ends next day"
        else if (endDayOffset > 1) s += "  ·  ends " + Qt.formatDate(new Date(date.getFullYear(), date.getMonth(), date.getDate() + endDayOffset), "ddd dd MMM")
        if (durMin > 12 * 60) s += "  ·  long event"
        return s
    }
    readonly property bool inPast: {
        if (editing) return false
        const end = allDay ? new Date(date.getFullYear(), date.getMonth(), date.getDate() + days)
                           : new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, startMin + durMin)
        return end < new Date()
    }

    signal closed()

    spacing: 10

    function fmtLength(min) {
        const d = Math.floor(min / 1440), h = Math.floor(min % 1440 / 60), m = min % 60
        return [d ? d + "d" : "", h ? h + "h" : "", m ? m + "m" : ""].filter(x => x).join(" ") || "0m"
    }

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
    }

    function daysBetween(a, b) {
        return Math.round((new Date(b.getFullYear(), b.getMonth(), b.getDate()) - new Date(a.getFullYear(), a.getMonth(), a.getDate())) / 86400000)
    }

    function shiftDate(n) { date = new Date(date.getFullYear(), date.getMonth(), date.getDate() + n) }

    // the end box was set: work out the new length
    function setEnd(e) {
        let len
        if (durMin > 1440) {
            // already runs over several days: keep the day it ends on
            len = endDayOffset * 1440 + e - startMin
            if (len < 0) { endBad = true; return }
        } else {
            len = e - startMin
            // earlier than the start: past midnight if that's believable, else a mistake
            if (len < 0) {
                if (len + 1440 > 12 * 60) { endBad = true; return }
                len += 1440
            }
        }
        endBad = false
        durMin = len
    }

    // a start or length change makes a rejected end irrelevant
    function clearEndBad() {
        if (endBad) { endBad = false; endIn.refresh() }
        error = ""
    }

    function startNew(day, atMin) {
        editing = null
        date = day
        savedStart = day
        allDay = false
        const now = new Date()
        startMin = atMin !== undefined ? atMin
                 : sameDay(day, now) ? Math.min(23 * 60, (now.getHours() + 1) * 60) : 9 * 60
        durMin = 60
        days = 1
        endBad = false
        startIn.refresh(); endIn.refresh()
        repeat = "none"
        reminder = 10
        error = ""
        titleIn.text = ""; locationIn.text = ""; notesIn.text = ""
        titleIn.focusInput()
    }

    function edit(ev) {
        editing = ev
        date = ev.start
        savedStart = ev.start
        allDay = ev.allDay
        startMin = ev.start.getHours() * 60 + ev.start.getMinutes()
        durMin = ev.allDay ? 60 : Math.max(0, Math.round((ev.end - ev.start) / 60000))
        days = ev.allDay ? Math.max(1, daysBetween(ev.start, ev.end)) : 1
        endBad = false
        startIn.refresh(); endIn.refresh()
        repeat = ev.repeat
        reminder = ev.reminder
        error = ""
        titleIn.text = ev.title; locationIn.text = ev.location; notesIn.text = ev.notes
        titleIn.focusInput()
    }

    function save() {
        startIn.commit(); endIn.commit()
        if (titleIn.text.trim() === "") { error = "give it a title"; titleIn.focusInput(); return }
        if (timeProblem) { error = timeProblem; return }
        const d = date
        let start, end
        if (allDay) {
            start = new Date(d.getFullYear(), d.getMonth(), d.getDate())
            end = new Date(d.getFullYear(), d.getMonth(), d.getDate() + days)
        } else {
            // built from local minutes so a DST change keeps the wall-clock times
            start = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, startMin)
            end = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, startMin + durMin)
        }
        // start from the loaded event so fields the form doesn't show are kept
        form.service.save(Object.assign({}, editing || {}, {
            title: titleIn.text.trim(),
            start: start, end: end, allDay: allDay,
            location: locationIn.text.trim(), notes: notesIn.text.trim(),
            reminder: reminder, repeat: repeat,
            origRepeat: editing ? editing.repeat : "none"
        }))
        savedStart = start
        closed()
    }

    function remove() {
        if (editing) form.service.remove(editing)
        closed()
    }

    // label on the left, controls flowing (and wrapping) to its right
    component FormRow: Item {
        id: fr
        property string label
        default property alias content: flow.data
        width: form.width
        height: Math.max(26, flow.implicitHeight)
        Text {
            y: 7
            text: fr.label
            color: Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: 9
            font.letterSpacing: 2
        }
        Flow {
            id: flow
            x: 66
            width: fr.width - 66
            spacing: 4
        }
    }

    component Unit: Text {
        height: 26
        verticalAlignment: Text.AlignVCenter
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 10
    }

    Text {
        width: parent.width
        elide: Text.ElideRight
        text: form.editing ? "EDIT EVENT" : "NEW EVENT"
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 10
        font.letterSpacing: 2
    }

    HudField {
        id: titleIn
        width: parent.width
        placeholder: "title"
        onAccepted: form.save()
    }

    FormRow {
        label: "DATE"
        HudButton { label: "‹"; onClicked: form.shiftDate(-1) }
        Unit {
            width: 104
            horizontalAlignment: Text.AlignHCenter
            text: Qt.formatDate(form.date, "ddd dd MMM yyyy").toUpperCase()
            color: Theme.text
        }
        HudButton { label: "›"; onClicked: form.shiftDate(1) }
        HudButton { label: "ALL DAY"; on: form.allDay; onClicked: { form.allDay = !form.allDay; form.error = "" } }
    }

    // timed: start – end, then the length buttons
    FormRow {
        label: "TIME"
        visible: !form.allDay
        z: startIn.open || endIn.open ? 10 : 0      // the ▾ lists draw over the rows below
        TimeField {
            id: startIn
            minutes: form.startMin
            onPicked: m => { form.startMin = m; form.clearEndBad() }
            onAccepted: form.save()
        }
        Unit { text: "–"; width: 10; horizontalAlignment: Text.AlignHCenter }
        TimeField {
            id: endIn
            minutes: form.endMin
            relativeTo: form.startMin
            bad: form.endBad
            onPicked: m => { form.setEnd(m); form.error = "" }
            onAccepted: form.save()
        }
    }

    FormRow {
        label: "LENGTH"
        visible: !form.allDay
        Repeater {
            model: [[30, "30M"], [60, "1H"], [90, "1.5H"], [120, "2H"], [180, "3H"]]
            HudButton {
                required property var modelData
                label: modelData[1]
                on: !form.endBad && form.durMin === modelData[0]
                onClicked: { form.durMin = modelData[0]; form.clearEndBad() }
            }
        }
    }

    // all-day: how many days
    FormRow {
        label: "LENGTH"
        visible: form.allDay
        HudButton { label: "‹"; onClicked: form.days = Math.max(1, form.days - 1) }
        Unit {
            width: 64
            horizontalAlignment: Text.AlignHCenter
            text: form.days + (form.days === 1 ? " DAY" : " DAYS")
            color: Theme.text
        }
        HudButton { label: "›"; onClicked: form.days = Math.min(366, form.days + 1) }
    }

    // live summary / problem with the times
    Text {
        x: 66
        width: parent.width - 66
        visible: text !== ""
        wrapMode: Text.Wrap
        text: form.timeProblem || [form.timeNote, form.inPast ? "this is in the past" : ""].filter(x => x).join("  ·  ")
        color: form.timeProblem ? Theme.danger : form.inPast ? Theme.accent2 : Theme.textFaint
        font.family: Theme.fontFamily
        font.pixelSize: 9
        font.letterSpacing: 1
    }

    FormRow {
        label: "REPEAT"
        Repeater {
            model: [["none", "NO"], ["daily", "DAY"], ["weekly", "WEEK"], ["monthly", "MONTH"], ["yearly", "YEAR"]]
            HudButton {
                required property var modelData
                label: modelData[1]
                on: form.repeat === modelData[0]
                onClicked: form.repeat = modelData[0]
            }
        }
    }

    FormRow {
        label: "REMIND"
        Repeater {
            model: [[-1, "NO"], [0, form.allDay ? "MIDNIGHT" : "AT START"], [10, "10M"], [30, "30M"], [60, "1H"], [1440, "1D"]]
            HudButton {
                required property var modelData
                label: modelData[1]
                on: form.reminder === modelData[0]
                onClicked: form.reminder = modelData[0]
            }
        }
    }

    HudField { id: locationIn; width: parent.width; placeholder: "location"; onAccepted: form.save() }
    HudField { id: notesIn; width: parent.width; placeholder: "notes"; onAccepted: form.save() }

    // buttons on the right; the error wraps above them if there isn't room beside
    Flow {
        width: parent.width
        spacing: 6
        layoutDirection: Qt.RightToLeft
        HudButton { label: "SAVE"; on: true; onClicked: form.save() }
        HudButton { label: "CANCEL"; onClicked: form.closed() }
        HudButton {
            visible: form.editing !== null
            label: form.editing && form.editing.repeat !== "none" ? "DELETE SERIES" : "DELETE"
            danger: true
            onClicked: form.remove()
        }
    }

    Text {
        width: parent.width
        visible: form.error !== ""
        horizontalAlignment: Text.AlignRight
        wrapMode: Text.Wrap
        text: form.error
        color: Theme.danger
        font.family: Theme.fontFamily
        font.pixelSize: 9
    }
}
