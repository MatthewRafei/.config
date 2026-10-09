import QtQuick
import qs

// Time box for the event form. Type a time ("9", "930", "9:30pm", "21:30"),
// scroll over it or press Up/Down for ±15 min (Shift: ±1 h), or pick from the
// ▾ list. Typing something that isn't a time puts the last good value back.
//
//   minutes      minutes after midnight; bind it, the box never assigns it
//   relativeTo   when >= 0, list entries show the length from that time
//                (used by the end box: "7:30 PM  1h 30m")
//   bad          draw it red (the form's validation)
//   picked(m)    the user chose a time; the owner updates `minutes` (or not)
//   accepted()   Enter was pressed
//   refresh()    show `minutes` again (after the owner rejected a pick)
Item {
    id: tf

    property int minutes: 9 * 60
    property int relativeTo: -1
    property bool bad: false
    property bool open: false
    property bool typing: false
    signal picked(int m)
    signal accepted()

    width: 108
    height: 30

    function parseTime(s) {
        const m = String(s).trim().toLowerCase().match(/^(\d{1,2})(?::?(\d{2}))?\s*([ap])?\.?m?\.?$/)
        if (!m) return -1
        let h = +m[1], min = +(m[2] || 0)
        if (min > 59 || h > 23) return -1
        if (m[3] === "p" && h < 12) h += 12
        if (m[3] === "a" && h === 12) h = 0
        return h * 60 + min
    }

    function fmt(min) {
        return Qt.formatTime(new Date(2000, 0, 1, Math.floor(min / 60), min % 60), "h:mm AP")
    }

    function fmtLength(min) {
        const h = Math.floor(min / 60), m = min % 60
        return (h ? h + "h" : "") + (h && m ? " " : "") + (m || !h ? m + "m" : "")
    }

    function show(m) { input.text = fmt(m); typing = false }
    function refresh() { show(minutes) }

    // from a scroll, key or list pick
    function set(m) {
        m = ((m % 1440) + 1440) % 1440
        show(m)
        picked(m)
    }

    // typed text: a time is picked, anything else puts the current value back
    function commit() {
        if (!typing) return
        const t = parseTime(input.text)
        show(t >= 0 ? t : minutes)
        if (t >= 0) picked(t)
    }

    function focusInput() { input.forceActiveFocus() }

    onMinutesChanged: if (!typing) show(minutes)
    Component.onCompleted: show(minutes)

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.bgCard
        border.color: tf.bad ? Theme.danger : input.activeFocus || tf.open ? Theme.accent : Theme.border

        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 22
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: tf.bad ? Theme.danger : Theme.text
            selectionColor: Theme.alpha(Theme.accent, 0.4)
            selectByMouse: true
            font.family: Theme.fontFamily
            font.pixelSize: 11
            onTextEdited: { tf.typing = true; tf.open = false }
            onEditingFinished: tf.commit()
            onAccepted: { tf.commit(); tf.open = false; tf.accepted() }
            onActiveFocusChanged: if (activeFocus) selectAll(); else tf.open = false
            Keys.onUpPressed: event => tf.set(tf.minutes + (event.modifiers & Qt.ShiftModifier ? 60 : 15))
            Keys.onDownPressed: event => tf.set(tf.minutes - (event.modifiers & Qt.ShiftModifier ? 60 : 15))
            // Esc closes the list; otherwise it goes on to the panel (cancel / close)
            Keys.onEscapePressed: event => {
                if (tf.open) tf.open = false
                else event.accepted = false
            }
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: "▾"
            color: tf.open || arrowMouse.containsMouse ? Theme.accent : Theme.textFaint
            font.pixelSize: 11
        }

        MouseArea {
            id: arrowMouse
            anchors.right: parent.right
            width: 24
            height: parent.height
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { tf.commit(); input.forceActiveFocus(); tf.open = !tf.open }
        }

        // scrolling snaps to the 15-minute grid first, then steps by 15
        WheelHandler {
            onWheel: event => {
                const up = event.angleDelta.y > 0
                const off = tf.minutes % 15
                tf.set(off === 0 ? tf.minutes + (up ? 15 : -15) : tf.minutes + (up ? 15 - off : -off))
            }
        }
    }

    // ---- ▾ list: every 15 minutes ----
    Rectangle {
        visible: tf.open
        y: tf.height + 4
        width: Math.max(tf.width, tf.relativeTo >= 0 ? 170 : tf.width)
        height: 200
        z: 100
        radius: Theme.radius
        color: Theme.bgPanel
        border.color: Theme.accent

        onVisibleChanged: if (visible) list.positionViewAtIndex(Math.round(tf.minutes / 15) % 96, ListView.Center)

        ListView {
            id: list
            anchors.fill: parent
            anchors.margins: 3
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: 96

            delegate: Rectangle {
                id: slot
                required property int index
                readonly property int min: index * 15
                readonly property bool cur: min === tf.minutes
                width: list.width
                height: 22
                radius: 2
                color: cur ? Theme.alpha(Theme.accent, 0.2) : slotMouse.containsMouse ? Theme.bgCard : "transparent"

                Text {
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: tf.fmt(slot.min)
                    color: slot.cur ? Theme.accent : Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.bold: slot.cur
                }
                Text {
                    visible: tf.relativeTo >= 0
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property int len: (slot.min - tf.relativeTo + 1440) % 1440
                    text: len === 0 ? "" : tf.fmtLength(len) + (slot.min <= tf.relativeTo ? " ↷" : "")
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                }
                MouseArea {
                    id: slotMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { tf.set(slot.min); tf.open = false }
                }
            }
        }
    }
}
