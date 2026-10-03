import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Full calendar window, opened like Settings (centered card, tilt-in).
// Same events as the bar dropdown (Calendar.qml, ~/Calendar).
//
//   sidebar   today, sun times, next event countdown, views, stats, + NEW
//   main      MONTH grid (titles in cells) / WEEK timeline / AGENDA list
//   right     selected day's events, an event's full details, or the form
//
//   keys      Esc back/close · ←/→ previous/next month or week · T today
//             N new event · M / W / A switch view
//   open      OPEN ⤢ in the dropdown, or `qs ipc call calendar open`
//             (`qs ipc call calendar-window view week|month|agenda`, `... next`)
PanelWindow {
    id: root

    readonly property bool showing: Calendar.windowOpen

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-calendar-window"
    WlrLayershell.keyboardFocus: showing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    visible: showing || card.visible

    SystemClock { id: clock; precision: SystemClock.Seconds }

    // ---------------- state ----------------
    property string view: "month"          // month | week | agenda
    property string pane: "day"            // day | event | edit
    property date selDay: new Date()
    property var selOcc: null              // { ev, start, end }
    property int viewYear: selDay.getFullYear()
    property int viewMonth: selDay.getMonth()
    property date weekStart: startOfWeek(selDay)
    property bool confirmDelete: false

    onShowingChanged: if (showing) { goToday(); pane = "day"; selOcc = null }

    function close() { Calendar.windowOpen = false }

    //   qs ipc call calendar-window view week     month | week | agenda
    //   qs ipc call calendar-window next          open the next event's details
    IpcHandler {
        target: "calendar-window"
        function view(name: string): void {
            Calendar.windowOpen = true
            root.view = name
            if (name === "week") root.weekStart = root.startOfWeek(root.selDay)
        }
        function next(): void {
            Calendar.windowOpen = true
            if (root.nextOcc) root.pickOcc(root.nextOcc)
        }
    }

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
    }
    function startOfWeek(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() - d.getDay()) }
    function addDays(d, n) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n) }
    // 9:30 AM -> "9:30a", 1:00 PM -> "1p"
    function shortTime(d) {
        const t = Qt.formatTime(d, "h:mm AP")
        return t.replace(":00", "").replace(/\s*([AP])M$/i, (m, x) => x.toLowerCase())
    }
    function isoWeek(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
        t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7))
        return Math.ceil(((t - Date.UTC(t.getUTCFullYear(), 0, 1)) / 86400000 + 1) / 7)
    }

    function goToday() {
        selDay = new Date()
        viewYear = selDay.getFullYear()
        viewMonth = selDay.getMonth()
        weekStart = startOfWeek(selDay)
    }

    function step(dir) {
        if (view === "week") {
            weekStart = addDays(weekStart, 7 * dir)
        } else {
            const m = new Date(viewYear, viewMonth + dir, 1)
            viewYear = m.getFullYear()
            viewMonth = m.getMonth()
        }
    }

    function pickDay(d) {
        if (pane === "edit") { form.date = d; return }
        selDay = d
        selOcc = null
        pane = "day"
        if (d.getMonth() !== viewMonth && view === "month") { viewYear = d.getFullYear(); viewMonth = d.getMonth() }
    }

    function pickOcc(o) {
        selOcc = o
        selDay = o.start
        pane = "event"
        confirmDelete = false
    }

    function newEvent(day) { pane = "edit"; form.startNew(day || selDay) }

    // "in 2d 4h" / "in 25m" / "now" / "3h ago"
    function relative(o) {
        const now = clock.date.getTime()
        if (o.start.getTime() <= now && o.end.getTime() > now) return "happening now"
        const diff = o.start.getTime() - now
        const a = Math.abs(diff)
        const d = Math.floor(a / 86400000), h = Math.floor(a % 86400000 / 3600000), m = Math.floor(a % 3600000 / 60000)
        const txt = d > 0 ? d + "d " + h + "h" : h > 0 ? h + "h " + m + "m" : Math.max(1, m) + "m"
        return diff > 0 ? "in " + txt : (o.end.getTime() <= now ? "ended " : "") + txt + " ago"
    }

    function duration(o) {
        if (o.ev.allDay) {
            const days = Math.round((o.end - o.start) / 86400000)
            return days === 1 ? "all day" : days + " days"
        }
        const mins = Math.round((o.end - o.start) / 60000)
        const h = Math.floor(mins / 60), m = mins % 60
        return (h ? h + "h " : "") + (m ? m + "m" : "")
    }

    function repeatText(ev) {
        if (ev.repeat === "none") return "does not repeat"
        const unit = { daily: "day", weekly: "week", monthly: "month", yearly: "year" }[ev.repeat]
        return "every " + (ev.interval > 1 ? ev.interval + " " + unit + "s" : unit)
            + (ev.until ? " until " + Qt.formatDate(ev.until, "dd MMM yyyy") : "")
    }

    function reminderText(ev) {
        if (ev.reminder < 0) return "no reminder"
        if (ev.reminder === 0) return "at start"
        if (ev.reminder % 1440 === 0) return ev.reminder / 1440 + " day before"
        if (ev.reminder % 60 === 0) return ev.reminder / 60 + " hour before"
        return ev.reminder + " min before"
    }

    // live data (re-evaluates when Calendar reloads)
    readonly property var nextOcc: { Calendar.revision; clock.date.getMinutes(); const n = Calendar.next(1); return n.length ? n[0] : null }
    readonly property var weekStats: {
        Calendar.revision
        const a = startOfWeek(clock.date), b = addDays(a, 7)
        const occ = Calendar.occurrences(a, b)
        let mins = 0
        for (const o of occ) if (!o.ev.allDay) mins += (o.end - o.start) / 60000
        return { count: occ.length, hours: Math.round(mins / 6) / 10 }
    }
    readonly property int monthCount: {
        Calendar.revision
        const n = clock.date
        return Calendar.occurrences(new Date(n.getFullYear(), n.getMonth(), 1), new Date(n.getFullYear(), n.getMonth() + 1, 1)).length
    }

    // ================================================================ backdrop
    Rectangle {
        anchors.fill: parent
        color: Theme.alpha(Theme.bgPanel, 0.55)
        opacity: root.showing ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animMed } }
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    PerspectivePanel {
        id: card
        anchors.centerIn: parent
        width: Math.min(1240, root.width - 80)
        height: Math.min(760, root.height - 80)
        open: root.showing

        MouseArea { anchors.fill: parent }

        Rectangle {
            id: frame
            anchors.fill: parent
            color: Theme.bg
            radius: 6
            border.color: Theme.accent
            border.width: 1

            focus: root.showing
            Keys.onPressed: event => {
                if (root.pane === "edit") {
                    if (event.key === Qt.Key_Escape) { root.pane = "day"; event.accepted = true }
                    return
                }
                switch (event.key) {
                case Qt.Key_Escape:
                    if (root.pane === "event") root.pane = "day"
                    else root.close()
                    break
                case Qt.Key_Left: root.step(-1); break
                case Qt.Key_Right: root.step(1); break
                case Qt.Key_T: root.goToday(); break
                case Qt.Key_N: root.newEvent(); break
                case Qt.Key_M: root.view = "month"; break
                case Qt.Key_W: root.view = "week"; root.weekStart = root.startOfWeek(root.selDay); break
                case Qt.Key_A: root.view = "agenda"; break
                default: return
                }
                event.accepted = true
            }

            // corner accents, as in Settings
            Rectangle { width: 40; height: 2; color: Theme.accent2; anchors { top: parent.top; left: parent.left; margins: 14 } }
            Rectangle { width: 2; height: 40; color: Theme.accent2; anchors { top: parent.top; left: parent.left; margins: 14 } }
            Rectangle { width: 40; height: 2; color: Theme.accent2; anchors { bottom: parent.bottom; right: parent.right; margins: 14 } }
            Rectangle { width: 2; height: 40; color: Theme.accent2; anchors { bottom: parent.bottom; right: parent.right; margins: 14 } }

            Row {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 24

                // ======================================================= sidebar
                Item {
                    id: sidebar
                    width: 220
                    height: parent.height

                    Column {
                        width: parent.width
                        spacing: 18

                        Text {
                            text: "CALENDAR"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 20
                            font.bold: true
                            font.letterSpacing: 4
                        }

                        Rectangle { width: parent.width; height: 1; color: Theme.border }

                        // today
                        Row {
                            spacing: 14
                            Text {
                                id: bigDay
                                text: clock.date.getDate()
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: 54
                                font.weight: Font.Light
                            }
                            Column {
                                anchors.verticalCenter: bigDay.verticalCenter
                                spacing: 4
                                Text {
                                    text: Qt.formatDate(clock.date, "dddd").toUpperCase()
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.letterSpacing: 2
                                }
                                Text {
                                    text: Qt.formatDate(clock.date, "MMMM yyyy").toUpperCase()
                                    color: Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.letterSpacing: 1
                                }
                                Text {
                                    readonly property int doy: Math.round((new Date(clock.date.getFullYear(), clock.date.getMonth(), clock.date.getDate()) - new Date(clock.date.getFullYear(), 0, 1)) / 86400000) + 1
                                    text: "WEEK " + root.isoWeek(clock.date) + "  ·  DAY " + doy
                                    color: Theme.textFaint
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.letterSpacing: 1
                                }
                            }
                        }

                        Text {
                            text: "󰖜 " + NightLight.fmt(NightLight.sun.rise) + "    󰖛 " + NightLight.fmt(NightLight.sun.set)
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                        }

                        // next event
                        Rectangle {
                            width: parent.width
                            height: nextCol.implicitHeight + 20
                            radius: Theme.radius
                            color: Theme.alpha(Theme.bgCard, 0.8)
                            border.color: nextMouse.containsMouse && root.nextOcc ? Theme.accent : Theme.border

                            Rectangle {
                                width: 2; height: parent.height - 14; x: 7
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.accent
                            }

                            Column {
                                id: nextCol
                                x: 18; y: 10
                                width: parent.width - 28
                                spacing: 4
                                Text {
                                    text: "NEXT"
                                    color: Theme.textFaint
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.letterSpacing: 2
                                }
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: root.nextOcc ? (root.nextOcc.ev.title || "(untitled)") : "nothing coming up"
                                    color: root.nextOcc ? Theme.text : Theme.textFaint
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: root.nextOcc !== null
                                }
                                Text {
                                    visible: root.nextOcc !== null
                                    text: root.nextOcc ? root.relative(root.nextOcc) + "  ·  " + Qt.formatDate(root.nextOcc.start, "ddd dd MMM").toUpperCase() : ""
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.letterSpacing: 1
                                }
                            }

                            MouseArea {
                                id: nextMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: root.nextOcc ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: if (root.nextOcc) {
                                    root.pickOcc(root.nextOcc)
                                    root.viewYear = root.nextOcc.start.getFullYear()
                                    root.viewMonth = root.nextOcc.start.getMonth()
                                    root.weekStart = root.startOfWeek(root.nextOcc.start)
                                }
                            }
                        }

                        Rectangle { width: parent.width; height: 1; color: Theme.border }

                        // views
                        Column {
                            width: parent.width
                            spacing: 4
                            Repeater {
                                model: [["month", "󰃭", "Month", "M"], ["week", "󰨳", "Week", "W"], ["agenda", "󰃮", "Agenda", "A"]]
                                Rectangle {
                                    required property var modelData
                                    readonly property bool sel: root.view === modelData[0]
                                    width: sidebar.width
                                    height: 36
                                    radius: Theme.radius
                                    color: sel ? Theme.alpha(Theme.accent, 0.12) : viewMouse.containsMouse ? Theme.bgCard : "transparent"
                                    border.width: sel ? 1 : 0
                                    border.color: Theme.accent
                                    Rectangle {
                                        visible: parent.sel
                                        width: 3; height: parent.height - 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: Theme.accent2
                                    }
                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: 16
                                        spacing: 12
                                        Text {
                                            text: modelData[1]
                                            color: parent.parent.sel ? Theme.accent : Theme.textDim
                                            font.family: Theme.iconFont
                                            font.pixelSize: 14
                                        }
                                        Text {
                                            text: modelData[2]
                                            color: parent.parent.sel ? Theme.text : Theme.textDim
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                        }
                                    }
                                    Text {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData[3]
                                        color: Theme.textFaint
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                    }
                                    MouseArea {
                                        id: viewMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.view = modelData[0]
                                            if (modelData[0] === "week") root.weekStart = root.startOfWeek(root.selDay)
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle { width: parent.width; height: 1; color: Theme.border }

                        // stats
                        Grid {
                            columns: 2
                            columnSpacing: 14
                            rowSpacing: 6
                            Repeater {
                                model: [
                                    ["THIS WEEK", root.weekStats.count + (root.weekStats.count === 1 ? " event" : " events")],
                                    ["BOOKED", root.weekStats.hours + " h"],
                                    ["THIS MONTH", root.monthCount + (root.monthCount === 1 ? " event" : " events")]
                                ]
                                Column {
                                    required property var modelData
                                    width: (sidebar.width - 14) / 2
                                    spacing: 2
                                    Text { text: modelData[0]; color: Theme.textFaint; font.family: Theme.fontFamily; font.pixelSize: 8; font.letterSpacing: 2 }
                                    Text { text: modelData[1]; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 12 }
                                }
                            }
                        }
                    }

                    Column {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        spacing: 10
                        HudButton {
                            width: parent.width
                            height: 34
                            label: "+  NEW EVENT"
                            on: true
                            fontSize: 10
                            onClicked: root.newEvent()
                        }
                        Text {
                            text: "~/Calendar  ·  " + Calendar.events.length + " files"
                            color: Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }
                    }
                }

                Rectangle { width: 1; height: parent.height; color: Theme.border }

                // ======================================================= main
                Item {
                    id: main
                    width: parent.width - sidebar.width - detail.width - 2 - 4 * 24
                    height: parent.height

                    // header
                    Item {
                        id: mainHead
                        width: parent.width
                        height: 30

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.view === "month"
                                ? Qt.formatDate(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy").toUpperCase()
                                : root.view === "week"
                                ? "WEEK OF " + Qt.formatDate(root.weekStart, "dd MMM").toUpperCase() + " – " + Qt.formatDate(root.addDays(root.weekStart, 6), "dd MMM yyyy").toUpperCase()
                                : "NEXT 60 DAYS"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 16
                            font.bold: true
                            font.letterSpacing: 3
                        }

                        Row {
                            visible: root.view !== "agenda"
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            HudButton { label: "‹"; onClicked: root.step(-1) }
                            HudButton { label: "TODAY"; onClicked: root.goToday() }
                            HudButton { label: "›"; onClicked: root.step(1) }
                        }
                    }

                    // ---------------- month ----------------
                    Item {
                        id: monthView
                        visible: root.view === "month"
                        anchors.top: mainHead.bottom
                        anchors.topMargin: 16
                        anchors.bottom: parent.bottom
                        width: parent.width

                        readonly property date first: new Date(root.viewYear, root.viewMonth, 1)
                        readonly property var occ: {
                            Calendar.revision
                            const a = new Date(root.viewYear, root.viewMonth, 1 - first.getDay())
                            return Calendar.occurrences(a, root.addDays(a, 42))
                        }

                        Row {
                            id: wdays
                            Repeater {
                                model: ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
                                Text {
                                    required property string modelData
                                    width: monthView.width / 7
                                    leftPadding: 8
                                    text: modelData
                                    color: Theme.textFaint
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.letterSpacing: 2
                                }
                            }
                        }

                        Grid {
                            anchors.top: wdays.bottom
                            anchors.topMargin: 8
                            columns: 7
                            rowSpacing: 4
                            columnSpacing: 4
                            readonly property real cw: (monthView.width - 6 * 4) / 7
                            readonly property real ch: (monthView.height - wdays.height - 8 - 5 * 4) / 6

                            Repeater {
                                model: 42

                                Rectangle {
                                    id: mcell
                                    required property int index
                                    readonly property date day: new Date(root.viewYear, root.viewMonth, 1 - monthView.first.getDay() + index)
                                    readonly property bool inMonth: day.getMonth() === root.viewMonth
                                    readonly property bool isToday: root.sameDay(day, clock.date)
                                    readonly property bool isSel: root.sameDay(day, root.pane === "edit" ? form.date : root.selDay)
                                    readonly property var items: {
                                        const a = day, b = root.addDays(day, 1)
                                        return monthView.occ.filter(o => o.start < b && o.end > a)
                                    }
                                    readonly property int maxChips: Math.max(0, Math.floor((height - 30) / 19))

                                    width: parent.cw
                                    height: parent.ch
                                    radius: Theme.radius
                                    color: isSel ? Theme.alpha(Theme.accent, 0.10)
                                         : cellMouse.containsMouse ? Theme.alpha(Theme.bgCard, 0.9)
                                         : Theme.alpha(Theme.bgCard, inMonth ? 0.45 : 0.15)
                                    border.color: isToday ? Theme.accent : isSel ? Theme.borderAccent : "transparent"

                                    MouseArea {
                                        id: cellMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.pickDay(mcell.day)
                                        onDoubleClicked: { root.pickDay(mcell.day); root.newEvent(mcell.day) }
                                    }

                                    Text {
                                        x: 8; y: 6
                                        text: mcell.day.getDate()
                                        color: mcell.isToday ? Theme.accent : mcell.inMonth ? Theme.text : Theme.textFaint
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.bold: mcell.isToday
                                    }

                                    Column {
                                        x: 5
                                        y: 26
                                        width: parent.width - 10
                                        spacing: 3

                                        Repeater {
                                            model: mcell.items.slice(0, mcell.items.length > mcell.maxChips ? mcell.maxChips - 1 : mcell.maxChips)
                                            Rectangle {
                                                id: chip
                                                required property var modelData
                                                readonly property bool sel: root.selOcc !== null && root.selOcc.ev.uid === modelData.ev.uid
                                                    && root.selOcc.start.getTime() === modelData.start.getTime()
                                                width: parent.width
                                                height: 16
                                                radius: 2
                                                color: sel ? Theme.alpha(Theme.accent, 0.35)
                                                     : modelData.ev.allDay ? Theme.alpha(Theme.accent, 0.18)
                                                     : chipMouse.containsMouse ? Theme.alpha(Theme.accent, 0.15) : "transparent"
                                                Rectangle { width: 2; height: parent.height; color: Theme.accent; visible: !chip.modelData.ev.allDay }
                                                Text {
                                                    x: 6
                                                    width: parent.width - 8
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    elide: Text.ElideRight
                                                    text: (chip.modelData.ev.allDay ? "" : root.shortTime(chip.modelData.start) + " ")
                                                        + (chip.modelData.ev.title || "(untitled)")
                                                    color: Theme.text
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 9
                                                }
                                                MouseArea {
                                                    id: chipMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.pickOcc(chip.modelData)
                                                }
                                            }
                                        }

                                        Text {
                                            visible: mcell.items.length > mcell.maxChips
                                            text: "+" + (mcell.items.length - mcell.maxChips + 1) + " more"
                                            color: Theme.textDim
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 9
                                            leftPadding: 4
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---------------- week ----------------
                    Item {
                        id: weekView
                        visible: root.view === "week"
                        anchors.top: mainHead.bottom
                        anchors.topMargin: 16
                        anchors.bottom: parent.bottom
                        width: parent.width

                        readonly property real gutter: 52
                        readonly property real colW: (width - gutter) / 7
                        readonly property real hourH: 42
                        readonly property var occ: { Calendar.revision; return Calendar.occurrences(root.weekStart, root.addDays(root.weekStart, 7)) }

                        // day headers
                        Row {
                            id: weekHead
                            x: weekView.gutter
                            Repeater {
                                model: 7
                                Column {
                                    required property int index
                                    readonly property date day: root.addDays(root.weekStart, index)
                                    readonly property bool isToday: root.sameDay(day, clock.date)
                                    width: weekView.colW
                                    spacing: 2
                                    Text {
                                        leftPadding: 6
                                        text: Qt.formatDate(parent.day, "ddd").toUpperCase()
                                        color: parent.isToday ? Theme.accent : Theme.textFaint
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                        font.letterSpacing: 2
                                    }
                                    Text {
                                        leftPadding: 6
                                        text: parent.day.getDate()
                                        color: parent.isToday ? Theme.accent : Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 16
                                        font.bold: parent.isToday
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.pickDay(parent.parent.day) }
                                    }
                                }
                            }
                        }

                        // all-day strip
                        Row {
                            id: allDayRow
                            anchors.top: weekHead.bottom
                            anchors.topMargin: 6
                            x: weekView.gutter
                            height: 20
                            Repeater {
                                model: 7
                                Item {
                                    required property int index
                                    readonly property date day: root.addDays(root.weekStart, index)
                                    readonly property var items: weekView.occ.filter(o => o.ev.allDay && o.start < root.addDays(day, 1) && o.end > day)
                                    width: weekView.colW
                                    height: 20
                                    Rectangle {
                                        visible: parent.items.length > 0
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        radius: 2
                                        color: Theme.alpha(Theme.accent, 0.2)
                                        Text {
                                            x: 6
                                            width: parent.width - 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            elide: Text.ElideRight
                                            text: parent.parent.items.length ? parent.parent.items[0].ev.title + (parent.parent.items.length > 1 ? " +" + (parent.parent.items.length - 1) : "") : ""
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 9
                                        }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.pickOcc(parent.parent.items[0]) }
                                    }
                                }
                            }
                        }

                        Flickable {
                            id: timeline
                            anchors.top: allDayRow.bottom
                            anchors.topMargin: 6
                            anchors.bottom: parent.bottom
                            width: parent.width
                            clip: true
                            contentHeight: 24 * weekView.hourH
                            boundsBehavior: Flickable.StopAtBounds
                            Component.onCompleted: contentY = 7 * weekView.hourH
                            onVisibleChanged: if (visible) contentY = Math.max(0, Math.min(contentHeight - height, (clock.date.getHours() - 2) * weekView.hourH))

                            // hour lines + labels
                            Repeater {
                                model: 24
                                Item {
                                    required property int index
                                    y: index * weekView.hourH
                                    width: timeline.width
                                    height: weekView.hourH
                                    Text {
                                        y: -6
                                        width: weekView.gutter - 8
                                        horizontalAlignment: Text.AlignRight
                                        visible: index > 0
                                        text: Qt.formatTime(new Date(2000, 0, 1, index), "h AP")
                                        color: Theme.textFaint
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                    }
                                    Rectangle { x: weekView.gutter; width: parent.width - weekView.gutter; height: 1; color: Theme.alpha(Theme.border, 0.7) }
                                }
                            }

                            // day columns with event blocks
                            Repeater {
                                model: 7
                                Item {
                                    id: dayCol
                                    required property int index
                                    readonly property date day: root.addDays(root.weekStart, index)
                                    x: weekView.gutter + index * weekView.colW
                                    width: weekView.colW
                                    height: 24 * weekView.hourH

                                    // simple lane layout for overlapping events
                                    readonly property var blocks: {
                                        const a = day, b = root.addDays(day, 1)
                                        const items = weekView.occ.filter(o => !o.ev.allDay && o.start < b && o.end > a)
                                        const lanes = []
                                        const out = []
                                        for (const o of items) {
                                            const s = Math.max(0, (o.start - a) / 60000), e = Math.min(1440, (o.end - a) / 60000)
                                            let lane = 0
                                            while (lanes[lane] !== undefined && lanes[lane] > s) lane++
                                            lanes[lane] = e
                                            out.push({ o: o, s: s, e: e, lane: lane })
                                        }
                                        const n = Math.max(1, lanes.length)
                                        for (const b2 of out) b2.lanes = n
                                        return out
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        color: root.sameDay(dayCol.day, clock.date) ? Theme.alpha(Theme.accent, 0.04) : "transparent"
                                        border.width: 0
                                        Rectangle { width: 1; height: parent.height; color: Theme.alpha(Theme.border, 0.5) }
                                        MouseArea {
                                            anchors.fill: parent
                                            onDoubleClicked: mouse => {
                                                const min = Math.floor(mouse.y / weekView.hourH * 2) * 30
                                                root.pickDay(dayCol.day)
                                                root.newEvent(dayCol.day)
                                                form.startMin = min
                                                form.endMin = Math.min(min + 60, 1439)
                                            }
                                            onClicked: root.pickDay(dayCol.day)
                                        }
                                    }

                                    Repeater {
                                        model: dayCol.blocks
                                        Rectangle {
                                            id: block
                                            required property var modelData
                                            readonly property bool sel: root.selOcc !== null && root.selOcc.ev.uid === modelData.o.ev.uid
                                                && root.selOcc.start.getTime() === modelData.o.start.getTime()
                                            x: 2 + modelData.lane * (dayCol.width - 4) / modelData.lanes
                                            y: modelData.s / 60 * weekView.hourH + 1
                                            width: (dayCol.width - 4) / modelData.lanes - 2
                                            height: Math.max(18, (modelData.e - modelData.s) / 60 * weekView.hourH - 2)
                                            radius: 3
                                            color: sel ? Theme.alpha(Theme.accent, 0.45) : blockMouse.containsMouse ? Theme.alpha(Theme.accent, 0.32) : Theme.alpha(Theme.accent, 0.22)
                                            border.color: sel ? Theme.accent : "transparent"
                                            clip: true
                                            Rectangle { width: 2; height: parent.height; color: Theme.accent }
                                            Column {
                                                x: 7; y: 3
                                                width: parent.width - 10
                                                Text {
                                                    width: parent.width
                                                    elide: Text.ElideRight
                                                    text: block.modelData.o.ev.title || "(untitled)"
                                                    color: Theme.text
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    font.bold: true
                                                }
                                                Text {
                                                    visible: block.height > 34
                                                    width: parent.width
                                                    elide: Text.ElideRight
                                                    text: Qt.formatTime(block.modelData.o.start, "h:mm AP")
                                                        + (block.modelData.o.ev.location ? " · " + block.modelData.o.ev.location : "")
                                                    color: Theme.textDim
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 9
                                                }
                                            }
                                            MouseArea {
                                                id: blockMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.pickOcc(block.modelData.o)
                                            }
                                        }
                                    }
                                }
                            }

                            // now line
                            Rectangle {
                                readonly property int dayIdx: Math.round((new Date(clock.date.getFullYear(), clock.date.getMonth(), clock.date.getDate()) - root.weekStart) / 86400000)
                                visible: dayIdx >= 0 && dayIdx < 7
                                x: weekView.gutter + dayIdx * weekView.colW - 3
                                y: (clock.date.getHours() * 60 + clock.date.getMinutes()) / 60 * weekView.hourH - 1
                                width: weekView.colW + 3
                                height: 2
                                color: Theme.danger
                                Rectangle { width: 6; height: 6; radius: 3; y: -2; color: Theme.danger }
                            }
                        }
                    }

                    // ---------------- agenda ----------------
                    Flickable {
                        id: agendaView
                        visible: root.view === "agenda"
                        anchors.top: mainHead.bottom
                        anchors.topMargin: 16
                        anchors.bottom: parent.bottom
                        width: parent.width
                        clip: true
                        contentHeight: agendaCol.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        // [{ day, items }]
                        readonly property var groups: {
                            Calendar.revision
                            const now = new Date(clock.date.getFullYear(), clock.date.getMonth(), clock.date.getDate())
                            const occ = Calendar.occurrences(now, root.addDays(now, 60))
                            const out = []
                            for (const o of occ) {
                                const d = o.start < now ? now : o.start
                                const last = out[out.length - 1]
                                if (last && root.sameDay(last.day, d)) last.items.push(o)
                                else out.push({ day: new Date(d.getFullYear(), d.getMonth(), d.getDate()), items: [o] })
                            }
                            return out
                        }

                        Column {
                            id: agendaCol
                            width: parent.width
                            spacing: 16

                            Text {
                                visible: agendaView.groups.length === 0
                                text: "nothing in the next 60 days"
                                color: Theme.textFaint
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.italic: true
                            }

                            Repeater {
                                model: agendaView.groups
                                Row {
                                    id: group
                                    required property var modelData
                                    spacing: 18

                                    Column {
                                        width: 90
                                        Text {
                                            text: root.sameDay(group.modelData.day, clock.date) ? "TODAY"
                                                : root.sameDay(group.modelData.day, root.addDays(clock.date, 1)) ? "TOMORROW"
                                                : Qt.formatDate(group.modelData.day, "ddd").toUpperCase()
                                            color: root.sameDay(group.modelData.day, clock.date) ? Theme.accent : Theme.textDim
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            font.bold: true
                                            font.letterSpacing: 2
                                        }
                                        Text {
                                            text: Qt.formatDate(group.modelData.day, "dd MMM").toUpperCase()
                                            color: Theme.textFaint
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 9
                                        }
                                    }

                                    Column {
                                        width: agendaCol.width - 108
                                        spacing: 4
                                        Repeater {
                                            model: group.modelData.items
                                            Rectangle {
                                                id: arow
                                                required property var modelData
                                                width: parent.width
                                                height: 40
                                                radius: Theme.radius
                                                color: arowMouse.containsMouse ? Theme.bgCard : Theme.alpha(Theme.bgCard, 0.45)
                                                border.color: root.selOcc !== null && root.selOcc.ev.uid === modelData.ev.uid && root.selOcc.start.getTime() === modelData.start.getTime() ? Theme.accent : "transparent"
                                                Rectangle { width: 2; height: parent.height - 12; x: 6; anchors.verticalCenter: parent.verticalCenter; color: Theme.accent }
                                                Text {
                                                    x: 16
                                                    width: 150
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: Calendar.timeLabel(arow.modelData)
                                                    color: Theme.accent
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 9
                                                }
                                                Text {
                                                    x: 176
                                                    width: parent.width - 186
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    elide: Text.ElideRight
                                                    text: (arow.modelData.ev.title || "(untitled)") + (arow.modelData.ev.location ? "   ·   " + arow.modelData.ev.location : "")
                                                    color: Theme.text
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
                                                }
                                                MouseArea {
                                                    id: arowMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.pickOcc(arow.modelData)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle { width: 1; height: parent.height; color: Theme.border }

                // ======================================================= detail
                Item {
                    id: detail
                    width: 320
                    height: parent.height

                    // ---- selected day ----
                    Column {
                        visible: root.pane === "day"
                        width: parent.width
                        spacing: 12

                        readonly property var items: { Calendar.revision; return Calendar.onDay(root.selDay) }

                        Item {
                            width: parent.width
                            height: 30
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: (root.sameDay(root.selDay, clock.date) ? "TODAY  ·  " : "") + Qt.formatDate(root.selDay, "ddd dd MMM").toUpperCase()
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.letterSpacing: 2
                            }
                            HudButton {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                label: "+  NEW"
                                on: true
                                onClicked: root.newEvent(root.selDay)
                            }
                        }

                        Text {
                            visible: parent.items.length === 0
                            text: "nothing scheduled  ·  double-click a day to add"
                            color: Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.italic: true
                        }

                        Repeater {
                            model: parent.items
                            Rectangle {
                                id: drow
                                required property var modelData
                                width: detail.width
                                height: dcol.implicitHeight + 16
                                radius: Theme.radius
                                color: drowMouse.containsMouse ? Theme.bgCard : Theme.alpha(Theme.bgCard, 0.5)
                                Rectangle { width: 2; height: parent.height - 12; x: 6; anchors.verticalCenter: parent.verticalCenter; color: Theme.accent }
                                Column {
                                    id: dcol
                                    x: 16; y: 8
                                    width: parent.width - 26
                                    spacing: 3
                                    Text {
                                        text: Calendar.timeLabel(drow.modelData)
                                        color: Theme.accent
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                    }
                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: drow.modelData.ev.title || "(untitled)"
                                        color: Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.bold: true
                                    }
                                }
                                MouseArea {
                                    id: drowMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.pickOcc(drow.modelData)
                                }
                            }
                        }
                    }

                    // ---- event details ----
                    Flickable {
                        visible: root.pane === "event" && root.selOcc !== null
                        anchors.fill: parent
                        anchors.bottomMargin: 40
                        clip: true
                        contentHeight: evCol.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: evCol
                            width: parent.width
                            spacing: 14
                            readonly property var o: root.selOcc

                            HudButton { label: "‹  BACK"; onClicked: root.pane = "day" }

                            Text {
                                width: parent.width
                                wrapMode: Text.Wrap
                                text: evCol.o ? (evCol.o.ev.title || "(untitled)") : ""
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 20
                                font.bold: true
                            }

                            Text {
                                text: evCol.o ? root.relative(evCol.o).toUpperCase() : ""
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.bold: true
                                font.letterSpacing: 2
                            }

                            Rectangle { width: parent.width; height: 1; color: Theme.border }

                            Repeater {
                                model: evCol.o ? [
                                    ["󰃭", "DATE", Qt.formatDate(evCol.o.start, "dddd, dd MMMM yyyy")],
                                    ["󰥔", "TIME", evCol.o.ev.allDay ? "all day" : Qt.formatTime(evCol.o.start, "h:mm AP") + " – " + Qt.formatTime(evCol.o.end, "h:mm AP")],
                                    ["󱎫", "LENGTH", root.duration(evCol.o)],
                                    ["󰑖", "REPEAT", root.repeatText(evCol.o.ev)],
                                    ["󰂚", "REMIND", root.reminderText(evCol.o.ev)],
                                    ["󰍎", "WHERE", evCol.o.ev.location || "—"]
                                ] : []
                                Row {
                                    required property var modelData
                                    spacing: 10
                                    Text { text: modelData[0]; width: 16; color: Theme.textDim; font.family: Theme.iconFont; font.pixelSize: 13 }
                                    Text { text: modelData[1]; width: 60; color: Theme.textFaint; font.family: Theme.fontFamily; font.pixelSize: 9; font.letterSpacing: 2; anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: modelData[2]; width: detail.width - 96; wrapMode: Text.Wrap; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 11 }
                                }
                            }

                            Rectangle { visible: evCol.o !== null && evCol.o.ev.notes !== ""; width: parent.width; height: 1; color: Theme.border }

                            Text {
                                visible: evCol.o !== null && evCol.o.ev.notes !== ""
                                width: parent.width
                                wrapMode: Text.Wrap
                                text: evCol.o ? evCol.o.ev.notes : ""
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                lineHeight: 1.3
                            }

                            Text {
                                width: parent.width
                                elide: Text.ElideMiddle
                                text: evCol.o && evCol.o.ev.file ? evCol.o.ev.file.replace(Quickshell.env("HOME"), "~") : ""
                                color: Theme.textFaint
                                font.family: Theme.fontFamily
                                font.pixelSize: 8
                                topPadding: 8
                            }
                        }
                    }

                    Row {
                        visible: root.pane === "event" && root.selOcc !== null
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        spacing: 6
                        HudButton {
                            label: root.confirmDelete ? "CONFIRM DELETE" : (root.selOcc && root.selOcc.ev.repeat !== "none" ? "DELETE SERIES" : "DELETE")
                            danger: true
                            on: root.confirmDelete
                            onClicked: {
                                if (!root.confirmDelete) { root.confirmDelete = true; return }
                                Calendar.remove(root.selOcc.ev)
                                root.selOcc = null
                                root.pane = "day"
                            }
                        }
                        HudButton { label: "EDIT"; on: true; onClicked: { root.pane = "edit"; form.edit(root.selOcc.ev) } }
                    }

                    // ---- form ----
                    EventForm {
                        id: form
                        visible: root.pane === "edit"
                        width: parent.width
                        onClosed: { root.selDay = form.savedStart; root.selOcc = null; root.pane = "day" }
                    }
                }
            }
        }
    }
}
