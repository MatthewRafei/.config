import QtQuick

// Add / edit form for one calendar event, shared by the bar dropdown
// (CalendarPanel) and the big window (CalendarWindow).
//
//   form.startNew(day)   blank event on that day
//   form.edit(ev)        load an existing event (repeating: edits the series)
//   form.date = d        move the event to another day (e.g. a grid click)
//   closed()             saved / deleted / cancelled; `savedStart` is the day to show after
Column {
    id: form

    property var editing: null
    property date date: new Date()
    property bool allDay: false
    property int startMin: 9 * 60
    property int endMin: 10 * 60
    property string repeat: "none"
    property int reminder: 10
    property string error: ""
    property date savedStart: new Date()

    signal closed()

    spacing: 9

    // "9", "930", "9:30", "9:30pm", "21:30", "9 pm" -> minutes after midnight, or -1
    function parseTime(s) {
        const m = String(s).trim().toLowerCase().match(/^(\d{1,2})(?::?(\d{2}))?\s*([ap])?\.?m?\.?$/)
        if (!m) return -1
        let h = +m[1], min = +(m[2] || 0)
        if (min > 59 || h > 23) return -1
        if (m[3] === "p" && h < 12) h += 12
        if (m[3] === "a" && h === 12) h = 0
        return h * 60 + min
    }

    function fmtTime(min) {
        return Qt.formatTime(new Date(2000, 0, 1, Math.floor(min / 60), min % 60), "h:mm AP")
    }

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
    }

    function startNew(day) {
        editing = null
        date = day
        savedStart = day
        allDay = false
        const now = new Date()
        startMin = sameDay(day, now) ? Math.min(23 * 60, (now.getHours() + 1) * 60) : 9 * 60
        endMin = Math.min(startMin + 60, 23 * 60 + 59)
        repeat = "none"
        reminder = 10
        error = ""
        titleIn.text = ""; locationIn.text = ""; notesIn.text = ""
        startIn.text = fmtTime(startMin); endIn.text = fmtTime(endMin)
        titleIn.focusInput()
    }

    function edit(ev) {
        editing = ev
        date = ev.start
        savedStart = ev.start
        allDay = ev.allDay
        startMin = ev.start.getHours() * 60 + ev.start.getMinutes()
        endMin = ev.end.getHours() * 60 + ev.end.getMinutes()
        repeat = ev.repeat
        reminder = ev.reminder
        error = ""
        titleIn.text = ev.title; locationIn.text = ev.location; notesIn.text = ev.notes
        startIn.text = fmtTime(startMin); endIn.text = fmtTime(endMin)
        titleIn.focusInput()
    }

    function save() {
        if (titleIn.text.trim() === "") { error = "give it a title"; titleIn.focusInput(); return }
        const s = parseTime(startIn.text), e = parseTime(endIn.text)
        if (!allDay && (s < 0 || e < 0)) { error = "times look like 9:30 AM or 14:00"; return }
        const d = date
        let start, end
        if (allDay) {
            start = new Date(d.getFullYear(), d.getMonth(), d.getDate())
            end = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1)
        } else {
            start = new Date(d.getFullYear(), d.getMonth(), d.getDate(), Math.floor(s / 60), s % 60)
            end = new Date(d.getFullYear(), d.getMonth(), d.getDate(), Math.floor(e / 60), e % 60)
            if (end <= start) end = new Date(end.getTime() + 86400000)   // runs past midnight
        }
        Calendar.save({
            uid: editing ? editing.uid : undefined,
            file: editing ? editing.file : undefined,
            title: titleIn.text.trim(),
            start: start, end: end, allDay: allDay,
            location: locationIn.text.trim(), notes: notesIn.text.trim(),
            reminder: reminder, repeat: repeat, interval: editing ? editing.interval : 1,
            until: editing ? editing.until : undefined
        })
        savedStart = start
        closed()
    }

    function remove() {
        if (editing) Calendar.remove(editing)
        closed()
    }

    component Label: Text {
        width: 80
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        color: Theme.textFaint
        font.family: Theme.fontFamily
        font.pixelSize: 9
        font.letterSpacing: 2
    }

    Text {
        text: (form.editing ? "EDIT EVENT" : "NEW EVENT") + "  ·  "
            + Qt.formatDate(form.date, "ddd dd MMM yyyy").toUpperCase()
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 10
        font.letterSpacing: 2
        bottomPadding: 4
    }

    HudField {
        id: titleIn
        width: parent.width
        placeholder: "title"
        onAccepted: form.save()
    }

    Row {
        spacing: 6
        Label { text: "WHEN" }
        HudButton { label: "ALL DAY"; on: form.allDay; onClicked: form.allDay = !form.allDay }
        HudField {
            id: startIn
            visible: !form.allDay
            width: 86
            placeholder: "9:00 AM"
            onAccepted: form.save()
            onFinished: { const t = form.parseTime(text); if (t >= 0) { form.startMin = t; text = form.fmtTime(t) } }
        }
        Text {
            visible: !form.allDay
            anchors.verticalCenter: parent.verticalCenter
            text: "–"
            color: Theme.textFaint
            font.family: Theme.fontFamily
        }
        HudField {
            id: endIn
            visible: !form.allDay
            width: 86
            placeholder: "10:00 AM"
            onAccepted: form.save()
            onFinished: { const t = form.parseTime(text); if (t >= 0) { form.endMin = t; text = form.fmtTime(t) } }
        }
    }

    Row {
        spacing: 4
        Label { text: "REPEAT" }
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

    Row {
        spacing: 4
        Label { text: "REMIND" }
        Repeater {
            model: [[-1, "NO"], [0, "AT START"], [10, "10M"], [30, "30M"], [60, "1H"], [1440, "1D"]]
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

    Item {
        width: parent.width
        height: 28

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: form.error !== ""
            text: form.error
            color: Theme.danger
            font.family: Theme.fontFamily
            font.pixelSize: 9
        }

        Row {
            anchors.right: parent.right
            spacing: 6
            HudButton {
                visible: form.editing !== null
                label: form.editing && form.editing.repeat !== "none" ? "DELETE SERIES" : "DELETE"
                danger: true
                onClicked: form.remove()
            }
            HudButton { label: "CANCEL"; onClicked: form.closed() }
            HudButton { label: "SAVE"; on: true; onClicked: form.save() }
        }
    }
}
