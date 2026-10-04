import QtQuick
import Quickshell
import "../"
import "../ScreensaverScenes.js" as Scenes

// Settings > Screensaver: when it starts, and a card per scene to preview it.
// Previewing closes Settings and plays the scene (move the mouse to end it).
Item {
    id: page

    property int contentRightMargin: 48

    readonly property var scenes: Scenes.list().map(id => {
        const s = Scenes.get(id)
        return { id: id, name: s.name, gif: !!s.gif }
    })

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

        // ---------------- timing + caffeine ----------------
        Rectangle {
            width: parent.width
            height: infoCol.implicitHeight + 24
            radius: Theme.radius
            color: "transparent"
            border.color: Theme.border

            Column {
                id: infoCol
                x: 14
                y: 12
                width: parent.width - 28
                spacing: 8

                Repeater {
                    model: [
                        { k: "STARTS", v: "after 3 min idle, a random scene, changing every minute" },
                        { k: "LOCKS", v: "after 5 min idle" },
                        { k: "PAUSED BY", v: "video and games (idle inhibitors), and Caffeine" }
                    ]
                    delegate: Row {
                        required property var modelData
                        spacing: 12
                        Text {
                            width: 90
                            text: modelData.k
                            color: Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.letterSpacing: 1
                        }
                        Text {
                            text: modelData.v
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }
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
            text: "// SCENES  ·  click one to preview it"
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.letterSpacing: 2
        }

        // ---------------- scene cards ----------------
        Flickable {
            width: parent.width
            height: parent.height - y
            contentHeight: cards.implicitHeight
            clip: true

            Flow {
                id: cards
                width: parent.width
                spacing: 8

                Repeater {
                    model: page.scenes
                    delegate: Rectangle {
                        id: card
                        required property var modelData
                        width: (cards.width - 2 * cards.spacing) / 3
                        height: 58
                        radius: Theme.radius
                        color: cardMouse.containsMouse ? Theme.alpha(Theme.accent, 0.10) : "transparent"
                        border.color: cardMouse.containsMouse ? Theme.accent : Theme.border
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        Text {
                            id: cardIcon
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            // hand-drawn scenes vs. ones made from a GIF / image
                            text: card.modelData.gif ? "󰵸" : "󰏘"
                            color: cardMouse.containsMouse ? Theme.accent : Theme.textDim
                            font.family: Theme.iconFont
                            font.pixelSize: 16
                        }

                        Column {
                            anchors.left: cardIcon.right
                            anchors.leftMargin: 10
                            anchors.right: parent.right
                            anchors.rightMargin: 10
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
                                    : (card.modelData.gif ? "GIF" : "DRAWN") + "  ·  " + card.modelData.id
                                color: cardMouse.containsMouse ? Theme.accent : Theme.textFaint
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.letterSpacing: 1
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
