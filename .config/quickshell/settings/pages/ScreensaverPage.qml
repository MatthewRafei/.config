import QtQuick
import Quickshell
import "../../screensaver/ScreensaverScenes.js" as Scenes
import qs
import qs.widgets

// Settings > Screensaver: timings and options (Idle.qml), and a card per
// scene: click to preview, the switch in its corner keeps it in or out of the
// random rotation.
// Previewing closes Settings and plays the scene (move the mouse to end it).
Item {
    id: page

    property int contentRightMargin: 48

    readonly property var scenes: Scenes.list().map(id => {
        const s = Scenes.get(id)
        return { id: id, name: s.name, gif: !!s.gif, kind: Scenes.kind(id) }
    })

    // the settings rows: label, choices, and how to read / write the value
    readonly property var rows: [
        { k: "SCREENSAVER", opts: [{ l: "ON", v: true }, { l: "OFF", v: false }],
          get: () => Idle.screensaver, set: v => Idle.screensaver = v },
        { k: "START AFTER", opts: [1, 2, 3, 5, 10, 15, 30].map(m => ({ l: m + "M", v: m })),
          get: () => Idle.screensaverMin, set: v => Idle.screensaverMin = v },
        { k: "CHANGE SCENE", opts: [{ l: "30S", v: 30 }, { l: "1M", v: 60 }, { l: "2M", v: 120 }, { l: "5M", v: 300 }, { l: "NEVER", v: 0 }],
          get: () => Idle.sceneSec, set: v => Idle.sceneSec = v },
        { k: "LOCK AFTER", opts: [2, 5, 10, 15, 30].map(m => ({ l: m + "M", v: m })).concat([{ l: "1H", v: 60 }, { l: "NEVER", v: 0 }]),
          get: () => Idle.lockMin, set: v => Idle.lockMin = v },
        { k: "SCREEN OFF", opts: [5, 10, 15, 30].map(m => ({ l: m + "M", v: m })).concat([{ l: "1H", v: 60 }, { l: "NEVER", v: 0 }]),
          get: () => Idle.screenOffMin, set: v => Idle.screenOffMin = v },
        { k: "ON BATTERY", opts: [{ l: "SCREENSAVER", v: true }, { l: "SKIP IT", v: false }],
          get: () => Idle.onBattery, set: v => Idle.onBattery = v },
        { k: "SHADERS ON BAT", opts: [{ l: "SKIP THEM", v: false }, { l: "PLAY THEM", v: true }],
          get: () => Idle.shadersOnBattery, set: v => Idle.shadersOnBattery = v },
        { k: "SCENE NAME", opts: [{ l: "SHOW", v: true }, { l: "HIDE", v: false }],
          get: () => Idle.showName, set: v => Idle.showName = v }
    ]

    function preview(id) {
        // close Settings first so the scene isn't drawn underneath it
        Quickshell.execDetached(["sh", "-c",
            "qs ipc call settings hide; sleep 0.4; qs ipc call screensaver "
            + (id ? "scene \"$1\"" : "start"), "sh", id || ""])
    }

    Column {
        anchors.fill: parent
        anchors.rightMargin: page.contentRightMargin
        spacing: 12

        // ---------------- header ----------------
        Row {
            width: parent.width
            height: 28
            spacing: 16

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "SCREENSAVER"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 18
                font.bold: true
                font.letterSpacing: 3
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: page.scenes.length + " SCENES"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.letterSpacing: 2
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.border }

        // ---------------- settings (Idle.qml) ----------------
        Rectangle {
            width: parent.width
            height: setCol.implicitHeight + 24
            radius: Theme.radius
            color: "transparent"
            border.color: Theme.border

            Column {
                id: setCol
                x: 14
                y: 12
                width: parent.width - 28
                spacing: 6

                Repeater {
                    model: page.rows
                    delegate: Row {
                        id: srow
                        required property var modelData
                        width: setCol.width
                        spacing: 12
                        Text {
                            width: 100
                            height: 22
                            verticalAlignment: Text.AlignVCenter
                            text: srow.modelData.k
                            color: Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.letterSpacing: 1
                        }
                        Flow {
                            width: parent.width - 112
                            spacing: 4
                            Repeater {
                                model: srow.modelData.opts
                                HudButton {
                                    required property var modelData
                                    label: modelData.l
                                    on: srow.modelData.get() === modelData.v
                                    onClicked: srow.modelData.set(modelData.v)
                                }
                            }
                        }
                    }
                }

                // settings that don't add up
                Text {
                    width: parent.width
                    visible: text !== ""
                    wrapMode: Text.Wrap
                    topPadding: 2
                    text: Idle.screensaver && Idle.lockMin > 0 && Idle.lockMin <= Idle.screensaverMin
                          ? "Locks at or before the screensaver would start, so you'll see the lock screen instead."
                        : Idle.screensaver && Idle.screenOffMin > 0 && Idle.screenOffMin <= Idle.screensaverMin
                          ? "The screen turns off before the screensaver would start."
                        : ""
                    color: Theme.accent2
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                Row {
                    spacing: 8
                    topPadding: 4
                    HudButton {
                        label: "▶  PREVIEW RANDOM"
                        on: true
                        onClicked: page.preview("")
                    }
                    HudButton {
                        label: Caffeine.on ? "󰅶  CAFFEINE ON" : "󰛊  CAFFEINE OFF"
                        on: Caffeine.on
                        onClicked: Caffeine.toggle()
                    }
                }
            }
        }

        Text {
            text: "click a scene to preview it  ·  the switch keeps it in or out of the rotation"
            color: Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: 10
        }

        // ---------------- scene cards, by kind ----------------
        Flickable {
            width: parent.width
            height: parent.height - y
            contentHeight: groups.implicitHeight
            clip: true

            Column {
                id: groups
                width: parent.width
                spacing: 14

                Repeater {
                    // ASCII: text the CPU redraws 10-20 times a second. Shader: the
                    // GPU draws every pixel each frame, heavier on a laptop battery.
                    model: [
                        { title: "ASCII", kinds: ["drawn", "gif"], note: "text drawn by the CPU, 10-20 times a second · light" },
                        { title: "SHADER", kinds: ["shader"], note: "drawn by the GPU every frame · heavier"
                            + (Idle.shadersOnBattery ? "" : " · skipped on battery") }
                    ]
                    delegate: Column {
                        id: group
                        required property var modelData
                        readonly property var members: page.scenes.filter(x => modelData.kinds.indexOf(x.kind) >= 0)
                        visible: members.length > 0
                        width: groups.width
                        spacing: 8

                        Row {
                            width: parent.width
                            spacing: 10
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "// " + group.modelData.title + " SCENES  ·  "
                                    + group.members.filter(x => Idle.sceneEnabled(x.id)).length + " OF " + group.members.length + " IN ROTATION"
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.letterSpacing: 2
                            }
                            HudButton {
                                label: "ALL"
                                onClicked: { for (const x of group.members) Idle.setSceneEnabled(x.id, true) }
                            }
                            HudButton {
                                label: "NONE"
                                onClicked: { for (const x of group.members) Idle.setSceneEnabled(x.id, false) }
                            }
                        }
                        Text {
                            text: group.modelData.note
                            color: Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.letterSpacing: 1
                        }

                        Flow {
                            id: cards
                            width: parent.width
                            spacing: 8

                            Repeater {
                                model: group.members
                                delegate: Rectangle {
                                    id: card
                                    required property var modelData
                                    width: (cards.width - 2 * cards.spacing) / 3
                                    height: 58
                                    radius: Theme.radius
                                    readonly property bool inRotation: Idle.sceneEnabled(modelData.id)
                                    opacity: inRotation ? 1 : 0.5
                                    color: cardMouse.containsMouse ? Theme.alpha(Theme.accent, 0.10) : "transparent"
                                    border.color: cardMouse.containsMouse ? Theme.accent : Theme.border
                                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                                    Text {
                                        id: cardIcon
                                        x: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        // shader, hand-drawn, or made from a GIF / image
                                        text: card.modelData.kind === "shader" ? "󰢮" : card.modelData.gif ? "󰵸" : "󰏘"
                                        color: cardMouse.containsMouse ? Theme.accent : Theme.textDim
                                        font.family: Theme.iconFont
                                        font.pixelSize: 16
                                    }

                                    Column {
                                        anchors.left: cardIcon.right
                                        anchors.leftMargin: 10
                                        anchors.right: parent.right
                                        anchors.rightMargin: 40
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 3

                                        Text {
                                            width: parent.width
                                            elide: Text.ElideRight
                                            text: card.modelData.name
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                        Text {
                                            width: parent.width
                                            elide: Text.ElideRight
                                            text: cardMouse.containsMouse ? "▶ PREVIEW"
                                                : (card.modelData.kind === "shader" ? "SHADER" : card.modelData.gif ? "GIF" : "DRAWN") + "  ·  " + card.modelData.id
                                            color: cardMouse.containsMouse ? Theme.accent : Theme.textFaint
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 9
                                            font.letterSpacing: 1
                                        }
                                    }

                                    // in the random rotation or not
                                    Rectangle {
                                        z: 2
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 7
                                        width: 26
                                        height: 14
                                        radius: 7
                                        color: card.inRotation ? Theme.accent : Theme.trackBg
                                        border.color: Theme.border
                                        Rectangle {
                                            width: 10
                                            height: 10
                                            radius: 5
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: card.inRotation ? parent.width - width - 2 : 2
                                            color: Theme.text
                                            Behavior on x { NumberAnimation { duration: Theme.animFast } }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -4
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Idle.setSceneEnabled(card.modelData.id, !card.inRotation)
                                        }
                                    }

                                    MouseArea {
                                        id: cardMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: page.preview(card.modelData.id)
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
