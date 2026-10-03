import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Calendar dropdown under the bar clock (click the clock; right-click still
// toggles the date). Left: month grid with event dots. Right: the selected
// day's events, or the add/edit form. Events live in ~/Calendar (Calendar.qml).
//
// grid: click a day to select it (while editing, it sets the event's date),
//       scroll to change month. form: Enter in the title saves, Esc cancels.
PanelWindow {
    id: root

    readonly property bool open: Calendar.panelOpen

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-calendar"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    visible: open || panel.opacity > 0

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // ---- view state ----
    property date selected: new Date()
    property int viewYear: selected.getFullYear()
    property int viewMonth: selected.getMonth()
    property string mode: "day"          // "day" | "edit"

    onOpenChanged: if (open) { selected = new Date(); viewYear = selected.getFullYear(); viewMonth = selected.getMonth(); mode = "day" }

    function close() { Calendar.panelOpen = false }

    //   qs ipc call calendar-panel add    open straight into a new event
    IpcHandler {
        target: "calendar-panel"
        function add(): void { Calendar.panelOpen = true; addLater.restart() }
    }
    Timer { id: addLater; interval: 50; onTriggered: root.newEvent() }

    function shiftMonth(d) {
        const m = new Date(viewYear, viewMonth + d, 1)
        viewYear = m.getFullYear()
        viewMonth = m.getMonth()
    }

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
    }

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

    // ---- form state ----
    property var editing: null           // the event being edited, or null for a new one
    property date formDate: new Date()
    property bool fAllDay: false
    property int fStart: 9 * 60
    property int fEnd: 10 * 60
    property string fRepeat: "none"
    property int fReminder: 10
    property string formError: ""

    function newEvent() {
        editing = null
        formDate = selected
        fAllDay = false
        const now = new Date()
        fStart = sameDay(selected, now) ? Math.min(23 * 60, (now.getHours() + 1) * 60) : 9 * 60
        fEnd = Math.min(fStart + 60, 23 * 60 + 59)
        fRepeat = "none"
        fReminder = 10
        formError = ""
        titleIn.text = ""; locationIn.text = ""; notesIn.text = ""
        startIn.text = fmtTime(fStart); endIn.text = fmtTime(fEnd)
        mode = "edit"
        titleIn.forceActiveFocus()
    }

    function editEvent(ev) {
        editing = ev
        formDate = ev.start                 // repeating: edit the series from its start
        fAllDay = ev.allDay
        fStart = ev.start.getHours() * 60 + ev.start.getMinutes()
        fEnd = ev.end.getHours() * 60 + ev.end.getMinutes()
        fRepeat = ev.repeat
        fReminder = ev.reminder
        formError = ""
        titleIn.text = ev.title; locationIn.text = ev.location; notesIn.text = ev.notes
        startIn.text = fmtTime(fStart); endIn.text = fmtTime(fEnd)
        mode = "edit"
        titleIn.forceActiveFocus()
    }

    function saveForm() {
        if (titleIn.text.trim() === "") { formError = "give it a title"; titleIn.forceActiveFocus(); return }
        const s = parseTime(startIn.text), e = parseTime(endIn.text)
        if (!fAllDay && (s < 0 || e < 0)) { formError = "times look like 9:30 AM or 14:00"; return }
        const d = formDate
        let start, end
        if (fAllDay) {
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
            start: start, end: end, allDay: fAllDay,
            location: locationIn.text.trim(), notes: notesIn.text.trim(),
            reminder: fReminder, repeat: fRepeat, interval: editing ? editing.interval : 1,
            until: editing ? editing.until : undefined
        })
        selected = start
        mode = "day"
    }

    function deleteEditing() {
        if (editing) Calendar.remove(editing)
        mode = "day"
    }

    // ================================================================ UI
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    // shared bits
    component Btn: Rectangle {
        id: btn
        property string label
        property bool on: false
        property bool danger: false
        signal clicked()
        width: btnText.implicitWidth + 20
        height: 26
        radius: Theme.radius
        readonly property color tint: danger ? Theme.danger : Theme.accent
        color: on ? Theme.alpha(tint, 0.15) : btnMouse.containsMouse ? Theme.bgCard : "transparent"
        border.color: on || btnMouse.containsMouse ? tint : Theme.border
        Text {
            id: btnText
            anchors.centerIn: parent
            text: btn.label
            color: btn.on || btnMouse.containsMouse ? btn.tint : Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 9
            font.bold: btn.on
            font.letterSpacing: 1
        }
        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    component Field: Rectangle {
        id: field
        property alias text: input.text
        property alias input: input
        property string placeholder
        signal accepted()
        signal finished()
        height: 30
        radius: Theme.radius
        color: Theme.bgCard
        border.color: input.activeFocus ? Theme.accent : Theme.border
        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: Theme.text
            selectionColor: Theme.alpha(Theme.accent, 0.4)
            font.family: Theme.fontFamily
            font.pixelSize: 11
            onAccepted: field.accepted()
            onEditingFinished: field.finished()
            Text {
                visible: input.text === "" && !input.activeFocus
                anchors.verticalCenter: parent.verticalCenter
                text: field.placeholder
                color: Theme.textFaint
                font: input.font
            }
        }
    }

    component Label: Text {
        width: 74
        color: Theme.textFaint
        font.family: Theme.fontFamily
        font.pixelSize: 9
        font.letterSpacing: 2
    }

    Rectangle {
        id: panel

        width: 700
        height: 380
        x: (parent.width - width) / 2
        y: 10
        radius: Theme.radius
        color: Theme.alpha(Theme.bgPanel, 0.97)
        border.color: Theme.border

        opacity: root.open ? 1 : 0
        transform: Translate { y: root.open ? 0 : -8 }
        Behavior on opacity { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }

        focus: root.open
        Keys.onEscapePressed: root.mode === "edit" ? root.mode = "day" : root.close()

        MouseArea { anchors.fill: parent }

        // ================= month grid =================
        Item {
            id: gridSide
            x: 18
            y: 16
            width: 300
            height: parent.height - 32

            Item {
                id: monthHead
                width: parent.width
                height: 26

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDate(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy").toUpperCase()
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.bold: true
                    font.letterSpacing: 2
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Btn { label: "‹"; onClicked: root.shiftMonth(-1) }
                    Btn {
                        label: "TODAY"
                        onClicked: { root.selected = new Date(); root.viewYear = root.selected.getFullYear(); root.viewMonth = root.selected.getMonth() }
                    }
                    Btn { label: "›"; onClicked: root.shiftMonth(1) }
                }
            }

            Row {
                id: weekdays
                anchors.top: monthHead.bottom
                anchors.topMargin: 14
                Repeater {
                    model: ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
                    Text {
                        required property string modelData
                        width: gridSide.width / 7
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.letterSpacing: 1
                    }
                }
            }

            Grid {
                id: days
                anchors.top: weekdays.bottom
                anchors.topMargin: 8
                columns: 7

                readonly property date first: new Date(root.viewYear, root.viewMonth, 1)
                readonly property var counts: { Calendar.revision; return Calendar.monthCounts(root.viewYear, root.viewMonth) }

                Repeater {
                    model: 42

                    Item {
                        id: cell
                        required property int index
                        readonly property date day: new Date(root.viewYear, root.viewMonth, 1 - days.first.getDay() + index)
                        readonly property bool inMonth: day.getMonth() === root.viewMonth
                        readonly property bool isToday: root.sameDay(day, clock.date)
                        readonly property bool isSel: root.sameDay(day, root.mode === "edit" ? root.formDate : root.selected)
                        readonly property int count: inMonth ? (days.counts[day.getDate()] || 0) : 0

                        width: gridSide.width / 7
                        height: 38

                        Rectangle {
                            anchors.centerIn: parent
                            width: 32
                            height: 32
                            radius: Theme.radius
                            color: cell.isSel ? Theme.alpha(Theme.accent, 0.18)
                                 : dayMouse.containsMouse ? Theme.bgCard : "transparent"
                            border.color: cell.isToday ? Theme.accent : "transparent"
                        }

                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: cell.count > 0 ? -3 : 0
                            text: cell.day.getDate()
                            color: cell.isSel ? Theme.accent : cell.inMonth ? Theme.text : Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: cell.isSel || cell.isToday
                        }

                        // one dot per event, up to three
                        Row {
                            visible: cell.count > 0
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 7
                            spacing: 2
                            Repeater {
                                model: Math.min(cell.count, 3)
                                Rectangle { width: 3; height: 3; radius: 1.5; color: Theme.accent }
                            }
                        }

                        MouseArea {
                            id: dayMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.mode === "edit") root.formDate = cell.day
                                else root.selected = cell.day
                                if (!cell.inMonth) { root.viewYear = cell.day.getFullYear(); root.viewMonth = cell.day.getMonth() }
                            }
                        }
                    }
                }

                WheelHandler {
                    onWheel: event => root.shiftMonth(event.angleDelta.y > 0 ? -1 : 1)
                }
            }
        }

        Rectangle {
            x: gridSide.x + gridSide.width + 18
            y: 16
            width: 1
            height: parent.height - 32
            color: Theme.border
        }

        // ================= day agenda =================
        Item {
            id: side
            x: gridSide.x + gridSide.width + 37
            y: 16
            width: parent.width - x - 18
            height: parent.height - 32

            Item {
                visible: root.mode === "day"
                anchors.fill: parent

                Item {
                    id: dayHead
                    width: parent.width
                    height: 26
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (root.sameDay(root.selected, clock.date) ? "TODAY  ·  " : "")
                            + Qt.formatDate(root.selected, "ddd dd MMM").toUpperCase()
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.letterSpacing: 2
                    }
                    Btn {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        label: "+  NEW"
                        on: true
                        onClicked: root.newEvent()
                    }
                }

                Flickable {
                    anchors.top: dayHead.bottom
                    anchors.topMargin: 14
                    anchors.bottom: parent.bottom
                    width: parent.width
                    contentHeight: agenda.implicitHeight
                    clip: true

                    Column {
                        id: agenda
                        width: parent.width
                        spacing: 6

                        readonly property var items: { Calendar.revision; return Calendar.onDay(root.selected) }

                        Text {
                            visible: agenda.items.length === 0
                            text: "nothing scheduled"
                            color: Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.italic: true
                            topPadding: 6
                        }

                        Repeater {
                            model: agenda.items

                            Rectangle {
                                id: item
                                required property var modelData
                                readonly property bool past: !modelData.ev.allDay && modelData.end < clock.date
                                width: agenda.width
                                height: itemCol.implicitHeight + 16
                                radius: Theme.radius
                                color: itemMouse.containsMouse ? Theme.bgCard : Theme.alpha(Theme.bgCard, 0.5)
                                border.color: itemMouse.containsMouse ? Theme.borderAccent : "transparent"
                                opacity: past ? 0.5 : 1

                                Rectangle {
                                    width: 2
                                    height: parent.height - 12
                                    x: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Theme.accent
                                }

                                Column {
                                    id: itemCol
                                    x: 16
                                    y: 8
                                    width: parent.width - 26
                                    spacing: 3
                                    Text {
                                        width: parent.width
                                        text: Calendar.timeLabel(item.modelData)
                                            + (item.modelData.ev.repeat !== "none" ? "  ·  " + item.modelData.ev.repeat.toUpperCase() : "")
                                            + (item.modelData.ev.reminder >= 0 ? "  󰂚" : "")
                                        color: Theme.accent
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                        font.letterSpacing: 1
                                    }
                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: item.modelData.ev.title || "(untitled)"
                                        color: Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.bold: true
                                    }
                                    Text {
                                        visible: text !== ""
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: [item.modelData.ev.location, item.modelData.ev.notes.split("\n")[0]].filter(x => x).join("  ·  ")
                                        color: Theme.textDim
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                    }
                                }

                                MouseArea {
                                    id: itemMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.editEvent(item.modelData.ev)
                                }
                            }
                        }
                    }
                }
            }

            // ================= add / edit form =================
            Column {
                visible: root.mode === "edit"
                width: parent.width
                spacing: 9

                Item {
                    width: parent.width
                    height: 26
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (root.editing ? "EDIT EVENT" : "NEW EVENT") + "  ·  "
                            + Qt.formatDate(root.formDate, "ddd dd MMM yyyy").toUpperCase()
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.letterSpacing: 2
                    }
                }

                Field {
                    id: titleIn
                    width: parent.width
                    placeholder: "title"
                    onAccepted: root.saveForm()
                }

                Row {
                    spacing: 6
                    Label { text: "WHEN"; anchors.verticalCenter: parent.verticalCenter }
                    Btn { label: "ALL DAY"; on: root.fAllDay; onClicked: root.fAllDay = !root.fAllDay }
                    Field {
                        id: startIn
                        visible: !root.fAllDay
                        width: 86
                        placeholder: "9:00 AM"
                        onAccepted: root.saveForm()
                        onFinished: { const t = root.parseTime(text); if (t >= 0) { root.fStart = t; text = root.fmtTime(t) } }
                    }
                    Text {
                        visible: !root.fAllDay
                        anchors.verticalCenter: parent.verticalCenter
                        text: "–"
                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                    }
                    Field {
                        id: endIn
                        visible: !root.fAllDay
                        width: 86
                        placeholder: "10:00 AM"
                        onAccepted: root.saveForm()
                        onFinished: { const t = root.parseTime(text); if (t >= 0) { root.fEnd = t; text = root.fmtTime(t) } }
                    }
                }

                Row {
                    spacing: 4
                    Label { text: "REPEAT"; anchors.verticalCenter: parent.verticalCenter }
                    Repeater {
                        model: [["none", "NO"], ["daily", "DAY"], ["weekly", "WEEK"], ["monthly", "MONTH"], ["yearly", "YEAR"]]
                        Btn {
                            required property var modelData
                            label: modelData[1]
                            on: root.fRepeat === modelData[0]
                            onClicked: root.fRepeat = modelData[0]
                        }
                    }
                }

                Row {
                    spacing: 4
                    Label { text: "REMIND"; anchors.verticalCenter: parent.verticalCenter }
                    Repeater {
                        model: [[-1, "NO"], [0, "AT START"], [10, "10M"], [30, "30M"], [60, "1H"], [1440, "1D"]]
                        Btn {
                            required property var modelData
                            label: modelData[1]
                            on: root.fReminder === modelData[0]
                            onClicked: root.fReminder = modelData[0]
                        }
                    }
                }

                Field { id: locationIn; width: parent.width; placeholder: "location"; onAccepted: root.saveForm() }
                Field { id: notesIn; width: parent.width; placeholder: "notes"; onAccepted: root.saveForm() }

                Item {
                    width: parent.width
                    height: 28

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.formError !== ""
                        text: root.formError
                        color: Theme.danger
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                    }

                    Row {
                        anchors.right: parent.right
                        spacing: 6
                        Btn {
                            visible: root.editing !== null
                            label: root.editing && root.editing.repeat !== "none" ? "DELETE SERIES" : "DELETE"
                            danger: true
                            onClicked: root.deleteEditing()
                        }
                        Btn { label: "CANCEL"; onClicked: root.mode = "day" }
                        Btn { label: "SAVE"; on: true; onClicked: root.saveForm() }
                    }
                }
            }
        }
    }
}
