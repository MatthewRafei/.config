import Quickshell
import Quickshell.Wayland
import QtQuick

// Music EQ widget, bottom left (AudioFx.qml). Opened from the bar's EQ chip.
//
//   genre presets   click to apply (also turns the EQ on)
//   sliders         drag, scroll for ±0.5 dB, double-click for 0
//   curve           the response the sliders add up to (drawn approximately)
//   save            name the current curve as your own preset (× deletes)
//
//   qs ipc call eq panel
PanelWindow {
    id: root

    readonly property bool open: AudioFx.panelOpen

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-eq"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    visible: open || card.opacity > 0

    MouseArea {
        anchors.fill: parent
        onClicked: AudioFx.panelOpen = false
    }

    function fmtFreq(f) { return f >= 1000 ? (f / 1000) + "k" : String(f) }
    function fmtDb(v) { return (v > 0 ? "+" : "") + (Number.isInteger(v) ? v : v.toFixed(1)) }

    Rectangle {
        id: card
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 14
        width: 560
        height: col.implicitHeight + 32
        radius: 6
        color: Theme.alpha(Theme.bgPanel, 0.96)
        border.color: Theme.accent
        focus: root.open
        Keys.onEscapePressed: AudioFx.panelOpen = false

        opacity: root.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }
        transform: Translate {
            y: root.open ? 0 : 24
            Behavior on y { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }
        }

        MouseArea { anchors.fill: parent }    // clicks on the card don't close it

        // HUD corner marks, like Settings
        Rectangle { width: 30; height: 2; color: Theme.accent2; anchors { top: parent.top; left: parent.left; margins: 10 } }
        Rectangle { width: 2; height: 30; color: Theme.accent2; anchors { top: parent.top; left: parent.left; margins: 10 } }

        Column {
            id: col
            x: 18
            y: 16
            width: parent.width - 36
            spacing: 12

            // ---------------- header
            Item {
                width: parent.width
                height: 26
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "EQUALIZER"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                        font.letterSpacing: 3
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (AudioFx.preset || "CUSTOM").toUpperCase()
                        color: AudioFx.eqOn ? Theme.accent : Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.letterSpacing: 2
                    }
                }
                // on / off
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 22
                    radius: 11
                    color: AudioFx.eqOn ? Theme.accent : Theme.trackBg
                    border.color: Theme.border
                    Rectangle {
                        width: 16; height: 16; radius: 8
                        anchors.verticalCenter: parent.verticalCenter
                        x: AudioFx.eqOn ? parent.width - width - 3 : 3
                        color: Theme.text
                        Behavior on x { NumberAnimation { duration: Theme.animFast } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: AudioFx.setOn(!AudioFx.eqOn)
                    }
                }
            }

            // ---------------- genres
            Flow {
                width: parent.width
                spacing: 4
                Repeater {
                    model: AudioFx.genres
                    HudButton {
                        required property var modelData
                        label: modelData.name.toUpperCase()
                        on: AudioFx.preset === modelData.name
                        onClicked: AudioFx.applyPreset(modelData.name)
                    }
                }
            }

            // ---------------- sliders over the response curve
            Item {
                id: eqArea
                width: parent.width
                height: 190
                opacity: AudioFx.eqOn ? 1 : 0.45
                Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

                readonly property real labelW: 30
                readonly property real plotW: width - labelW
                readonly property real plotTop: 18
                readonly property real plotH: height - plotTop - 22
                function yOf(db) { return plotTop + (1 - (db + AudioFx.maxDb) / (2 * AudioFx.maxDb)) * plotH }
                function colX(i) { return labelW + (i + 0.5) * plotW / 10 }

                // dB grid
                Repeater {
                    model: [12, 6, 0, -6, -12]
                    Item {
                        required property int modelData
                        width: eqArea.width
                        y: eqArea.yOf(modelData)
                        Rectangle {
                            x: eqArea.labelW
                            width: eqArea.plotW
                            height: 1
                            color: modelData === 0 ? Theme.alpha(Theme.text, 0.18) : Theme.alpha(Theme.text, 0.06)
                        }
                        Text {
                            anchors.verticalCenter: parent.top
                            text: (modelData > 0 ? "+" : "") + modelData
                            color: Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }
                    }
                }

                // approximate response: each band a bell about 1.2 octaves wide
                Canvas {
                    id: curve
                    anchors.fill: parent
                    property var g: AudioFx.gains
                    onGChanged: requestPaint()
                    onPaint: {
                        const c = getContext("2d")
                        c.reset()
                        const n = 120, x0 = eqArea.colX(0), x1 = eqArea.colX(9)
                        const pts = []
                        for (let k = 0; k <= n; k++) {
                            const pos = k / n * 9 - 0.25 + 0.5 * k / n   // band index, a little past both ends
                            let db = 0
                            for (let i = 0; i < 10; i++) {
                                const d = pos - i
                                db += g[i] * Math.exp(-d * d / (2 * 0.42 * 0.42))
                            }
                            pts.push([x0 + (pos) * (x1 - x0) / 9, eqArea.yOf(Math.max(-AudioFx.maxDb, Math.min(AudioFx.maxDb, db)))])
                        }
                        c.beginPath()
                        c.moveTo(pts[0][0], eqArea.yOf(0))
                        for (const p of pts) c.lineTo(p[0], p[1])
                        c.lineTo(pts[pts.length - 1][0], eqArea.yOf(0))
                        c.closePath()
                        c.fillStyle = Theme.css(Theme.accent, 0.12)
                        c.fill()
                        c.beginPath()
                        pts.forEach((p, i) => i ? c.lineTo(p[0], p[1]) : c.moveTo(p[0], p[1]))
                        c.strokeStyle = Theme.css(Theme.accent, 0.9)
                        c.lineWidth = 2
                        c.stroke()
                    }
                }

                // one vertical slider per band
                Repeater {
                    model: 10
                    Item {
                        id: band
                        required property int index
                        readonly property real v: AudioFx.gains[index]
                        x: eqArea.colX(index) - width / 2
                        width: eqArea.plotW / 10
                        height: eqArea.height

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 0
                            text: root.fmtDb(band.v)
                            color: band.v !== 0 ? Theme.text : Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.bold: drag.pressed
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: eqArea.plotTop
                            width: 3
                            height: eqArea.plotH
                            radius: 1.5
                            color: Theme.alpha(Theme.text, 0.08)
                        }
                        // fill from 0 dB to the value
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: Math.min(eqArea.yOf(0), eqArea.yOf(band.v))
                            width: 3
                            height: Math.abs(eqArea.yOf(band.v) - eqArea.yOf(0))
                            color: Theme.accent
                        }
                        Rectangle {
                            id: knob
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: eqArea.yOf(band.v) - height / 2
                            width: 16
                            height: 10
                            radius: 2
                            color: drag.pressed || drag.containsMouse ? Theme.accent : Theme.text
                            border.color: Theme.bgPanel
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            text: root.fmtFreq(AudioFx.freqs[band.index])
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                        }
                        MouseArea {
                            id: drag
                            anchors.fill: parent
                            anchors.topMargin: eqArea.plotTop - 8
                            anchors.bottomMargin: 14
                            hoverEnabled: true
                            cursorShape: Qt.SizeVerCursor
                            function dbAt(my) {
                                const y = my + anchors.topMargin
                                return (1 - (y - eqArea.plotTop) / eqArea.plotH) * 2 * AudioFx.maxDb - AudioFx.maxDb
                            }
                            onPressed: mouse => AudioFx.setGain(band.index, dbAt(mouse.y))
                            onPositionChanged: mouse => { if (pressed) AudioFx.setGain(band.index, dbAt(mouse.y)) }
                            onDoubleClicked: AudioFx.setGain(band.index, 0)
                            onWheel: wheel => AudioFx.setGain(band.index, band.v + (wheel.angleDelta.y > 0 ? 0.5 : -0.5))
                        }
                    }
                }
            }

            // ---------------- your presets
            Flow {
                visible: Object.keys(AudioFx.userPresets).length > 0
                width: parent.width
                spacing: 4
                Repeater {
                    model: Object.keys(AudioFx.userPresets).sort()
                    Rectangle {
                        id: up
                        required property string modelData
                        readonly property bool cur: AudioFx.preset === modelData
                        width: upRow.implicitWidth + 16
                        height: 26
                        radius: Theme.radius
                        color: cur ? Theme.alpha(Theme.accent, 0.15) : upMouse.containsMouse ? Theme.bgCard : "transparent"
                        border.color: cur || upMouse.containsMouse ? Theme.accent : Theme.border
                        MouseArea {
                            id: upMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: AudioFx.applyPreset(up.modelData)
                        }
                        Row {
                            id: upRow
                            anchors.centerIn: parent
                            spacing: 8
                            Text {
                                text: up.modelData.toUpperCase()
                                color: up.cur ? Theme.accent : Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.bold: up.cur
                                font.letterSpacing: 1
                            }
                            Text {
                                text: "×"
                                color: xMouse.containsMouse ? Theme.danger : Theme.textFaint
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                MouseArea {
                                    id: xMouse
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: AudioFx.deleteUser(up.modelData)
                                }
                            }
                        }
                    }
                }
            }

            // ---------------- footer: save, reset, where it plays
            Row {
                width: parent.width
                spacing: 6
                HudField {
                    id: nameField
                    width: 160
                    placeholder: "name this curve ↵"
                    onAccepted: { AudioFx.saveUser(text); text = "" }
                }
                HudButton {
                    label: "SAVE"
                    onClicked: { AudioFx.saveUser(nameField.text); nameField.text = "" }
                }
                HudButton {
                    label: "RESET"
                    onClicked: AudioFx.applyPreset("Flat")
                }
                Text {
                    width: parent.width - x
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideLeft
                    text: !AudioFx.eeRunning ? "starting EasyEffects…"
                        : "preamp " + root.fmtDb(AudioFx.preamp) + " dB  ·  → " + (AudioFx.calibrated ? "calibrated speakers" : AudioFx.outputName)
                    color: AudioFx.eeRunning ? Theme.textFaint : Theme.danger
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                }
            }
        }
    }
}
