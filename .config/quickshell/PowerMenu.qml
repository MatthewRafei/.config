import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Power menu: dimmed overlay with five HUD tiles.
//
//   L lock   S suspend   E log out   R reboot   P shut down
//   ← → / Tab to move, Enter to choose, Esc or click outside to close.
//
// Log out / reboot / shut down need a second press to confirm.
// Opened by the bar's ⏻ or `qs ipc call power toggle`.
PanelWindow {
    id: root

    property bool open: false
    property int current: 0
    property int armed: -1          // index waiting for confirmation

    readonly property var actions: [
        { key: "L", label: "LOCK",      icon: "󰌾", confirm: false, cmd: ["qs", "ipc", "call", "lock", "lock"] },
        { key: "S", label: "SUSPEND",   icon: "󰤄", confirm: false, cmd: ["loginctl", "suspend"] },
        { key: "E", label: "LOG OUT",   icon: "󰍃", confirm: true,  cmd: null },  // null: Compositor.quit()
        { key: "R", label: "REBOOT",    icon: "󰜉", confirm: true,  cmd: ["loginctl", "reboot"] },
        { key: "P", label: "SHUT DOWN", icon: "󰐥", confirm: true,  cmd: ["loginctl", "poweroff"] }
    ]

    function show() { current = 0; armed = -1; open = true }
    function hide() { open = false; armed = -1 }

    function choose(i) {
        const a = actions[i]
        if (a.confirm && armed !== i) {
            armed = i
            current = i
            disarm.restart()
            return
        }
        hide()
        // let the overlay fade before locking/suspending
        runLater.cmd = a.cmd
        runLater.restart()
    }

    Timer {
        id: runLater
        property var cmd: []
        interval: 180
        onTriggered: cmd ? Quickshell.execDetached(cmd) : Compositor.quit()
    }

    Timer {
        id: disarm
        interval: 3000
        onTriggered: root.armed = -1
    }

    IpcHandler {
        target: "power"
        function toggle(): void { root.open ? root.hide() : root.show() }
        function open(): void { root.show() }
    }

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-power"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    visible: open || backdrop.opacity > 0

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Theme.alpha(Theme.bgPanel, 0.78)
        opacity: root.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }

        MouseArea {
            anchors.fill: parent
            onClicked: root.hide()
        }

        Canvas {
            anchors.fill: parent
            opacity: 0.5
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = "rgba(0,0,0,0.3)"
                for (let y = 0; y < height; y += 3)
                    ctx.fillRect(0, y, width, 1)
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 26
            scale: root.open ? 1 : 0.96
            Behavior on scale { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "// POWER"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.letterSpacing: 4
            }

            Row {
                id: tiles
                spacing: 14
                focus: root.open

                Keys.onPressed: event => {
                    const k = event.key
                    if (k === Qt.Key_Escape) root.hide()
                    else if (k === Qt.Key_Left || k === Qt.Key_H || k === Qt.Key_Backtab)
                        root.current = (root.current + root.actions.length - 1) % root.actions.length
                    else if (k === Qt.Key_Right || k === Qt.Key_Tab)
                        root.current = (root.current + 1) % root.actions.length
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space)
                        root.choose(root.current)
                    else {
                        const t = event.text.toUpperCase()
                        const i = root.actions.findIndex(a => a.key === t)
                        if (i < 0) return
                        root.choose(i)
                    }
                    event.accepted = true
                }

                Repeater {
                    model: root.actions

                    Rectangle {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property bool focused: root.current === index
                        readonly property bool armed: root.armed === index
                        readonly property color tint: armed ? Theme.danger : Theme.accent

                        width: 132
                        height: 132
                        radius: Theme.radius
                        color: armed ? Theme.alpha(Theme.danger, 0.14)
                             : focused ? Theme.alpha(Theme.accent, 0.10)
                             : Theme.alpha(Theme.bgCard, 0.9)
                        border.width: 1
                        border.color: armed || focused ? tint : Theme.border
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                        // accent edge-stripe on the focused tile
                        Rectangle {
                            visible: tile.focused || tile.armed
                            width: 2
                            height: parent.height - 24
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            color: tile.tint
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 12

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tile.modelData.icon
                                color: tile.armed || tile.focused ? tile.tint : Theme.textDim
                                font.family: Theme.iconFont
                                font.pixelSize: 34
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tile.armed ? "AGAIN?" : tile.modelData.label
                                color: tile.armed ? Theme.danger : tile.focused ? Theme.text : Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.bold: tile.focused || tile.armed
                                font.letterSpacing: 2
                            }
                        }

                        // key hint
                        Text {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 9
                            text: tile.modelData.key
                            color: tile.focused ? tile.tint : Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.current = tile.index
                            onClicked: root.choose(tile.index)
                        }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.armed >= 0
                    ? "PRESS " + root.actions[root.armed].key + " OR ENTER AGAIN TO CONFIRM"
                    : "← →  SELECT    ENTER  CHOOSE    ESC  CLOSE"
                color: root.armed >= 0 ? Theme.danger : Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.letterSpacing: 2
            }
        }
    }
}
