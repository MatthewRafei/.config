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

    function newEvent() { mode = "edit"; form.startNew(selected) }
    function editEvent(ev) { mode = "edit"; form.edit(ev) }

    // ================================================================ UI
    MouseArea { anchors.fill: parent; onClicked: root.close() }

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
                    HudButton { label: "‹"; onClicked: root.shiftMonth(-1) }
                    HudButton {
                        label: "TODAY"
                        onClicked: { root.selected = new Date(); root.viewYear = root.selected.getFullYear(); root.viewMonth = root.selected.getMonth() }
                    }
                    HudButton { label: "›"; onClicked: root.shiftMonth(1) }
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
                        readonly property bool isSel: root.sameDay(day, root.mode === "edit" ? form.date : root.selected)
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
                                if (root.mode === "edit") form.date = cell.day
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
                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        HudButton {
                            label: "OPEN ⤢"
                            onClicked: { Calendar.panelOpen = false; Calendar.windowOpen = true }
                        }
                        HudButton { label: "+  NEW"; on: true; onClicked: root.newEvent() }
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
            EventForm {
                id: form
                visible: root.mode === "edit"
                width: parent.width
                onClosed: { root.selected = form.savedStart; root.mode = "day" }
            }
        }
    }
}
