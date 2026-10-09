import QtQuick
import qs.widgets
import Quickshell
import qs

// Key repeat, module sections (the typing test), layout, a few xkb options, and
// every Hyprland shortcut, which can be moved to another key combo or switched off. Options save to
// ~/.config/hypr/settings.lua, shortcuts to keybinds.lua (../Input.qml).
Item {
    id: page

    property int rightMargin: 36
    property string filter: ""
    property string recording: ""      // orig combo of the bind being re-recorded
    property string recordingDesc: ""
    property string conflict: ""

    Component.onCompleted: Input.refresh()
    Component.onDestruction: if (Input.capturing) Input.capture(false)

    function kbOptions() {
        return String(Input.opt("input:kb_options", "")).split(",").filter(x => x !== "")
    }
    function hasOption(o) { return kbOptions().indexOf(o) >= 0 }
    // replace every option in `group` with `value` ("" removes them)
    function setOption(group, value) {
        const list = kbOptions().filter(x => group.indexOf(x) < 0)
        if (value) list.push(value)
        Input.set("input:kb_options", list.join(","))
    }

    function startRecording(b) {
        conflict = ""
        recording = b.orig
        recordingDesc = b.description
        Input.capture(true)
        catcher.forceActiveFocus()
        recordTimeout.restart()
    }
    function stopRecording() {
        recordTimeout.stop()
        if (Input.capturing) Input.capture(false)
        recording = ""
    }
    function finishRecording(combo) {
        const orig = recording, desc = recordingDesc
        stopRecording()
        const clash = Input.binds.find(x => !x.disabled && Input.sameCombo(x.combo, combo) && x.orig !== orig)
        if (clash) {
            conflict = combo + " is already " + (clash.description || clash.orig) + ". Move or switch that one off first."
            return
        }
        Input.remap(orig, combo, desc)
    }
    Timer { id: recordTimeout; interval: 10000; onTriggered: page.stopRecording() }

    // takes the keys while recording (Hyprland's binds are paused meanwhile)
    Item {
        id: catcher
        Keys.onPressed: event => {
            if (page.recording === "") return
            event.accepted = true
            if (event.key === Qt.Key_Escape && event.modifiers === Qt.NoModifier) { page.stopRecording(); return }
            const combo = Input.comboOf(event)
            if (combo !== "") page.finishRecording(combo)
        }
    }

    // ------------------------------------------------------------ pieces
    component Chip: Rectangle {
        id: chip
        property string label
        property bool current: false
        signal clicked()
        width: Math.max(chipText.implicitWidth + 22, 58)
        height: 28
        radius: Theme.radius
        color: current ? Theme.alpha(Theme.accent, 0.14) : chipMouse.containsMouse ? Theme.bgCard : "transparent"
        border.width: 1
        border.color: current || chipMouse.containsMouse ? Theme.accent : Theme.border
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            color: chip.current ? Theme.accent : Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.bold: chip.current
            font.letterSpacing: 1
        }
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }
    component Switch: Item {
        id: sw
        property string label
        property string hint
        property bool on: false
        signal toggled()
        width: parent ? parent.width : 0
        height: hint ? 40 : 28
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 60
            spacing: 3
            Text {
                text: sw.label
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }
            Text {
                visible: sw.hint !== ""
                width: parent.width
                elide: Text.ElideRight
                text: sw.hint
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }
        }
        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            height: 22
            radius: 11
            color: sw.on ? Theme.accent : Theme.trackBg
            border.color: Theme.border
            Rectangle {
                width: 16; height: 16; radius: 8
                anchors.verticalCenter: parent.verticalCenter
                x: sw.on ? parent.width - width - 3 : 3
                color: Theme.text
                Behavior on x { NumberAnimation { duration: Theme.animFast } }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: sw.toggled()
            }
        }
    }
    component Section: Text {
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.bold: true
        font.letterSpacing: 2
        topPadding: 6
    }
    component RowLabel: Text {
        width: 110
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 10
        font.letterSpacing: 2
    }
    // one key of a combo, drawn as a keycap
    component Keycap: Rectangle {
        property string label
        property bool lit: false
        width: Math.max(capText.implicitWidth + 12, 22)
        height: 20
        radius: Theme.radius
        color: lit ? Theme.alpha(Theme.accent, 0.16) : Theme.alpha(Theme.text, 0.05)
        border.color: lit ? Theme.accent : Theme.borderAccent
        Text {
            id: capText
            anchors.centerIn: parent
            text: parent.label
            color: parent.lit ? Theme.accent : Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 9
            font.bold: true
        }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width - page.rightMargin
            spacing: 14

            Item {
                width: parent.width
                height: 28
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "KEYBOARD"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    font.bold: true
                    font.letterSpacing: 3
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰑐"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 22
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Input.refresh()
                    }
                }
            }
            Rectangle { width: parent.width; height: 1; color: Theme.border }

            Text {
                visible: !Compositor.hyprland
                width: parent.width
                wrapMode: Text.Wrap
                text: "Keyboard settings here are for Hyprland. On niri, set them in config.kdl (input { keyboard { … } } and binds { … })."
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }
            Text {
                visible: Input.error !== ""
                width: parent.width
                wrapMode: Text.Wrap
                text: Input.error
                color: Theme.danger
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }

            Column {
                visible: Compositor.hyprland && Input.loaded
                width: parent.width
                spacing: 14

                // ------------------------------------------------ typing
                Section { text: "TYPING" }
                Item {
                    width: parent.width
                    height: 50
                    Slider {
                        anchors.fill: parent
                        property real v: Input.opt("input:repeat_delay", 300)
                        label: "REPEAT AFTER  ·  " + Math.round(v) + " ms"
                        icon: "󰌌"
                        // 150 .. 1000 ms
                        value: (v - 150) / 850
                        onMoved: value => v = Math.round((150 + value * 850) / 10) * 10
                        onCommitted: value => Input.set("input:repeat_delay", Math.round((150 + value * 850) / 10) * 10)
                    }
                }
                Item {
                    width: parent.width
                    height: 50
                    Slider {
                        anchors.fill: parent
                        property real v: Input.opt("input:repeat_rate", 50)
                        label: "REPEAT SPEED  ·  " + Math.round(v) + " / s"
                        icon: "󰌌"
                        // 10 .. 100 per second
                        value: (v - 10) / 90
                        onMoved: value => v = Math.round(10 + value * 90)
                        onCommitted: value => Input.set("input:repeat_rate", Math.round(10 + value * 90))
                    }
                }
                HudField {
                    width: parent.width
                    placeholder: "hold a key here to try the repeat"
                }

                // sections from modules (the typing test …)
                ModuleSections { page: "Keyboard"; width: parent.width }

                // ------------------------------------------------ layout
                Section { text: "LAYOUT" }
                Row {
                    spacing: 8
                    RowLabel { text: "LAYOUT" }
                    HudField {
                        id: layoutField
                        width: 150
                        text: Input.opt("input:kb_layout", "us")
                        placeholder: "us  or  us,de"
                        onAccepted: if (/^[a-z]{2,3}(,[a-z]{2,3})*$/.test(text.trim())) Input.set("input:kb_layout", text.trim())
                    }
                    RowLabel { text: "VARIANT"; width: 70 }
                    HudField {
                        width: 150
                        text: Input.opt("input:kb_variant", "")
                        placeholder: "e.g. colemak ↵"
                        onAccepted: if (/^[a-z0-9_,-]*$/.test(text.trim())) Input.set("input:kb_variant", text.trim())
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "xkb names, Enter to apply. Several layouts separated by commas switch with the options below."
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                Row {
                    spacing: 6
                    RowLabel { text: "CAPS LOCK" }
                    Repeater {
                        model: [{ v: "", l: "CAPS LOCK" }, { v: "ctrl:nocaps", l: "CTRL" }, { v: "caps:escape", l: "ESCAPE" }, { v: "caps:backspace", l: "BACKSPACE" }]
                        Chip {
                            required property var modelData
                            label: modelData.l
                            current: modelData.v === "" ? !["ctrl:nocaps", "caps:escape", "caps:backspace"].some(o => page.hasOption(o))
                                                        : page.hasOption(modelData.v)
                            onClicked: page.setOption(["ctrl:nocaps", "caps:escape", "caps:backspace"], modelData.v)
                        }
                    }
                }
                Row {
                    visible: String(Input.opt("input:kb_layout", "")).indexOf(",") >= 0
                    spacing: 6
                    RowLabel { text: "SWITCH LAYOUT" }
                    Repeater {
                        model: [{ v: "grp:alt_shift_toggle", l: "ALT+SHIFT" }, { v: "grp:win_space_toggle", l: "SUPER+SPACE" }, { v: "grp:caps_toggle", l: "CAPS LOCK" }]
                        Chip {
                            required property var modelData
                            label: modelData.l
                            current: page.hasOption(modelData.v)
                            onClicked: page.setOption(["grp:alt_shift_toggle", "grp:win_space_toggle", "grp:caps_toggle"], current ? "" : modelData.v)
                        }
                    }
                }
                Switch {
                    label: "Swap Alt and Super"
                    hint: "For Mac-style keyboards"
                    on: page.hasOption("altwin:swap_alt_win")
                    onToggled: page.setOption(["altwin:swap_alt_win"], on ? "" : "altwin:swap_alt_win")
                }
                Switch {
                    label: "Compose key on Right Alt"
                    hint: "Right Alt, then ' and e types é"
                    on: page.hasOption("compose:ralt")
                    onToggled: page.setOption(["compose:ralt"], on ? "" : "compose:ralt")
                }
                Switch {
                    label: "Num Lock on at login"
                    on: Input.opt("input:numlock_by_default", false)
                    onToggled: Input.set("input:numlock_by_default", !on)
                }

                // ------------------------------------------------ shortcuts
                Item {
                    width: parent.width
                    height: 34
                    Section { anchors.bottom: parent.bottom; text: "SHORTCUTS" }
                    Text {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        visible: Input.binds.some(b => b.moved)
                        text: "RESET ALL"
                        color: resetAllMouse.containsMouse ? Theme.danger : Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.letterSpacing: 2
                        MouseArea {
                            id: resetAllMouse
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Input.resetAll()
                        }
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: page.recording !== "" ? "Press the new shortcut for “" + page.recordingDesc + "”  ·  Esc cancels"
                        : page.conflict !== "" ? page.conflict
                        : "Click a shortcut to record a new one. Other shortcuts are paused while it records."
                    color: page.recording !== "" ? Theme.accent : page.conflict !== "" ? Theme.danger : Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }
                HudField {
                    width: parent.width
                    placeholder: "search shortcuts…"
                    onTextChanged: page.filter = text.trim().toLowerCase()
                }

                Column {
                    width: parent.width
                    spacing: 2
                    Repeater {
                        model: Input.binds.filter(b => page.filter === ""
                            || (b.description + " " + b.combo + " " + b.orig).toLowerCase().indexOf(page.filter) >= 0)
                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            readonly property var b: modelData
                            readonly property bool rec: page.recording === b.orig
                            width: col.width
                            height: 32
                            radius: Theme.radius
                            color: rec ? Theme.alpha(Theme.accent, 0.12) : rowMouse.containsMouse ? Theme.bgCard : "transparent"
                            border.width: rec ? 1 : 0
                            border.color: Theme.accent
                            opacity: b.disabled ? 0.5 : 1

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: row.b.mouse ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onClicked: {
                                    if (row.rec) page.stopRecording()
                                    else if (!row.b.mouse && !row.b.disabled) page.startRecording(row.b)
                                }
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - keys.width - actions.width - 40
                                elide: Text.ElideRight
                                text: (row.b.description || row.b.orig) + (row.b.moved && !row.b.disabled ? "   · was " + row.b.orig : "")
                                color: row.b.moved ? Theme.accent : Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }

                            Row {
                                id: keys
                                anchors.right: actions.left
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3
                                Text {
                                    visible: row.rec || row.b.disabled === true
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.rec ? "PRESS KEYS…" : "OFF"
                                    color: row.rec ? Theme.accent : Theme.textFaint
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.bold: true
                                    font.letterSpacing: 1
                                }
                                Repeater {
                                    model: row.rec || row.b.disabled ? [] : Input.caps(row.b.combo)
                                    Keycap {
                                        required property string modelData
                                        label: modelData
                                        lit: row.b.moved
                                    }
                                }
                            }

                            // reset (moved) and on / off
                            Row {
                                id: actions
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Repeater {
                                    model: [
                                        { icon: "󰑓", show: row.b.moved, tip: "reset" },
                                        { icon: row.b.disabled ? "󰐊" : "󰅖", show: true, tip: row.b.disabled ? "on" : "off" }
                                    ]
                                    Rectangle {
                                        required property var modelData
                                        width: 24; height: 22
                                        radius: Theme.radius
                                        opacity: modelData.show ? 1 : 0
                                        color: actMouse.containsMouse ? Theme.bgCard : "transparent"
                                        border.color: actMouse.containsMouse ? (modelData.tip === "off" ? Theme.danger : Theme.accent) : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: parent.modelData.icon
                                            color: actMouse.containsMouse ? (parent.modelData.tip === "off" ? Theme.danger : Theme.accent) : Theme.textFaint
                                            font.family: Theme.iconFont
                                            font.pixelSize: 12
                                        }
                                        MouseArea {
                                            id: actMouse
                                            anchors.fill: parent
                                            enabled: parent.modelData.show
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                const t = parent.modelData.tip
                                                if (t === "reset" || t === "on") Input.reset(row.b.orig)
                                                else Input.disable(row.b.orig, row.b.description)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
