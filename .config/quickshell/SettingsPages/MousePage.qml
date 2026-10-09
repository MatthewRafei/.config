import QtQuick
import Quickshell
import "../"

// Pointer speed, scrolling, buttons and the cursor itself. Options apply at
// once and are saved to ~/.config/hypr/settings.lua (../Input.qml); the cursor
// is rebuilt by ~/.config/theme/cursor/cursor-accent and follows the wallpaper.
Item {
    id: page

    property int rightMargin: 36

    Component.onCompleted: Input.refresh()

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
    // a labelled on/off row
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

            // header
            Item {
                width: parent.width
                height: 28
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "MOUSE"
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
                text: "Mouse settings here are for Hyprland. On niri, set them in config.kdl (input { mouse { … } })."
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

            // ------------------------------------------------ pointer
            Column {
                visible: Compositor.hyprland && Input.loaded
                width: parent.width
                spacing: 14

                Section { text: "POINTER" }

                Item {
                    width: parent.width
                    height: 50
                    Slider {
                        id: sens
                        anchors.fill: parent
                        property real v: Input.opt("input:sensitivity", 0)
                        label: "SPEED  ·  " + (v > 0 ? "+" : "") + v.toFixed(2)
                        icon: "󰍽"
                        value: (v + 1) / 2
                        onMoved: value => v = Math.round((value * 2 - 1) * 20) / 20
                        onCommitted: value => Input.set("input:sensitivity", Math.round((value * 2 - 1) * 20) / 20)
                    }
                }

                Row {
                    spacing: 6
                    RowLabel { text: "ACCELERATION" }
                    Repeater {
                        model: [{ v: "flat", l: "OFF (FLAT)" }, { v: "adaptive", l: "ON (ADAPTIVE)" }]
                        Chip {
                            required property var modelData
                            label: modelData.l
                            current: (Input.opt("input:accel_profile", "") || "adaptive") === modelData.v
                            onClicked: Input.set("input:accel_profile", modelData.v)
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 50
                    Slider {
                        anchors.fill: parent
                        property real v: Input.opt("input:scroll_factor", 1)
                        label: "SCROLL SPEED  ·  " + v.toFixed(1) + "×"
                        icon: "󰍽"
                        // 0.1× .. 3×
                        value: (v - 0.1) / 2.9
                        onMoved: value => v = Math.round((0.1 + value * 2.9) * 10) / 10
                        onCommitted: value => Input.set("input:scroll_factor", Math.round((0.1 + value * 2.9) * 10) / 10)
                    }
                }

                Switch {
                    label: "Natural scrolling"
                    hint: "Content follows the wheel, like a touchscreen"
                    on: Input.opt("input:natural_scroll", false)
                    onToggled: Input.set("input:natural_scroll", !on)
                }
                Switch {
                    label: "Left-handed"
                    hint: "Swap the left and right buttons, and mirror the cursor"
                    on: Input.opt("input:left_handed", false)
                    onToggled: {
                        const left = !on
                        Input.set("input:left_handed", left)
                        Input.setCursor(["hand", left ? "left" : "right"])
                    }
                }
                Switch {
                    label: "Focus follows mouse"
                    hint: "Windows get the keyboard as the pointer moves over them"
                    on: Input.opt("input:follow_mouse", 1) !== 0
                    onToggled: Input.set("input:follow_mouse", on ? 0 : 1)
                }
                Switch {
                    label: "Hide while typing"
                    hint: "The cursor disappears on a key press and comes back when the mouse moves"
                    on: Input.opt("cursor:hide_on_key_press", false)
                    onToggled: Input.set("cursor:hide_on_key_press", !on)
                }
            }

            // ------------------------------------------------ touchpad
            Column {
                visible: Compositor.hyprland && Input.loaded && Input.touchpad
                width: parent.width
                spacing: 14

                Section { text: "TOUCHPAD" }
                Switch {
                    label: "Tap to click"
                    on: Input.opt("input:touchpad:tap_to_click", true)
                    onToggled: Input.set("input:touchpad:tap_to_click", !on)
                }
                Switch {
                    label: "Natural scrolling"
                    on: Input.opt("input:touchpad:natural_scroll", true)
                    onToggled: Input.set("input:touchpad:natural_scroll", !on)
                }
                Switch {
                    label: "Off while typing"
                    on: Input.opt("input:touchpad:disable_while_typing", true)
                    onToggled: Input.set("input:touchpad:disable_while_typing", !on)
                }
                Item {
                    width: parent.width
                    height: 50
                    Slider {
                        anchors.fill: parent
                        property real v: Input.opt("input:touchpad:scroll_factor", 1)
                        label: "SCROLL SPEED  ·  " + v.toFixed(1) + "×"
                        icon: "󰟸"
                        value: (v - 0.1) / 2.9
                        onMoved: value => v = Math.round((0.1 + value * 2.9) * 10) / 10
                        onCommitted: value => Input.set("input:touchpad:scroll_factor", Math.round((0.1 + value * 2.9) * 10) / 10)
                    }
                }
            }

            // ------------------------------------------------ cursor
            Column {
                visible: Input.cursor !== null
                width: parent.width
                spacing: 12

                Row {
                    spacing: 14
                    Section { text: "CURSOR" }
                    Text {
                        anchors.bottom: parent.bottom
                        text: Input.cursorBusy ? "BUILDING…" : "SAME IN EVERY APP"
                        color: Input.cursorBusy ? Theme.accent : Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.letterSpacing: 2
                    }
                }

                Row {
                    spacing: 6
                    RowLabel { text: "COLOUR" }
                    Repeater {
                        model: [{ v: "wallpaper", l: "WALLPAPER" }, { v: "fixed", l: "CUSTOM" }, { v: "off", l: "PLAIN" }]
                        Chip {
                            required property var modelData
                            label: modelData.l
                            current: Input.cursor && Input.cursor.mode === modelData.v
                            onClicked: if (!current) Input.setCursor(["mode", modelData.v])
                        }
                    }
                }

                // custom colour: swatches from the palette, or any hex
                Row {
                    visible: Input.cursor && Input.cursor.mode === "fixed"
                    spacing: 6
                    RowLabel { text: "" }
                    Repeater {
                        model: [String(Theme.accent), String(Theme.accent2), "#ffffff", "#ff003c", "#00ff9c", "#3fa9ff", "#ffd400"]
                        Rectangle {
                            required property string modelData
                            readonly property bool current: Input.cursor && String(Input.cursor.color).toLowerCase() === modelData.toLowerCase()
                            width: 28; height: 28
                            radius: Theme.radius
                            color: modelData
                            border.width: current ? 2 : 1
                            border.color: current ? Theme.text : Theme.border
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Input.setCursor(["color", parent.modelData])
                            }
                        }
                    }
                    HudField {
                        width: 110
                        height: 28
                        placeholder: "#rrggbb ↵"
                        onAccepted: {
                            const t = text.trim()
                            if (/^#[0-9a-fA-F]{6}$/.test(t)) { Input.setCursor(["color", t]); text = "" }
                        }
                    }
                }

                Row {
                    visible: Input.cursor && Input.cursor.mode !== "off"
                    spacing: 6
                    RowLabel { text: "STYLE" }
                    Repeater {
                        model: [{ v: "outline", l: "DARK · COLOUR EDGE" }, { v: "filled", l: "COLOUR · DARK EDGE" }]
                        Chip {
                            required property var modelData
                            label: modelData.l
                            current: Input.cursor && Input.cursor.style === modelData.v
                            onClicked: if (!current) Input.setCursor(["style", modelData.v])
                        }
                    }
                }
                Row {
                    visible: Input.cursor && Input.cursor.mode !== "off"
                    spacing: 6
                    RowLabel { text: "SHAPE" }
                    Repeater {
                        model: [{ v: "modern", l: "ROUNDED" }, { v: "original", l: "SHARP" }]
                        Chip {
                            required property var modelData
                            label: modelData.l
                            current: Input.cursor && Input.cursor.shape === modelData.v
                            onClicked: if (!current) Input.setCursor(["shape", modelData.v])
                        }
                    }
                }
                Row {
                    spacing: 6
                    RowLabel { text: "SIZE" }
                    Repeater {
                        model: [24, 32, 48, 64]
                        Chip {
                            required property int modelData
                            label: String(modelData)
                            current: Input.cursor && Input.cursor.size === modelData
                            onClicked: if (!current) Input.setCursor(["size", modelData])
                        }
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "Bibata cursor, rebuilt for Hyprland, GTK, Qt and XWayland apps alike, and recoloured whenever the wallpaper changes. "
                        + "Apps already open pick up a new size when restarted."
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }
            }
        }
    }
}
